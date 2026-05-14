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

# Pre-create the chroma_data directory owned by appuser so the volume
# mount (which lands as root) can be written by appuser at runtime.
# Railway mounts the volume over /app/chroma_data at container start,
# preserving the ownership set here if the volume is freshly provisioned.
RUN mkdir -p /app/chroma_data && chown appuser:appuser /app/chroma_data

USER appuser

EXPOSE 8000

# Run alembic migrations then start uvicorn.
# Using sh -c so ${PORT:-8000} is expanded by the shell.
# Railway sets PORT at runtime; fall back to 8000 for local docker compose.
CMD ["sh", "-c", "if [ -d /app/chroma_db ] && [ ! -f /app/chroma_data/chroma.sqlite3 ]; then echo '[INIT] Seeding chroma_data from bundled chroma_db...'; mkdir -p /app/chroma_data && cp -rp /app/chroma_db/. /app/chroma_data/ && echo '[INIT] Seed OK' || echo '[WARN] Seed failed, continuing'; fi; alembic upgrade head || echo '[WARN] Migrations skipped'; exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --workers 1 --log-level info"]
