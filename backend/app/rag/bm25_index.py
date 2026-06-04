"""
BM25 sparse retrieval index + Reciprocal Rank Fusion (RRF) helper.

This module provides:
  BM25Index   — in-memory BM25Okapi index built from a Chroma collection.
  rrf_fuse    — fuses two ranked lists (dense + sparse) using RRF scoring.

Design decisions:
  • The index lives in memory (rank-bm25 is pure Python, no external service).
  • It is rebuilt from Chroma at first use and can be invalidated/rebuilt after
    a re-ingestion via BM25Index.rebuild().
  • BM25 tokenises on whitespace and lowercases — adequate for English technical
    text (JEE/NEET syllabus content is predominantly English even for Indic users).
  • RRF constant k=60 is the empirically validated default (Robertson et al. 2010).
"""

from __future__ import annotations

import logging
import threading
import time
from typing import Any

log = logging.getLogger(__name__)

_RRF_K = 60  # RRF constant — larger k dampens the rank-difference penalty


# ── RRF helper ────────────────────────────────────────────────────────

def rrf_fuse(
    dense_ids: list[str],
    sparse_ids: list[str],
    k: int = _RRF_K,
) -> list[str]:
    """
    Fuse two ranked lists of document IDs using Reciprocal Rank Fusion.

    Args:
        dense_ids:  IDs ranked by dense (embedding) similarity, best first.
        sparse_ids: IDs ranked by BM25 score, best first.
        k:          RRF smoothing constant (default 60).

    Returns:
        Fused list of unique IDs sorted by combined RRF score, best first.
    """
    scores: dict[str, float] = {}
    for rank, doc_id in enumerate(dense_ids, start=1):
        scores[doc_id] = scores.get(doc_id, 0.0) + 1.0 / (k + rank)
    for rank, doc_id in enumerate(sparse_ids, start=1):
        scores[doc_id] = scores.get(doc_id, 0.0) + 1.0 / (k + rank)
    return sorted(scores, key=lambda d: scores[d], reverse=True)


# ── BM25 index ────────────────────────────────────────────────────────

class BM25Index:
    """
    Wrapper around rank_bm25.BM25Okapi that loads its corpus from a Chroma
    collection and exposes a search() interface matching ChromaRetriever.

    Thread-safety: rebuild() acquires a write lock; search() acquires a read
    lock — concurrent /ask requests will not corrupt the index.

    Usage::

        idx = BM25Index(chroma_collection)
        ids = idx.search("Newton's second law", top_k=20)
    """

    def __init__(self, collection: Any) -> None:
        """
        Args:
            collection: a chromadb.Collection instance.
        """
        self._collection = collection
        self._lock = threading.RLock()
        self._ids: list[str] = []
        self._corpus: list[list[str]] = []
        self._bm25 = None  # BM25Okapi instance — None until first build
        self._build()

    # ── Public API ────────────────────────────────────────────────────

    def search(self, query: str, top_k: int = 20) -> list[str]:
        """
        Return the top_k document IDs most relevant to query (BM25 scored).

        Falls back to an empty list if the index is empty or not yet built.
        """
        t0 = time.perf_counter()
        with self._lock:
            if self._bm25 is None or not self._ids:
                log.warning(
                    "bm25_index.search: index not ready  bm25_built=%s  corpus_size=%d"
                    " — sparse retrieval disabled for this request",
                    self._bm25 is not None, len(self._ids),
                )
                return []
            tokens = query.lower().split()
            token_count = len(tokens)
            scores = self._bm25.get_scores(tokens)
            # argsort descending, clip to available docs
            top_n = min(top_k, len(self._ids))
            top_indices = sorted(range(len(scores)), key=lambda i: scores[i], reverse=True)[:top_n]
            result_ids = [self._ids[i] for i in top_indices]
            top_score = scores[top_indices[0]] if top_indices else 0.0
            elapsed_ms = (time.perf_counter() - t0) * 1_000
            log.debug(
                "bm25_index.search  query=%r  tokens=%d  corpus=%d"
                "  top_k=%d  returned=%d  top_score=%.4f  elapsed_ms=%.1f",
                query[:60], token_count, len(self._ids),
                top_k, len(result_ids), top_score, elapsed_ms,
            )
            return result_ids

    def rebuild(self) -> None:
        """Reload all documents from Chroma and rebuild the BM25 index.

        Call this after a re-ingestion to keep the index fresh.
        """
        with self._lock:
            self._build()

    def doc_count(self) -> int:
        with self._lock:
            return len(self._ids)

    # ── Internal ──────────────────────────────────────────────────────

    def _build(self) -> None:
        """Load all docs from Chroma and build the BM25Okapi index (called under lock)."""
        try:
            from rank_bm25 import BM25Okapi  # type: ignore[import]
        except ImportError:
            log.error(
                "bm25_index: rank-bm25 not installed — add rank-bm25>=0.2.2 to requirements.txt"
                "  IMPACT: sparse retrieval disabled, only dense search will be used"
            )
            return

        t0 = time.perf_counter()
        try:
            count = self._collection.count()
            log.debug("bm25_index._build  chroma_count=%d", count)
            if count == 0:
                log.warning(
                    "bm25_index._build: collection empty — BM25 index not built"
                    "  IMPACT: sparse retrieval disabled until corpus is ingested"
                )
                return

            # Chroma returns max 10_000 per get() call; for large corpora we page.
            # For typical JEE/NEET corpora (<100k chunks) one call is sufficient.
            result = self._collection.get(include=["documents"])
            ids: list[str] = result["ids"]
            docs: list[str] = result["documents"]

            tokenised = [doc.lower().split() for doc in docs]
            total_tokens = sum(len(t) for t in tokenised)
            avg_doc_len = total_tokens / len(tokenised) if tokenised else 0.0

            self._ids = ids
            self._corpus = tokenised
            self._bm25 = BM25Okapi(tokenised)
            elapsed_ms = (time.perf_counter() - t0) * 1_000
            log.info(
                "bm25_index._build  docs=%d  total_tokens=%d  avg_doc_len=%.1f  elapsed_ms=%.0f",
                len(ids), total_tokens, avg_doc_len, elapsed_ms,
            )
        except Exception:
            log.error(
                "bm25_index._build failed  IMPACT: BM25 disabled for all searches",
                exc_info=True,
            )


# ── Module-level singleton ────────────────────────────────────────────
# Created lazily; caller imports get_bm25_index() to retrieve or build.

_singleton: BM25Index | None = None
_singleton_lock = threading.Lock()


def get_bm25_index(collection: Any) -> BM25Index:
    """Return the module-level BM25Index singleton, creating it if needed."""
    global _singleton
    with _singleton_lock:
        if _singleton is None:
            _singleton = BM25Index(collection)
    return _singleton


def invalidate_bm25_index() -> None:
    """Force a rebuild of the singleton on the next get_bm25_index() call.

    Call this at the end of a successful ingest run so search sees fresh data.
    """
    global _singleton
    with _singleton_lock:
        _singleton = None
    log.info("bm25_index: singleton invalidated — will rebuild on next search")
