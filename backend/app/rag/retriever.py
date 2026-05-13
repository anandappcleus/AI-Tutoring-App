"""
Retriever — similarity search abstraction over Chroma (dev) or Pinecone (prod).

Usage:
    retriever = get_retriever()
    chunks = retriever.search("Newton's second law", top_k=5)
    # returns: [{"text": ..., "source": ..., "page": ..., "subject": ..., "score": ...}, ...]

The factory function `get_retriever()` reads VECTOR_DB from settings:
    "chroma"   → ChromaRetriever   (local, zero cost — default for dev)
    "pinecone" → PineconeRetriever (managed — Sprint 9)
"""

from __future__ import annotations

import logging
from abc import ABC, abstractmethod

import chromadb

from app.config import get_settings
from app.rag.embedder import Embedder

log = logging.getLogger(__name__)

COLLECTION_NAME = "jee_corpus"


# ── Abstract base ─────────────────────────────────────────────────────

class BaseRetriever(ABC):
    @abstractmethod
    def search(self, query: str, top_k: int = 5) -> list[dict]:
        """Return top_k relevant chunks for the query."""


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

    def search(self, query: str, top_k: int = 5) -> list[dict]:
        query_vec = self._embedder.embed_query(query)
        try:
            results = self._collection.query(
                query_embeddings=[query_vec],
                n_results=top_k,
                include=["documents", "metadatas", "distances"],
            )
        except Exception:
            log.error(
                "ChromaRetriever.search failed  query=%r  top_k=%d",
                query[:60],
                top_k,
                exc_info=True,
            )
            raise
        chunks: list[dict] = []
        for text, meta, dist in zip(
            results["documents"][0],
            results["metadatas"][0],
            results["distances"][0],
        ):
            chunks.append(
                {
                    "text": text,
                    "source": meta.get("source", ""),
                    "page": meta.get("page", 0),
                    "subject": meta.get("subject", ""),
                    "score": round(1.0 - dist, 4),  # cosine distance → similarity
                }
            )
        log.debug("search  query=%r  top_k=%d  results=%d", query[:60], top_k, len(chunks))
        return chunks

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
