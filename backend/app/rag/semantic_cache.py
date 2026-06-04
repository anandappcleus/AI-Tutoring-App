"""
Semantic Answer Cache — Redis-backed cache keyed by embedding similarity.

Instead of exact-match caching (which is useless for natural-language queries),
this cache stores (query_vector, response_json) pairs and returns a hit when a
new query is within `threshold` cosine similarity of a stored entry.

This eliminates repeated LLM calls for common JEE/NEET questions such as:
  "What is Newton's second law?" ≈ "Explain Newton's 2nd law of motion"

Storage layout in Upstash Redis:
  scache:idx    — ZSET: members = entry_ids, scores = unix-timestamp (for LRU eviction)
  scache:{id}   — HASH: fields = vec (JSON float list), resp (response JSON string),
                         ts (unix timestamp), query_preview (first 80 chars for debugging)

Security:
  • No student PII stored in cache — only the anonymised query vector + response JSON.
  • TTL applied per-entry; the ZSET idx is trimmed to MAX_ENTRIES on every write.

Graceful degradation:
  • All methods return safe defaults (None / no-op) when Redis is unavailable.
  • Cosine similarity is computed client-side over retrieved vectors — no vector DB.
"""

from __future__ import annotations

import hashlib
import json
import logging
import math
import time
import uuid

from app.config import get_settings
from app.services.redis_client import get_redis

log = logging.getLogger(__name__)

_IDX_KEY = "scache:idx"


def _cosine(a: list[float], b: list[float]) -> float:
    """Compute cosine similarity between two equal-length vectors."""
    dot = sum(x * y for x, y in zip(a, b))
    norm_a = math.sqrt(sum(x * x for x in a))
    norm_b = math.sqrt(sum(y * y for y in b))
    if norm_a == 0.0 or norm_b == 0.0:
        return 0.0
    return dot / (norm_a * norm_b)


