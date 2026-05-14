import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.config import get_settings
from app.logging_config import configure_logging
from app.middleware import RequestLoggingMiddleware

settings = get_settings()

# Configure logging before anything else logs (including SQLAlchemy engine init)
configure_logging(level=settings.LOG_LEVEL, env=settings.APP_ENV)

log = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    from app.database import ping_db, _mask_db_url
    from app.scheduler import start_scheduler, stop_scheduler

    log.info(
        "startup  env=%s  version=0.1.0  db=%s",
        settings.APP_ENV,
        _mask_db_url(settings.DATABASE_URL),
    )
    # Verify DB connectivity at startup — warn but don't crash.
    # Routes that need the DB will fail with a 503 if it's unreachable.
    db_ok = await ping_db()
    if not db_ok:
        log.warning(
            "startup  db=unreachable — app will start but DB-dependent routes will fail. "
            "Check DATABASE_URL in .env."
        )
    else:
        log.info("startup  db=reachable")

    # Start the nightly APScheduler job (skipped in test environments)
    if settings.APP_ENV != "test":
        start_scheduler()

    yield

    stop_scheduler()
    log.info("shutdown")


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


# ── Global exception handler ──────────────────────────────────────
# Catches any exception not handled by a route and returns a structured JSON
# 500 instead of FastAPI's default plain-text response.
@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    log.error(
        "unhandled_exception  %s %s  %s: %s",
        request.method,
        request.url.path,
        type(exc).__name__,
        exc,
        exc_info=True,
    )
    return JSONResponse(
        status_code=500,
        content={
            "error": "internal_server_error",
            "detail": "An unexpected error occurred. The team has been notified.",
            "type": type(exc).__name__,
        },
    )


# ── Routes ────────────────────────────────────────────────────
from app.routers import auth, ask, plan, progress, packs, admin, mock_tests

app.include_router(auth.router, prefix="/auth", tags=["auth"])
app.include_router(ask.router, tags=["ask"])
app.include_router(plan.router, tags=["plan"])
app.include_router(progress.router, tags=["progress"])
app.include_router(packs.router, prefix="/packs", tags=["packs"])
app.include_router(mock_tests.router, prefix="/mock-tests", tags=["mock-tests"])
app.include_router(admin.router, prefix="/admin", tags=["admin"])


@app.get("/health", tags=["health"])
async def health():
    """Liveness + readiness probe. Checks DB connectivity."""
    from app.database import ping_db
    db_ok = await ping_db()
    db_status = "ok" if db_ok else "unreachable"
    overall = "ok" if db_ok else "degraded"
    log.debug("health_check  db=%s  status=%s", db_status, overall)
    return {
        "status": overall,
        "env": settings.APP_ENV,
        "version": "0.1.0",
        "checks": {"db": db_status},
    }
