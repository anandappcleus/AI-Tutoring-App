"""Logging configuration for SmartTutor.

Design
------
• Development  → ANSI-coloured, human-readable, timestamped (level DEBUG)
• Production   → JSON structured, one-line-per-event  (level INFO)

Correlation IDs
---------------
Every inbound HTTP request gets an ``X-Request-ID`` value stored in
``REQUEST_ID_CTX`` (a ``contextvars.ContextVar``).  All log lines emitted
during that request automatically carry ``request_id`` so logs can be
correlated in any aggregator (Datadog, Loki, CloudWatch, etc.).

Usage in any module::

    import logging
    log = logging.getLogger(__name__)

    log.debug("cache.miss  key=%s", cache_key)
    log.info("student.registered", extra={"student_id": str(sid)})
    log.warning("rate_limit.near  %d/%d", used, limit)
    log.error("db.query_failed", exc_info=True)
"""
from __future__ import annotations

import logging
import sys
from contextvars import ContextVar
from typing import Any

# ---------------------------------------------------------------------------
# Correlation-ID context variable
# ---------------------------------------------------------------------------
# Populated by RequestLoggingMiddleware for every HTTP request.
# Falls back to "-" when called outside a request context (e.g. startup tasks,
# background jobs, CLI commands).
REQUEST_ID_CTX: ContextVar[str] = ContextVar("request_id", default="-")


# ---------------------------------------------------------------------------
# Logging filter — injects request_id into every record
# ---------------------------------------------------------------------------
class _RequestIdFilter(logging.Filter):
    """Stamp every log record with the current correlation ID."""

    def filter(self, record: logging.LogRecord) -> bool:
        record.request_id = REQUEST_ID_CTX.get("-")  # type: ignore[attr-defined]
        return True


# ---------------------------------------------------------------------------
# Development formatter — coloured, human-readable
# ---------------------------------------------------------------------------
class _ColourFormatter(logging.Formatter):
    """ANSI-coloured formatter for local terminal output."""

    _RESET = "\033[0m"
    _COLOURS: dict[int, str] = {
        logging.DEBUG:    "\033[38;5;244m",  # grey
        logging.INFO:     "\033[36m",         # cyan
        logging.WARNING:  "\033[33m",         # yellow
        logging.ERROR:    "\033[31m",          # red
        logging.CRITICAL: "\033[1;31m",        # bold red
    }

    _FMT  = "%(asctime)s %(levelname)-8s [%(request_id)s] %(name)s  %(message)s"
    _DATE = "%H:%M:%S"

    def __init__(self) -> None:
        super().__init__(fmt=self._FMT, datefmt=self._DATE)

    def format(self, record: logging.LogRecord) -> str:
        colour = self._COLOURS.get(record.levelno, "")
        record.levelname = f"{colour}{record.levelname}{self._RESET}"
        return super().format(record)


# ---------------------------------------------------------------------------
# Production formatter — structured JSON
# ---------------------------------------------------------------------------
def _make_json_formatter() -> logging.Formatter:
    """Return a JSON formatter; falls back to inline-JSON if library absent."""
    try:
        from pythonjsonlogger.jsonlogger import JsonFormatter  # type: ignore[import]

        return JsonFormatter(
            fmt="%(asctime)s %(levelname)s %(name)s %(request_id)s %(message)s",
            datefmt="%Y-%m-%dT%H:%M:%SZ",
            rename_fields={
                "levelname":  "level",
                "asctime":    "ts",
                "name":       "logger",
                "request_id": "rid",
            },
        )
    except ImportError:
        # Safety net: plain inline-JSON via % formatting (zero extra deps)
        return logging.Formatter(
            fmt=(
                '{"ts":"%(asctime)s","level":"%(levelname)s",'
                '"logger":"%(name)s","rid":"%(request_id)s","msg":"%(message)s"}'
            ),
            datefmt="%Y-%m-%dT%H:%M:%SZ",
        )


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
def configure_logging(level: str = "INFO", env: str = "production") -> None:
    """Configure the root logger.  Call **once** at application startup.

    :param level: Log level — ``DEBUG`` / ``INFO`` / ``WARNING`` / ``ERROR``.
    :param env:   ``"development"`` → coloured text; anything else → JSON.
    """
    numeric_level: int = getattr(logging, level.upper(), logging.INFO)
    is_dev = env == "development"

    # Build the single stream handler (stdout so Docker / Railway capture it)
    handler = logging.StreamHandler(sys.stdout)
    handler.setLevel(numeric_level)
    handler.addFilter(_RequestIdFilter())
    handler.setFormatter(_ColourFormatter() if is_dev else _make_json_formatter())

    root = logging.getLogger()
    root.setLevel(numeric_level)
    root.handlers.clear()   # evict uvicorn's default handler added at import
    root.addHandler(handler)

    # ── Third-party verbosity ────────────────────────────────────────
    # SQLAlchemy: show SQL in dev (DEBUG), silence in prod
    logging.getLogger("sqlalchemy.engine").setLevel(
        logging.DEBUG if is_dev else logging.WARNING
    )
    logging.getLogger("sqlalchemy.pool").setLevel(logging.WARNING)

    # uvicorn: it manages its own access log; avoid duplicate output
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)
    logging.getLogger("uvicorn.error").setLevel(logging.INFO)

    # Chroma: suppress internal HNSWLIB / migration noise
    logging.getLogger("chromadb").setLevel(logging.WARNING)
    logging.getLogger("chromadb.segment").setLevel(logging.WARNING)

    # OpenAI / httpx: suppress per-request HTTP wire logs
    logging.getLogger("openai").setLevel(logging.WARNING)
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("httpcore").setLevel(logging.WARNING)

    # CrewAI: INFO in dev so agent steps are visible; WARNING in prod
    logging.getLogger("crewai").setLevel(
        logging.INFO if is_dev else logging.WARNING
    )

    # HTTP clients — only log errors
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("openai").setLevel(logging.WARNING)

    # Vector DB / agent frameworks
    logging.getLogger("chromadb").setLevel(logging.WARNING)
    logging.getLogger("crewai").setLevel(logging.INFO)

    logging.getLogger(__name__).info(
        "logging.configured  env=%s  level=%s", env, level
    )


def get_logger(name: str) -> logging.Logger:
    """Convenience wrapper — identical to ``logging.getLogger(name)``.

    Provided so future modules can do ``from app.logging_config import get_logger``
    without importing the stdlib ``logging`` module directly.
    """
    return logging.getLogger(name)
