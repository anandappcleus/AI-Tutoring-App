# ── Stage 1: build deps (cached layer) ───────────────────────────────────────
FROM python:3.11-slim AS builder

# System packages needed to compile asyncpg, bcrypt, and chromadb native exts.
# ca-certificates: truststore uses the system cert store on Linux too.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        libpq-dev \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt

# ── Stage 2: runtime image ────────────────────────────────────────────────────
FROM python:3.11-slim AS runtime

# Only the runtime shared libs needed by asyncpg / bcrypt wheels
RUN apt-get update && apt-get install -y --no-install-recommends \
        libpq5 \
        ca-certificates \
        curl \
    && rm -rf /var/lib/apt/lists/*

# Non-root user — required by Railway's security scanner
RUN useradd -m -u 1001 appuser

WORKDIR /app

# Copy installed packages from builder (avoids re-downloading in runtime stage)
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

# Copy application source
COPY --chown=appuser:appuser . .

USER appuser

EXPOSE 8000

# Run alembic migrations then start uvicorn.
# Using sh -c so ${PORT:-8000} is expanded by the shell.
# Railway sets PORT at runtime; fall back to 8000 for local docker compose.
CMD ["sh", "-c", "\
  if [ ! -f /app/chroma_data/chroma.sqlite3 ]; then \
    echo '[INIT] Seeding RAG volume from bundled chroma_db...'; \
    cp -rp /app/chroma_db/. /app/chroma_data/; \
    echo '[INIT] Seeding complete'; \
  else \
    echo '[INIT] chroma_data already populated, skipping seed'; \
  fi; \
  alembic upgrade head || echo '[WARN] Migrations skipped'; \
  exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --workers 1 --log-level info"]
