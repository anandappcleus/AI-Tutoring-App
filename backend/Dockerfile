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

# Remove the pre-create step — Railway volume mount overwrites the dir anyway
# The CMD runs the seed as root (before su to appuser) to bypass volume perms.


# Railway injects PORT at runtime (typically 8080); local dev falls back to 8000.
EXPOSE ${PORT:-8000}

# Startup sequence (runs as root so it can write to the Railway volume mount):
#   1. Seed /app/chroma_data from bundled chroma_db if volume is empty
#   2. Fix ownership so appuser can read the seeded files
#   3. Run alembic migrations as appuser
#   4. exec uvicorn as appuser
CMD ["sh", "-c", "\
  if [ -d /app/chroma_db ] && [ ! -f /app/chroma_data/chroma.sqlite3 ]; then \
    echo '[INIT] Seeding chroma_data from bundled chroma_db...'; \
    cp -rp /app/chroma_db/. /app/chroma_data/ && chown -R appuser:appuser /app/chroma_data && echo '[INIT] Seed OK'; \
  fi; \
  su appuser -s /bin/sh -c 'alembic upgrade head || echo [WARN] Migrations skipped'; \
  exec su appuser -s /bin/sh -c 'exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --workers 1 --log-level info'"]
