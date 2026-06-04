"""
Retriever — similarity search abstraction over Chroma (dev) or Pinecone (prod).

Usage:
    retriever = get_retriever()
    chunks = retriever.search("Newton's second law", top_k=5)
    # returns: [{"text": ..., "source": ..., "page": ..., "subject": ..., "score": ...}, ...]

    # With metadata filtering (restricts to JEE Physics corpus):
    chunks = retriever.search("refraction", top_k=5, exam_filter="JEE", subject_filter="physics")

    # With hybrid BM25+dense retrieval (enabled by settings.BM25_ENABLED):
    chunks = retriever.search("Newton's second law", top_k=5)  # BM25 fused automatically

The factory function `get_retriever()` reads VECTOR_DB from settings:
    "chroma"   → ChromaRetriever   (local, zero cost — default for dev)
    "pinecone" → PineconeRetriever (managed — Sprint 9)
"""

from __future__ import annotations

import logging
import time
from abc import ABC, abstractmethod

import chromadb

from app.config import get_settings
from app.rag.embedder import Embedder

log = logging.getLogger(__name__)

COLLECTION_NAME = "jee_corpus"


# ── Abstract base ─────────────────────────────────────────────────────

class BaseRetriever(ABC):
    @abstractmethod
    def search(
        self,
        query: str,
        top_k: int = 5,
        exam_filter: str | None = None,
        subject_filter: str | None = None,
    ) -> list[dict]:
        """Return top_k relevant chunks for the query.

        Args:
            query:          Search query string (may be HyDE-rewritten upstream).
            top_k:          Number of final chunks to return.
            exam_filter:    Optional exam type filter ("JEE" | "NEET" | "WBCHSE").
                            Mapped to the Chroma metadata field ``exam_type``.
            subject_filter: Optional subject filter ("physics" | "chemistry" | etc.).
                            Mapped to the Chroma metadata field ``subject``.
        """


# ── Chroma implementation ─────────────────────────────────────────────

