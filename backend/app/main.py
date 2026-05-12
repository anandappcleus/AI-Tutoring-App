import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import get_settings
from app.logging_config import configure_logging
from app.middleware import RequestLoggingMiddleware

settings = get_settings()

# Configure logging before anything else logs (including SQLAlchemy engine init)
configure_logging(level=settings.LOG_LEVEL, env=settings.APP_ENV)

log = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    log.info("startup  env=%s  version=0.1.0", settings.APP_ENV)
    # Sprint 4: start APScheduler nightly crew here
    yield
    log.info("shutdown")
    # Sprint 4: stop scheduler here


app = FastAPI(
    title="SmartTutor API",
    description="AI-powered vernacular tutoring — JEE / NEET / WB Board",
    version="0.1.0",
    lifespan=lifespan,
    docs_url="/docs" if settings.APP_ENV == "development" else None,
    redoc_url=None,
)

# Request logging + correlation ID (must be added before CORSMiddleware so the
# X-Request-ID header is visible to downstream handlers)
app.add_middleware(RequestLoggingMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Routes ────────────────────────────────────────────────────────────
# Sprint 4: include routers here
# from app.routers import auth, ask, plan, progress
# app.include_router(auth.router, prefix="/auth", tags=["auth"])
# app.include_router(ask.router, tags=["ask"])
# app.include_router(plan.router, tags=["plan"])
# app.include_router(progress.router, tags=["progress"])


@app.get("/health", tags=["health"])
async def health():
    log.debug("health check")
    return {"status": "ok", "env": settings.APP_ENV, "version": "0.1.0"}
