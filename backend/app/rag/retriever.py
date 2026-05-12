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
        self._client = chromadb.PersistentClient(path=path)
        self._collection = self._client.get_or_create_collection(
            name=COLLECTION_NAME,
            metadata={"hnsw:space": "cosine"},
        )
        self._embedder = Embedder()
        log.info("ChromaRetriever  collection=%s  path=%s", COLLECTION_NAME, path)

    def search(self, query: str, top_k: int = 5) -> list[dict]:
        query_vec = self._embedder.embed_query(query)
        results = self._collection.query(
            query_embeddings=[query_vec],
            n_results=top_k,
            include=["documents", "metadatas", "distances"],
        )
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
    if settings.VECTOR_DB == "chroma":
        return ChromaRetriever()
    # Sprint 9: add PineconeRetriever here
    raise NotImplementedError(
        f"Vector DB '{settings.VECTOR_DB}' is not implemented yet. "
        "Supported: 'chroma'. Pinecone support arrives in Sprint 9."
    )
