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
    LLM_FAST_MODEL: str = "meta/llama-3.1-8b-instruct"  # fallback when primary is throttled
    LLM_VISION_MODEL: str = "meta/llama-3.2-90b-vision-instruct"  # 90B is far better at typeset math OCR
    EMBED_MODEL: str = "nvidia/nv-embedqa-e5-v5"

    # ── Vector DB ────────────────────────────────────────────────────
    VECTOR_DB: str = "chroma"  # "chroma" | "pinecone"
    CHROMA_PERSIST_DIR: str = "chroma_db"  # relative to backend/ working dir

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

    # ── Admin ─────────────────────────────────────────────────────────
    ADMIN_SECRET: str = ""          # set in .env / Railway to protect /admin routes

    # ── App ──────────────────────────────────────────────────────────
    APP_ENV: str = "development"
    LOG_LEVEL: str = "INFO"          # DEBUG | INFO | WARNING | ERROR
    CORS_ORIGINS: List[str] = ["http://localhost:3000"]


@lru_cache
def get_settings() -> Settings:
    return Settings()
