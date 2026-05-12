"""
Embedder wrapper — NVIDIA NIM nv-embedqa-e5-v5 (dev) / OpenAI text-embedding-3-small (prod)

Usage:
    embedder = Embedder()
    passage_vecs = embedder.embed_passages(["Newton's second law says F=ma ..."])
    query_vec    = embedder.embed_query("What is Newton's second law?")

The NIM embeddings API is OpenAI-compatible. The only difference is the
`input_type` extra body param required by nv-embedqa-e5-v5:
    "passage"  — use when embedding corpus documents (ingestion)
    "query"    — use when embedding a search query (retrieval)
"""

import logging
from typing import Any

from openai import OpenAI

from app.config import get_settings

log = logging.getLogger(__name__)

# NIM / OpenAI embedding batch limit
_MAX_BATCH = 32


class Embedder:
    """Thin wrapper around OpenAI-compatible embeddings endpoint."""

    def __init__(self) -> None:
        settings = get_settings()
        self._client = OpenAI(
            base_url=settings.LLM_BASE_URL,
            api_key=settings.LLM_API_KEY,
        )
        self._model = settings.EMBED_MODEL
        log.info(
            "Embedder ready  model=%s  endpoint=%s",
            self._model,
            settings.LLM_BASE_URL,
        )

    # ── Public API ────────────────────────────────────────────────────

    def embed_passages(self, texts: list[str]) -> list[list[float]]:
        """Embed a list of corpus passages (documents). Batches automatically."""
        return self._embed(texts, input_type="passage")

    def embed_query(self, text: str) -> list[float]:
        """Embed a single search query."""
        return self._embed([text], input_type="query")[0]

    # ── Internal ──────────────────────────────────────────────────────

    def _embed(self, texts: list[str], input_type: str) -> list[list[float]]:
        results: list[list[float]] = []
        total_batches = -(-len(texts) // _MAX_BATCH)
        for i in range(0, len(texts), _MAX_BATCH):
            batch = texts[i : i + _MAX_BATCH]
            batch_num = i // _MAX_BATCH + 1
            log.debug(
                "embedding batch=%d/%d  input_type=%s  model=%s  size=%d",
                batch_num,
                total_batches,
                input_type,
                self._model,
                len(batch),
            )
            extra: dict[str, Any] = {"input_type": input_type, "truncate": "END"}
            try:
                resp = self._client.embeddings.create(
                    model=self._model,
                    input=batch,
                    extra_body=extra,
                )
            except Exception:
                log.error(
                    "NIM embeddings API failed  batch=%d/%d  model=%s",
                    batch_num,
                    total_batches,
                    self._model,
                    exc_info=True,
                )
                raise
            # API returns items sorted by index
            results.extend(item.embedding for item in sorted(resp.data, key=lambda x: x.index))
        return results
