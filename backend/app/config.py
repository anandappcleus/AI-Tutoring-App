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
    LLM_AGENT_MODEL: str = "qwen/qwen3-235b-a22b"
    EMBED_MODEL: str = "nvidia/nv-embedqa-e5-v5"

    # ── Vector DB ────────────────────────────────────────────────────
    VECTOR_DB: str = "chroma"  # "chroma" | "pinecone"

    # ── Database ─────────────────────────────────────────────────────
    DATABASE_URL: str

    # ── Auth ─────────────────────────────────────────────────────────
    SECRET_KEY: str
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30

    # ── App ──────────────────────────────────────────────────────────
    APP_ENV: str = "development"
    LOG_LEVEL: str = "INFO"          # DEBUG | INFO | WARNING | ERROR
    CORS_ORIGINS: List[str] = ["http://localhost:3000"]


@lru_cache
def get_settings() -> Settings:
    return Settings()
