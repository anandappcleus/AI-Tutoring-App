"""
Database engine, session factory, and health helpers.

Pool settings are read from Settings so they can be tuned via .env:
    DB_POOL_SIZE, DB_POOL_MAX_OVERFLOW, DB_POOL_TIMEOUT, DB_POOL_RECYCLE

Health check:
    ok = await ping_db()   →  True if reachable, False otherwise (used by /health)

FastAPI dependency:
    db: AsyncSession = Depends(get_db)
    — rolls back automatically on any unhandled exception inside the route
"""
from __future__ import annotations

import logging
import re
import ssl
from urllib.parse import urlparse, urlunparse

import sqlalchemy as sa
from sqlalchemy.pool import NullPool
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from app.config import get_settings

log = logging.getLogger(__name__)


def _mask_db_url(url: str) -> str:
    """Replace the DB password with **** so the URL is safe to log."""
    try:
        parsed = urlparse(url)
        if parsed.password:
            return urlunparse(
                parsed._replace(
                    netloc=parsed.netloc.replace(f":{parsed.password}@", ":****@")
                )
            )
    except Exception:
        pass
    return "<db-url>"


def _prepare_engine_args(database_url: str) -> tuple[str, dict]:
    """
    asyncpg does not honour ``?ssl=require`` / ``?sslmode=require`` in the
    connection URL.  Strip those parameters and return an ssl.SSLContext via
    ``connect_args`` instead — required for Neon / any TLS-only Postgres host.

    Returns (clean_url, connect_args_dict).
    """
    connect_args: dict = {}
    if re.search(r'[?&]ssl(?:mode)?=', database_url, re.IGNORECASE):
        # Remove ?ssl=... or &ssl=... / ?sslmode=... or &sslmode=...
        clean_url = re.sub(r'[?&]ssl(?:mode)?=[^&]*', '', database_url)
        clean_url = re.sub(r'[?&]$', '', clean_url)  # trailing ? or &
        ssl_ctx = ssl.create_default_context()
        connect_args["ssl"] = ssl_ctx
        log.debug("db._prepare_engine_args: SSL via connect_args (stripped from URL)")
        return clean_url, connect_args
    return database_url, connect_args


def _build_engine():
    settings = get_settings()
    masked = _mask_db_url(settings.DATABASE_URL)
    log.info(
        "db.engine_init  url=%s  pool_size=%d  max_overflow=%d  pool_recycle=%ds",
        masked,
        settings.DB_POOL_SIZE,
        settings.DB_POOL_MAX_OVERFLOW,
        settings.DB_POOL_RECYCLE,
    )
    url, connect_args = _prepare_engine_args(settings.DATABASE_URL)
    return create_async_engine(
        url,
        echo=False,          # SQL logged via sqlalchemy.engine logger in logging_config
        future=True,
        pool_pre_ping=True,  # test connections before checkout — catches stale sockets
        pool_size=settings.DB_POOL_SIZE,
        max_overflow=settings.DB_POOL_MAX_OVERFLOW,
        pool_timeout=settings.DB_POOL_TIMEOUT,
        pool_recycle=settings.DB_POOL_RECYCLE,
        connect_args=connect_args,
    )


engine = _build_engine()

AsyncSessionFactory = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


def _build_tool_engine():
    """
    Separate engine for CrewAI tool threads.

    Uses NullPool so asyncpg never holds connections between asyncio.run() calls.
    Each tool invocation gets a fresh connection that belongs to its own event loop,
    eliminating the 'Future attached to a different loop' error.
    """
    settings = get_settings()
    url, connect_args = _prepare_engine_args(settings.DATABASE_URL)
    return create_async_engine(
        url,
        echo=False,
        future=True,
        poolclass=NullPool,
        connect_args=connect_args,
    )


_tool_engine = _build_tool_engine()

ToolSessionFactory = async_sessionmaker(
    _tool_engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


async def ping_db() -> bool:
    """
    Return True if the database is reachable, False otherwise.
    Used by the /health endpoint — never raises.
    """
    try:
        async with engine.connect() as conn:
            await conn.execute(sa.text("SELECT 1"))
        log.debug("db.ping  status=ok")
        return True
    except Exception:
        log.error("db.ping  status=unreachable", exc_info=True)
        return False


async def get_db():
    """
    FastAPI dependency: yield an async DB session.
    Rolls back automatically on any unhandled exception inside the route handler.
    HTTPException (4xx/5xx) causes a rollback but is not logged as an error —
    those are normal application control-flow, not database problems.
    """
    from fastapi import HTTPException as _HTTPException
    async with AsyncSessionFactory() as session:
        try:
            yield session
        except _HTTPException:
            await session.rollback()
            raise
        except Exception:
            log.error("db.session_error  rolling_back", exc_info=True)
            await session.rollback()
            raise