class ChromaRetriever(BaseRetriever):
    """Local Chroma vector store — used in development."""

    def __init__(self, persist_dir: str | None = None) -> None:
        settings = get_settings()
        path = persist_dir or settings.CHROMA_PERSIST_DIR
        try:
            self._client = chromadb.PersistentClient(path=path)
            self._collection = self._client.get_or_create_collection(
                name=COLLECTION_NAME,
                metadata={"hnsw:space": "cosine"},
            )
        except Exception as exc:
            log.error(
                "ChromaRetriever init failed  collection=%s  path=%s  error=%s",
                COLLECTION_NAME,
                path,
                exc,
                # exc_info omitted — full traceback logged once at tool level
            )
            raise
        self._embedder = Embedder()
        log.info(
            "ChromaRetriever ready  collection=%s  path=%s  docs=%d",
            COLLECTION_NAME,
            path,
            self._collection.count(),
        )

    def search(
        self,
        query: str,
        top_k: int = 5,
        exam_filter: str | None = None,
        subject_filter: str | None = None,
    ) -> list[dict]:
        """
        Hybrid dense+sparse retrieval with optional metadata pre-filtering.

        Pipeline:
          1. Build an optional Chroma ``where`` clause from exam_filter / subject_filter.
          2. Dense search: embed the query and query Chroma for top-20 candidates.
          3. Sparse search: BM25Okapi over the full collection for top-20 candidates
             (enabled when settings.BM25_ENABLED=True; skipped otherwise).
          4. Fuse with Reciprocal Rank Fusion (k=60) → sorted combined ranking.
          5. Return the top top_k chunks (with metadata and scores).

        Note: metadata filters are applied at the dense retrieval stage only.
        BM25 searches the full corpus but typically has high overlap with the
        filtered dense results, so the final top_k quality remains high.
        """
        s = get_settings()
        t0 = time.perf_counter()

        log.info(
            "retriever.search_start  query=%r  top_k=%d  exam=%s  subject=%s  bm25=%s",
            query[:80], top_k, exam_filter, subject_filter, s.BM25_ENABLED,
        )

        # ── Embed query ───────────────────────────────────────────────
        t_embed = time.perf_counter()
        query_vec = self._embedder.embed_query(query)
        embed_ms = (time.perf_counter() - t_embed) * 1_000

        # ── Build optional Chroma where clause ────────────────────────
        where_clause = self._build_where(exam_filter, subject_filter)
        if where_clause:
            log.debug("retriever.where_clause  clause=%s", where_clause)

        # ── Dense retrieval (top-20 candidates) ───────────────────────
        fetch_k = max(top_k * 4, 20)  # fetch more candidates for fusion
        t_dense = time.perf_counter()
        dense_chunks = self._dense_search(query_vec, fetch_k, where_clause)
        dense_ms = (time.perf_counter() - t_dense) * 1_000
        dense_id_to_chunk = {c["_id"]: c for c in dense_chunks}
        dense_ids = [c["_id"] for c in dense_chunks]

        if not s.BM25_ENABLED:
            # No fusion — trim dense results directly
            result = [dense_id_to_chunk[did] for did in dense_ids[:top_k]]
            total_ms = (time.perf_counter() - t0) * 1_000
            log.info(
                "retriever.search_done  pipeline=dense_only  exam=%s  subject=%s"
                "  dense_hits=%d  returned=%d  embed_ms=%.0f  dense_ms=%.0f  total_ms=%.0f",
                exam_filter, subject_filter,
                len(dense_ids), len(result), embed_ms, dense_ms, total_ms,
            )
            return self._strip_internal_id(result)

        # ── Sparse retrieval (BM25 top-20) ────────────────────────────
        from app.rag.bm25_index import get_bm25_index
        bm25 = get_bm25_index(self._collection)
        t_sparse = time.perf_counter()
        sparse_ids = bm25.search(query, top_k=fetch_k)
        sparse_ms = (time.perf_counter() - t_sparse) * 1_000

        # ── RRF fusion ────────────────────────────────────────────────
        from app.rag.bm25_index import rrf_fuse
        fused_ids = rrf_fuse(dense_ids, sparse_ids)

        # Count BM25-only hits (not in dense results)
        bm25_only_ids = [sid for sid in sparse_ids if sid not in dense_id_to_chunk]

        # Reconstruct chunk dicts: dense hits are already fetched with full text+meta.
        # BM25-only hits (not in dense) are fetched individually from Chroma.
        result: list[dict] = []
        seen: set[str] = set()
        fetched_extra = 0
        for doc_id in fused_ids:
            if len(result) >= top_k:
                break
            if doc_id in seen:
                continue
            seen.add(doc_id)
            if doc_id in dense_id_to_chunk:
                result.append(dense_id_to_chunk[doc_id])
            else:
                # BM25-only hit — fetch text + meta from Chroma
                extra = self._fetch_by_id(doc_id)
                if extra:
                    result.append(extra)
                    fetched_extra += 1

        total_ms = (time.perf_counter() - t0) * 1_000
        log.info(
            "retriever.search_done  pipeline=hybrid  exam=%s  subject=%s"
            "  dense_hits=%d  sparse_hits=%d  fused=%d  bm25_only_hits=%d"
            "  extra_fetched=%d  returned=%d"
            "  embed_ms=%.0f  dense_ms=%.0f  sparse_ms=%.0f  total_ms=%.0f",
            exam_filter, subject_filter,
            len(dense_ids), len(sparse_ids), len(fused_ids), len(bm25_only_ids),
            fetched_extra, len(result),
            embed_ms, dense_ms, sparse_ms, total_ms,
        )
        return self._strip_internal_id(result)

    # ── Internal helpers ──────────────────────────────────────────────

    @staticmethod
    def _build_where(
        exam_filter: str | None,
        subject_filter: str | None,
    ) -> dict | None:
        """Construct a Chroma ``where`` filter dict, or None if no filters."""
        conditions: list[dict] = []
        if exam_filter:
            conditions.append({"exam_type": {"$eq": exam_filter}})
        if subject_filter:
            conditions.append({"subject": {"$eq": subject_filter.lower()}})
        if not conditions:
            return None
        return {"$and": conditions} if len(conditions) > 1 else conditions[0]

    def _dense_search(
        self,
        query_vec: list[float],
        fetch_k: int,
        where_clause: dict | None,
    ) -> list[dict]:
        """Run a Chroma vector query, returning chunks with internal ``_id`` field."""
        kwargs: dict = dict(
            query_embeddings=[query_vec],
            n_results=min(fetch_k, self._collection.count() or 1),
            include=["documents", "metadatas", "distances"],
        )
        if where_clause:
            kwargs["where"] = where_clause
        try:
            results = self._collection.query(**kwargs)
        except Exception:
            log.error(
                "ChromaRetriever._dense_search failed  fetch_k=%d", fetch_k, exc_info=True
            )
            raise

        chunks: list[dict] = []
        for doc_id, text, meta, dist in zip(
            results["ids"][0],
            results["documents"][0],
            results["metadatas"][0],
            results["distances"][0],
        ):
            chunks.append({
                "_id": doc_id,
                "text": text,
                "source": meta.get("source", ""),
                "page": meta.get("page", 0),
                "subject": meta.get("subject", ""),
                "exam_type": meta.get("exam_type", ""),
                "score": round(1.0 - dist, 4),
            })
        return chunks

    def _fetch_by_id(self, doc_id: str) -> dict | None:
        """Fetch a single document from Chroma by ID (used for BM25-only hits)."""
        try:
            result = self._collection.get(
                ids=[doc_id],
                include=["documents", "metadatas"],
            )
            if not result["ids"]:
                return None
            meta = result["metadatas"][0]
            return {
                "_id": doc_id,
                "text": result["documents"][0],
                "source": meta.get("source", ""),
                "page": meta.get("page", 0),
                "subject": meta.get("subject", ""),
                "exam_type": meta.get("exam_type", ""),
                "score": 0.0,  # BM25-only hit — no cosine score
            }
        except Exception:
            log.debug("_fetch_by_id failed  id=%s", doc_id, exc_info=True)
            return None

    @staticmethod
    def _strip_internal_id(chunks: list[dict]) -> list[dict]:
        """Remove internal ``_id`` field before returning to callers."""
        return [{k: v for k, v in c.items() if k != "_id"} for c in chunks]

    def count(self) -> int:
        return self._collection.count()


# ── Factory ───────────────────────────────────────────────────────────

def get_retriever() -> BaseRetriever:
    """Return the configured retriever based on settings.VECTOR_DB."""
    settings = get_settings()
    log.info("get_retriever  backend=%s", settings.VECTOR_DB)
    if settings.VECTOR_DB == "chroma":
        return ChromaRetriever()
    # Sprint 9: add PineconeRetriever here
    log.error(
        "Unsupported vector DB backend: %s — check VECTOR_DB in .env",
        settings.VECTOR_DB,
    )
    raise NotImplementedError(
        f"Vector DB '{settings.VECTOR_DB}' is not implemented yet. "
        "Supported: 'chroma'. Pinecone support arrives in Sprint 9."
    )
