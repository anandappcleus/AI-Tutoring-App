"""
Upstash Redis client — singleton for the lifetime of the process.

Used for:
  • Conversation history  key: chat:history:{student_id}  TTL: 24 h
  • Rate-limit counters   key: rate:{student_id}:{date}   TTL: seconds until UTC midnight

Graceful degradation: if UPSTASH_REDIS_REST_URL / TOKEN are not set, every
helper returns a safe default (None / 0) so the app works without Redis.
"""

from __future__ import annotations

import logging

log = logging.getLogger(__name__)

# Lazy singleton — created on first use so import-time errors don't crash startup.
_redis = None


def get_redis():
    """Return the Upstash async Redis client, or None if not configured."""
    global _redis
    if _redis is not None:
        return _redis

    from app.config import get_settings
    s = get_settings()

    if not s.UPSTASH_REDIS_REST_URL or not s.UPSTASH_REDIS_REST_TOKEN:
        log.debug("redis_client: UPSTASH env vars not set — Redis disabled")
        return None

    try:
        from upstash_redis.asyncio import Redis  # type: ignore[import]
        _redis = Redis(url=s.UPSTASH_REDIS_REST_URL, token=s.UPSTASH_REDIS_REST_TOKEN)
        log.info("redis_client: Upstash Redis connected")
        return _redis
    except ImportError:
        log.warning("redis_client: upstash-redis not installed — Redis disabled")
        return None
    except Exception as exc:
        log.warning("redis_client: init failed (%s) — Redis disabled", exc)
        return None
