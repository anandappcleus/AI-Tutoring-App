"""
Cross-encoder re-ranker using NVIDIA NIM nv-rerankqa-mistral-4b-v3.

After hybrid retrieval returns up to 20 candidate chunks, this re-ranker
scores each (query, chunk) pair with a dedicated re-ranking model that has
full cross-attention over both — significantly more accurate than cosine
similarity alone.

NIM re-ranking endpoint is OpenAI-compatible with a custom /reranking path:
  POST https://integrate.api.nvidia.com/v1/ranking
  Body: {"model": "...", "query": {"text": "..."}, "passages": [{"text": "..."}], ...}

Reference:
  NVIDIA NIM re-ranking API — https://docs.api.nvidia.com/nim/reference/ranking

Design:
  • Singleton Reranker; degrades gracefully (returns original order) on any
    failure, keeping the /ask endpoint functional even without re-ranking.
  • Passages are capped at 512 tokens (server-side) but we truncate to 1000
    chars client-side to avoid 413 errors on dense math chunks.
  • top_k defaults to 5 — after re-ranking we need far fewer chunks than the
    20 retrieved by hybrid search.
"""

from __future__ import annotations

import logging
import time

import httpx

from app.config import get_settings

log = logging.getLogger(__name__)

_MAX_PASSAGE_CHARS = 1000  # hard cap before sending to re-ranker
_RERANK_PATH = "/ranking"  # appended to LLM_BASE_URL


class Reranker:
    """
    Cross-encoder re-ranker backed by NVIDIA NIM.

    Usage::

        reranker = Reranker()
        top5 = reranker.rerank("Newton's second law", chunks, top_k=5)
    """

    def rerank(
        self,
        query: str,
        chunks: list[dict],
        top_k: int = 5,
    ) -> list[dict]:
        """
        Re-rank chunks using the cross-encoder model.

        Args:
            query:  The original (or HyDE-rewritten) query string.
            chunks: List of chunk dicts with at least a "text" key (as returned
                    by ChromaRetriever.search()).
            top_k:  Number of chunks to return after re-ranking.

        Returns:
            Up to top_k chunks sorted by cross-encoder relevance score (best first).
            On any error returns the first top_k chunks in their original order.
        """
        if not chunks:
            return chunks

        s = get_settings()
        top_k = min(top_k, len(chunks))

        passages = [
            {"text": c["text"][:_MAX_PASSAGE_CHARS]}
            for c in chunks
        ]

        url = s.LLM_BASE_URL.rstrip("/") + _RERANK_PATH
        log.debug(
            "reranker.rerank_start  model=%s  url=%s  n_passages=%d  top_k=%d  query=%r",
            s.RERANKER_MODEL, url, len(passages), top_k, query[:80],
        )

        t0 = time.perf_counter()
        try:
            with httpx.Client(timeout=10.0) as client:
                resp = client.post(
                    url,
                    headers={
                        "Authorization": f"Bearer {s.LLM_API_KEY}",
                        "Content-Type": "application/json",
                    },
                    json={
                        "model": s.RERANKER_MODEL,
                        "query": {"text": query},
                        "passages": passages,
                        "truncate": "END",
                    },
                )
                elapsed_ms = (time.perf_counter() - t0) * 1_000
                log.debug(
                    "reranker.http_response  status=%d  elapsed_ms=%.0f",
                    resp.status_code, elapsed_ms,
                )
                resp.raise_for_status()
                data = resp.json()
        except Exception as exc:
            elapsed_ms = (time.perf_counter() - t0) * 1_000
            log.warning(
                "reranker.rerank_failed  model=%s  elapsed_ms=%.0f  error=%s"
                "  — returning original order (top_%d)",
                s.RERANKER_MODEL, elapsed_ms, exc, top_k,
            )
            return chunks[:top_k]

        # Response: {"rankings": [{"index": int, "logit": float}, ...]}
        rankings = data.get("rankings") or []
        if not rankings:
            log.warning(
                "reranker.empty_rankings  model=%s  query=%r"
                "  — returning original order (top_%d)",
                s.RERANKER_MODEL, query[:60], top_k,
            )
            return chunks[:top_k]

        # Sort by logit score descending, take top_k
        sorted_rankings = sorted(rankings, key=lambda r: r.get("logit", 0.0), reverse=True)
        sorted_indices = [
            r["index"]
            for r in sorted_rankings
            if r["index"] < len(chunks)
        ][:top_k]

        reranked = [chunks[i] for i in sorted_indices]
        elapsed_ms = (time.perf_counter() - t0) * 1_000

        # Log score distribution for debugging rank quality
        logits = [r.get("logit", 0.0) for r in sorted_rankings[:top_k]]
        log.info(
            "reranker.rerank_ok  model=%s  input=%d  returned=%d"
            "  top_logit=%.4f  bottom_logit=%.4f  elapsed_ms=%.0f  query=%r",
            s.RERANKER_MODEL, len(chunks), len(reranked),
            logits[0] if logits else 0.0,
            logits[-1] if logits else 0.0,
            elapsed_ms, query[:60],
        )
        return reranked


# ── Module-level singleton ────────────────────────────────────────────

_reranker: Reranker | None = None


def get_reranker() -> Reranker:
    global _reranker
    if _reranker is None:
        _reranker = Reranker()
    return _reranker
