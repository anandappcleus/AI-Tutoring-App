"""
RAG corpus ingestion pipeline — PDF → chunks → embeddings → Chroma

Usage (from backend/ directory):
    python -m app.rag.ingest --dir rag/corpus/
    python -m app.rag.ingest --dir rag/corpus/ --subject physics --batch-size 32
    python -m app.rag.ingest --dir rag/corpus/ --dry-run   # count chunks only

What it does:
    1. Reads all PDF files in --dir (recursive)
    2. Extracts text page-by-page using pypdf
    3. Splits each page into 512-token chunks with 50-token overlap
       (approximated as 2048 chars / 200 chars overlap)
    4. Embeds chunks in batches using NIM nv-embedqa-e5-v5
    5. Upserts to Chroma collection "jee_corpus" with metadata {source, page, subject}
    6. Uses deterministic chunk IDs → safe to re-run (idempotent)
"""

from __future__ import annotations

import argparse
import hashlib
import logging
import sys
from pathlib import Path

import chromadb
from pypdf import PdfReader

from app.config import get_settings
from app.rag.embedder import Embedder
from app.logging_config import configure_logging

log = logging.getLogger(__name__)

# Chunking parameters (character-based approximation: 1 token ≈ 4 chars)
CHUNK_CHARS = 2048   # ≈ 512 tokens
OVERLAP_CHARS = 200  # ≈ 50 tokens
MIN_CHUNK_CHARS = 80 # discard near-empty chunks (headers, page numbers, etc.)

COLLECTION_NAME = "jee_corpus"


# ── Text utilities ────────────────────────────────────────────────────

def _extract_pages(pdf_path: Path) -> list[tuple[int, str]]:
    """Return list of (page_number, text) for every page in the PDF."""
    try:
        reader = PdfReader(str(pdf_path))
    except Exception:
        log.error("Failed to open PDF: %s", pdf_path.name, exc_info=True)
        return []
    pages: list[tuple[int, str]] = []
    for i, page in enumerate(reader.pages, start=1):
        try:
            text = page.extract_text() or ""
        except Exception:
            log.warning("Could not extract text from page %d of %s", i, pdf_path.name)
            continue
        text = text.strip()
        if text:
            pages.append((i, text))
    return pages


def _chunk_text(text: str) -> list[str]:
    """Split text into overlapping character windows."""
    chunks: list[str] = []
    start = 0
    while start < len(text):
        end = start + CHUNK_CHARS
        chunk = text[start:end].strip()
        if len(chunk) >= MIN_CHUNK_CHARS:
            chunks.append(chunk)
        start += CHUNK_CHARS - OVERLAP_CHARS
    return chunks


def _chunk_id(source: str, page: int, index: int) -> str:
    """Deterministic chunk ID — safe to re-run (idempotent upsert)."""
    raw = f"{source}::p{page}::c{index}"
    return hashlib.md5(raw.encode()).hexdigest()


def _infer_subject(pdf_path: Path) -> str:
    """Best-effort subject tag from filename.

    Handles full-word names ('jee_physics_2023.pdf') and NCERT 2-letter
    subject codes embedded after a 2-char series prefix, e.g.:
      keph101.pdf  → ke + ph + 101 → physics
      lech202.pdf  → le + ch + 202 → chemistry
      kemh103.pdf  → ke + mh + 103 → mathematics
      lebi101.pdf  → le + bi + 101 → biology
    """
    import re

    stem = pdf_path.stem.lower()

    # Full-word match (custom filenames)
    for subject in ("physics", "chemistry", "mathematics", "maths", "biology", "botany", "zoology"):
        if subject in stem:
            return subject

    # NCERT abbreviation: 2-char series prefix + 2-char subject code + digits
    _NCERT_CODES = {"ph": "physics", "ch": "chemistry", "mh": "mathematics", "bi": "biology"}
    m = re.match(r"[a-z]{2}(ph|ch|mh|bi)\d", stem)
    if m:
        return _NCERT_CODES[m.group(1)]

    return "general"


# ── Core pipeline ─────────────────────────────────────────────────────

