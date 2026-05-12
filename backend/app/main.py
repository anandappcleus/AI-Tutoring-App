from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import get_settings

settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Sprint 4: start APScheduler nightly crew here
    yield
    # Sprint 4: stop scheduler here


app = FastAPI(
    title="SmartTutor API",
    description="AI-powered vernacular tutoring — JEE / NEET / WB Board",
    version="0.1.0",
    lifespan=lifespan,
    docs_url="/docs" if settings.APP_ENV == "development" else None,
    redoc_url=None,
)

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
    return {"status": "ok", "env": settings.APP_ENV, "version": "0.1.0"}
