from functools import lru_cache
from typing import List

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore",  # ignore OS env vars like SSL_CERT_FILE, TERM, PATH, etc.
    )

    # ── LLM ──────────────────────────────────────────────────────────
    LLM_BASE_URL: str = "https://integrate.api.nvidia.com/v1"
    LLM_API_KEY: str
    LLM_CHAT_MODEL: str = "ai21labs/sarvam-m"
    LLM_AGENT_MODEL: str = "meta/llama-3.3-70b-instruct"
    LLM_FAST_MODEL: str = "meta/llama-3.1-8b-instruct"  # NIM fallback when primary is throttled
    LLM_VISION_MODEL: str = "meta/llama-3.2-90b-vision-instruct"  # 90B is far better at typeset math OCR
    EMBED_MODEL: str = "nvidia/nv-embedqa-e5-v5"

    # ── Groq fallback (optional — free tier, ~2s latency vs NIM's 40-60s) ────
    # Set GROQ_API_KEY in .env to enable; leave empty to keep NIM-only path.
    # When set, replaces LLM_FAST_MODEL on NIM with llama-3.3-70b-versatile on Groq.
    GROQ_API_KEY: str = ""
    GROQ_MODEL: str = "llama-3.3-70b-versatile"  # Groq free tier — 30k tokens/min

    # ── Vector DB ────────────────────────────────────────────────────
    VECTOR_DB: str = "chroma"  # "chroma" | "pinecone"
    CHROMA_PERSIST_DIR: str = "chroma_db"  # relative to backend/ working dir

    # ── RAG pipeline enhancements ────────────────────────────────────
    RERANKER_MODEL: str = "nvidia/nv-rerankqa-mistral-4b-v3"
    SEMANTIC_CACHE_TTL: int = 604800        # 7 days in seconds
    SEMANTIC_CACHE_THRESHOLD: float = 0.92  # cosine similarity for cache hit
    SEMANTIC_CACHE_MAX_ENTRIES: int = 1000  # max entries in the ZSET index
    HYDE_ENABLED: bool = True               # HyDE query rewriting
    BM25_ENABLED: bool = True               # BM25 sparse retrieval + RRF fusion

    # ── Database ─────────────────────────────────────────────────────
    DATABASE_URL: str
    DB_POOL_SIZE: int = 5
    DB_POOL_MAX_OVERFLOW: int = 10
    DB_POOL_TIMEOUT: int = 30        # seconds to wait for a pool connection
    DB_POOL_RECYCLE: int = 1800      # seconds before idle connections are recycled

    # ── Auth ─────────────────────────────────────────────────────────
    SECRET_KEY: str
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30

    # ── WhatsApp Cloud API (optional — Progress Monitor Agent) ────────
    WHATSAPP_TOKEN: str = ""                # Meta Graph API bearer token
    WHATSAPP_PHONE_NUMBER_ID: str = ""      # Sender phone number ID from Meta dashboard
    WHATSAPP_API_VERSION: str = "v20.0"

    # ── Upstash Redis (conversation history + rate limiting) ─────────
    UPSTASH_REDIS_REST_URL: str = ""    # e.g. https://xxx.upstash.io
    UPSTASH_REDIS_REST_TOKEN: str = ""  # Upstash REST token

    # ── Admin ─────────────────────────────────────────────────────────
    ADMIN_SECRET: str = ""          # set in .env / Railway to protect /admin routes

    # ── App ──────────────────────────────────────────────────────────
    APP_ENV: str = "development"
    LOG_LEVEL: str = "INFO"          # DEBUG | INFO | WARNING | ERROR
    CORS_ORIGINS: List[str] = ["http://localhost:3000"]


@lru_cache
def get_settings() -> Settings:
    return Settings()