class SemanticCache:
    """
    Redis-backed semantic answer cache.

    Usage::

        cache = SemanticCache()
        hit = await cache.get(query_vec)
        if hit:
            return hit  # cached response JSON string

        response = await run_crew(...)
        await cache.set(query_vec, response, query_preview="What is F=ma?")
    """

    async def get(
        self,
        query_vec: list[float],
        threshold: float | None = None,
    ) -> str | None:
        """
        Look up a cached response by cosine similarity.

        Returns the cached response JSON string on a hit, or None on a miss.
        """
        s = get_settings()
        threshold = threshold if threshold is not None else s.SEMANTIC_CACHE_THRESHOLD
        redis = get_redis()
        if redis is None:
            log.debug("semantic_cache.get: redis unavailable — cache miss")
            return None

        t0 = time.perf_counter()
        try:
            # Fetch all entry IDs from the sorted set (scores = timestamps, ascending)
            entry_ids: list[str] = await redis.zrange(_IDX_KEY, 0, -1)
            n_entries = len(entry_ids)
            if not entry_ids:
                log.debug("semantic_cache.get: index empty — cache miss")
                return None

            log.debug(
                "semantic_cache.get: scanning %d entries  threshold=%.4f  vec_dim=%d",
                n_entries, threshold, len(query_vec),
            )

            best_sim = -1.0
            best_resp: str | None = None
            best_preview: str = ""
            scanned = 0
            skipped = 0

            for entry_id in entry_ids:
                entry = await redis.hgetall(f"scache:{entry_id}")
                if not entry or "vec" not in entry or "resp" not in entry:
                    skipped += 1
                    log.debug("semantic_cache.get: missing fields  entry_id=%s  fields=%s", entry_id, list(entry.keys()) if entry else "[]") 
                    continue
                stored_vec: list[float] = json.loads(entry["vec"])
                if len(stored_vec) != len(query_vec):
                    skipped += 1
                    log.warning(
                        "semantic_cache.get: dim_mismatch  entry_id=%s"
                        "  stored_dim=%d  query_dim=%d — skipping entry",
                        entry_id, len(stored_vec), len(query_vec),
                    )
                    continue
                sim = _cosine(query_vec, stored_vec)
                scanned += 1
                if sim > best_sim:
                    best_sim = sim
                    best_resp = entry["resp"]
                    best_preview = entry.get("query_preview", "")

            elapsed_ms = (time.perf_counter() - t0) * 1_000

            if best_sim >= threshold and best_resp is not None:
                log.info(
                    "semantic_cache.hit  similarity=%.4f  threshold=%.4f"
                    "  scanned=%d  skipped=%d  elapsed_ms=%.1f"
                    "  matched_preview=%r",
                    best_sim, threshold, scanned, skipped, elapsed_ms, best_preview[:60],
                )
                return best_resp

            log.info(
                "semantic_cache.miss  best_sim=%.4f  threshold=%.4f"
                "  scanned=%d  skipped=%d  elapsed_ms=%.1f",
                best_sim, threshold, scanned, skipped, elapsed_ms,
            )
        except Exception as exc:
            elapsed_ms = (time.perf_counter() - t0) * 1_000
            log.warning(
                "semantic_cache.get error  elapsed_ms=%.1f  error=%s — cache miss",
                elapsed_ms, exc, exc_info=True,
            )

        return None

    async def set(
        self,
        query_vec: list[float],
        response_json: str,
        query_preview: str = "",
        ttl: int | None = None,
    ) -> None:
        """
        Store a query vector + response in the cache.

        Args:
            query_vec:     The embedding vector of the query.
            response_json: The serialised response to cache.
            query_preview: First ~80 chars of the query (for debugging only).
            ttl:           TTL in seconds (defaults to SEMANTIC_CACHE_TTL setting).
        """
        s = get_settings()
        ttl = ttl if ttl is not None else s.SEMANTIC_CACHE_TTL
        redis = get_redis()
        if redis is None:
            log.debug("semantic_cache.set: redis unavailable — skipping")
            return

        t0 = time.perf_counter()
        try:
            entry_id = hashlib.md5(
                (query_preview + str(time.time())).encode()
            ).hexdigest()[:16]
            ts = time.time()

            # Store the entry hash with TTL
            # upstash-redis hset() takes alternating field/value positional args
            entry_key = f"scache:{entry_id}"
            await redis.hset(
                entry_key,
                "vec", json.dumps(query_vec),
                "resp", response_json,
                "ts", str(ts),
                "query_preview", query_preview[:80],
            )
            await redis.expire(entry_key, ttl)

            # Track in ZSET (score = timestamp for LRU eviction ordering)
            await redis.zadd(_IDX_KEY, {entry_id: ts})

            # Evict oldest entries if over MAX_ENTRIES
            max_entries = s.SEMANTIC_CACHE_MAX_ENTRIES
            count = await redis.zcard(_IDX_KEY)
            if count > max_entries:
                overflow = count - max_entries
                oldest_ids: list[str] = await redis.zrange(_IDX_KEY, 0, overflow - 1)
                for oid in oldest_ids:
                    await redis.delete(f"scache:{oid}")
                await redis.zremrangebyrank(_IDX_KEY, 0, overflow - 1)
                log.info(
                    "semantic_cache.evict  removed=%d  new_count=%d  max_entries=%d",
                    overflow, max_entries, max_entries,
                )

            elapsed_ms = (time.perf_counter() - t0) * 1_000
            log.info(
                "semantic_cache.set  entry_id=%s  ttl=%ds  vec_dim=%d"
                "  resp_chars=%d  elapsed_ms=%.1f  preview=%r",
                entry_id, ttl, len(query_vec),
                len(response_json), elapsed_ms, query_preview[:60],
            )
        except Exception as exc:
            elapsed_ms = (time.perf_counter() - t0) * 1_000
            log.warning(
                "semantic_cache.set error  elapsed_ms=%.1f  error=%s — skipping cache write",
                elapsed_ms, exc, exc_info=True,
            )


# ── Module-level singleton ────────────────────────────────────────────

_cache: SemanticCache | None = None


def get_semantic_cache() -> SemanticCache:
    global _cache
    if _cache is None:
        _cache = SemanticCache()
    return _cache
