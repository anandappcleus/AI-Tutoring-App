import asyncio
import ssl
import sys
from logging.config import fileConfig
from pathlib import Path

from sqlalchemy import pool, create_engine
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import create_async_engine

from alembic import context

# ── Make app importable from backend/ directory ───────────────────────
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

# ── Import settings + all models (required for autogenerate) ─────────
from app.config import get_settings  # noqa: E402
from app.models import Base  # noqa: E402, F401 — side-effect: registers all models
from app.database import _prepare_engine_args  # noqa: E402

# Alembic Config object
config = context.config

# Override sqlalchemy.url from env settings
settings = get_settings()
config.set_main_option("sqlalchemy.url", settings.DATABASE_URL)

# Logging
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


# ── Offline migrations ────────────────────────────────────────────────
def run_migrations_offline() -> None:
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


# ── Online migrations (sync via psycopg2) ────────────────────────────
# Using synchronous psycopg2 avoids the asyncpg SSL-upgrade handshake
# issue with Neon's serverless proxy on macOS.
def run_migrations_online() -> None:
    db_url = settings.DATABASE_URL
    # Convert +asyncpg dialect to plain psycopg2 for the migration engine.
    # Also translate ?ssl=require → ?sslmode=require (psycopg2 syntax).
    import re
    sync_url = db_url.replace("postgresql+asyncpg://", "postgresql://")
    sync_url = re.sub(r'[?&]ssl=require', '?sslmode=require', sync_url, flags=re.IGNORECASE)
    connectable = create_engine(sync_url, poolclass=pool.NullPool)
    with connectable.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