def ingest_pdf(
    pdf_path: Path,
    collection: chromadb.Collection,
    embedder: Embedder,
    subject_override: str | None,
    batch_size: int,
    dry_run: bool,
) -> int:
    """Process a single PDF. Returns number of chunks upserted."""
    subject = subject_override or _infer_subject(pdf_path)
    source = pdf_path.name

    pages = _extract_pages(pdf_path)
    if not pages:
        log.warning("No extractable text in %s — skipping", pdf_path.name)
        return 0

    # Build all chunks with metadata
    all_chunks: list[dict] = []
    for page_num, page_text in pages:
        for idx, chunk_text in enumerate(_chunk_text(page_text)):
            all_chunks.append(
                {
                    "id": _chunk_id(source, page_num, idx),
                    "text": chunk_text,
                    "metadata": {"source": source, "page": page_num, "subject": subject},
                }
            )

    log.info("  %s  pages=%d  chunks=%d  subject=%s", source, len(pages), len(all_chunks), subject)

    if dry_run or not all_chunks:
        return len(all_chunks)

    # Embed + upsert in batches
    total_batches = -(-len(all_chunks) // batch_size)
    for i in range(0, len(all_chunks), batch_size):
        batch = all_chunks[i : i + batch_size]
        texts = [c["text"] for c in batch]
        batch_num = i // batch_size + 1
        try:
            embeddings = embedder.embed_passages(texts)
            collection.upsert(
                ids=[c["id"] for c in batch],
                documents=texts,
                embeddings=embeddings,
                metadatas=[c["metadata"] for c in batch],
            )
        except Exception:
            log.error(
                "ingest_pdf  upsert failed  file=%s  batch=%d/%d",
                source,
                batch_num,
                total_batches,
                exc_info=True,
            )
            raise
        log.debug("  upserted batch %d/%d", batch_num, total_batches)

    return len(all_chunks)


def ingest_directory(
    corpus_dir: Path,
    subject_override: str | None = None,
    batch_size: int = 32,
    dry_run: bool = False,
) -> None:
    """Ingest all PDFs found under corpus_dir."""
    settings = get_settings()

    pdf_files = sorted(corpus_dir.rglob("*.pdf"))
    if not pdf_files:
        # Raise so callers (including __main__) can decide how to handle it
        raise FileNotFoundError(f"No PDF files found in {corpus_dir}")

    log.info(
        "Starting ingestion  dir=%s  files=%d  dry_run=%s",
        corpus_dir,
        len(pdf_files),
        dry_run,
    )

    if not dry_run:
        try:
            chroma_client = chromadb.PersistentClient(path=settings.CHROMA_PERSIST_DIR)
            collection = chroma_client.get_or_create_collection(
                name=COLLECTION_NAME,
                metadata={"hnsw:space": "cosine"},
            )
        except Exception:
            log.error(
                "ingest_directory  Chroma init failed  path=%s",
                settings.CHROMA_PERSIST_DIR,
                exc_info=True,
            )
            raise
        embedder = Embedder()
    else:
        collection = None  # type: ignore[assignment]
        embedder = None    # type: ignore[assignment]

    total_chunks = 0
    failed: list[str] = []
    for pdf_path in pdf_files:
        try:
            total_chunks += ingest_pdf(
                pdf_path, collection, embedder, subject_override, batch_size, dry_run
            )
        except Exception:
            log.error("Skipping %s due to error", pdf_path.name, exc_info=True)
            failed.append(pdf_path.name)
    if failed:
        log.warning("Ingestion finished with %d failed file(s): %s", len(failed), failed)

    if dry_run:
        log.info("DRY RUN — total chunks that would be ingested: %d", total_chunks)
    else:
        log.info(
            "Ingestion complete  total_chunks=%d  collection=%s",
            total_chunks,
            COLLECTION_NAME,
        )


# ── CLI entry point ───────────────────────────────────────────────────

def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Ingest JEE/NEET/WBCHSE PDFs into the Chroma vector store."
    )
    parser.add_argument(
        "--dir",
        type=Path,
        default=Path(__file__).resolve().parents[3] / "rag" / "corpus",
        help="Directory containing PDF files (default: rag/corpus/)",
    )
    parser.add_argument(
        "--subject",
        type=str,
        default=None,
        help="Override subject tag for all files in --dir (e.g. physics)",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=32,
        help="Embedding batch size sent to NIM API (default: 32)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Count chunks without embedding or writing to Chroma",
    )
    return parser.parse_args()


if __name__ == "__main__":
    configure_logging(level="INFO", env="development")
    args = _parse_args()
    try:
        ingest_directory(
            corpus_dir=args.dir,
            subject_override=args.subject,
            batch_size=args.batch_size,
            dry_run=args.dry_run,
        )
    except FileNotFoundError as exc:
        log.error("%s", exc)
        sys.exit(1)
    except Exception:
        log.error("Ingestion failed with unexpected error", exc_info=True)
        sys.exit(2)
