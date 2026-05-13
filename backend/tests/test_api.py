"""
Sprint 4 — FastAPI route tests

All tests use httpx AsyncClient against the real FastAPI app with:
    - An in-memory SQLite database (no Postgres needed)
    - CrewAI / QuestionCrew mocked out (no NIM API calls)
    - APScheduler disabled (APP_ENV=test)

Test groups:
    TestHealth          — /health endpoint
    TestAuthRegister    — POST /auth/register
    TestAuthLogin       — POST /auth/token
    TestAuthRefresh     — POST /auth/refresh
    TestAuthMe          — GET /auth/me
    TestAskEndpoint     — POST /ask (crew mocked)
    TestPlanEndpoint    — GET /plan/{student_id}
    TestSyncAnswers     — POST /sync-answers
    TestProgressEndpoint— GET /progress/{student_id}
    TestRateLimiting    — 10-question daily cap for free-tier students

Run:
    pytest tests/test_api.py -v -m "not integration"

Integration (real DB + NIM):
    pytest tests/test_api.py -v -m integration
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone, timedelta
from typing import AsyncGenerator
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
import pytest_asyncio
from httpx import AsyncClient, ASGITransport
from sqlalchemy import event
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.ext.compiler import compiles
from sqlalchemy.dialects.postgresql import JSONB

from app.database import get_db
from app.main import app
from app.models.base import Base


# ─────────────────────────────────────────────────────────────────────
# SQLite compat: teach SQLAlchemy to render JSONB as TEXT for SQLite
# ─────────────────────────────────────────────────────────────────────

@compiles(JSONB, "sqlite")
def _render_jsonb_sqlite(type_, compiler, **kw):
    """Render JSONB as TEXT in SQLite (used only in tests)."""
    return "TEXT"


# ─────────────────────────────────────────────────────────────────────
# In-memory SQLite test database
# ─────────────────────────────────────────────────────────────────────

_TEST_DATABASE_URL = "sqlite+aiosqlite:///:memory:"


@pytest_asyncio.fixture
async def db_session() -> AsyncGenerator[AsyncSession, None]:
    """
    Fully isolated per-test database.

    Each test gets its own in-memory SQLite engine → fresh schema → fresh data.
    No data leaks between tests. The engine is disposed after the test completes.
    """
    from sqlalchemy.pool import StaticPool

    engine = create_async_engine(
        _TEST_DATABASE_URL,
        echo=False,
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    Session = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    async with Session() as session:
        yield session

    await engine.dispose()


@pytest_asyncio.fixture
async def client(db_session: AsyncSession) -> AsyncGenerator[AsyncClient, None]:
    """
    httpx AsyncClient wired to the FastAPI app.
    DB dependency is overridden to use the in-memory SQLite session.
    APScheduler is disabled via APP_ENV=test.
    """
    async def _override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = _override_get_db

    # Prevent scheduler from starting during tests
    with patch("app.main.settings") as mock_settings:
        mock_settings.APP_ENV = "test"
        mock_settings.LOG_LEVEL = "WARNING"
        mock_settings.CORS_ORIGINS = ["*"]
        mock_settings.ACCESS_TOKEN_EXPIRE_MINUTES = 30
        mock_settings.REFRESH_TOKEN_EXPIRE_DAYS = 30
        mock_settings.SECRET_KEY = "test-secret-key-for-unit-tests-only"

        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as ac:
            yield ac

    app.dependency_overrides.clear()


# ─────────────────────────────────────────────────────────────────────
# Shared helpers
# ─────────────────────────────────────────────────────────────────────

_REGISTER_PAYLOAD = {
    "name": "Riya Chatterjee",
    "email": "riya@test.example",
    "password": "securepass123",
    "preferred_language": "bn",
    "exam_target": "JEE",
}


async def _register_and_login(client: AsyncClient) -> tuple[str, str]:
    """Register a student and return (access_token, student_id)."""
    reg = await client.post("/auth/register", json=_REGISTER_PAYLOAD)
    assert reg.status_code == 201, reg.text
    student_id = reg.json()["id"]

    login = await client.post(
        "/auth/token",
        data={"username": _REGISTER_PAYLOAD["email"], "password": _REGISTER_PAYLOAD["password"]},
    )
    assert login.status_code == 200, login.text
    token = login.json()["access_token"]
    return token, student_id


# ─────────────────────────────────────────────────────────────────────
# /health
# ─────────────────────────────────────────────────────────────────────

class TestHealth:
    async def test_health_returns_200(self, client: AsyncClient):
        r = await client.get("/health")
        assert r.status_code == 200

    async def test_health_has_status_field(self, client: AsyncClient):
        r = await client.get("/health")
        data = r.json()
        assert "status" in data
        assert data["status"] in ("ok", "degraded")

    async def test_health_has_checks_field(self, client: AsyncClient):
        r = await client.get("/health")
        assert "checks" in r.json()


# ─────────────────────────────────────────────────────────────────────
# POST /auth/register
# ─────────────────────────────────────────────────────────────────────

class TestAuthRegister:
    async def test_register_success(self, client: AsyncClient):
        r = await client.post("/auth/register", json=_REGISTER_PAYLOAD)
        assert r.status_code == 201
        data = r.json()
        assert data["email"] == _REGISTER_PAYLOAD["email"]
        assert data["preferred_language"] == "bn"
        assert "id" in data
        assert "hashed_password" not in data  # never exposed

    async def test_register_duplicate_email_409(self, client: AsyncClient):
        await client.post("/auth/register", json=_REGISTER_PAYLOAD)
        r = await client.post("/auth/register", json=_REGISTER_PAYLOAD)
        assert r.status_code == 409
        assert r.json()["detail"]["error"] == "email_taken"

    async def test_register_invalid_language_422(self, client: AsyncClient):
        payload = {**_REGISTER_PAYLOAD, "email": "other@test.example", "preferred_language": "xx"}
        r = await client.post("/auth/register", json=payload)
        assert r.status_code == 422

    async def test_register_invalid_exam_target_422(self, client: AsyncClient):
        payload = {**_REGISTER_PAYLOAD, "email": "other2@test.example", "exam_target": "UPSC"}
        r = await client.post("/auth/register", json=payload)
        assert r.status_code == 422

    async def test_register_short_password_422(self, client: AsyncClient):
        payload = {**_REGISTER_PAYLOAD, "email": "other3@test.example", "password": "abc"}
        r = await client.post("/auth/register", json=payload)
        assert r.status_code == 422


# ─────────────────────────────────────────────────────────────────────
# POST /auth/token
# ─────────────────────────────────────────────────────────────────────

class TestAuthLogin:
    async def test_login_success(self, client: AsyncClient):
        await client.post("/auth/register", json=_REGISTER_PAYLOAD)
        r = await client.post(
            "/auth/token",
            data={"username": _REGISTER_PAYLOAD["email"], "password": _REGISTER_PAYLOAD["password"]},
        )
        assert r.status_code == 200
        data = r.json()
        assert "access_token" in data
        assert "refresh_token" in data
        assert data["token_type"] == "bearer"
        assert data["expires_in"] > 0

    async def test_login_wrong_password_401(self, client: AsyncClient):
        await client.post("/auth/register", json=_REGISTER_PAYLOAD)
        r = await client.post(
            "/auth/token",
            data={"username": _REGISTER_PAYLOAD["email"], "password": "wrongpass"},
        )
        assert r.status_code == 401
        assert r.json()["detail"]["error"] == "bad_credentials"

    async def test_login_unknown_email_401(self, client: AsyncClient):
        r = await client.post(
            "/auth/token",
            data={"username": "nobody@test.example", "password": "whatever"},
        )
        assert r.status_code == 401

    async def test_login_access_and_refresh_tokens_different(self, client: AsyncClient):
        await client.post("/auth/register", json=_REGISTER_PAYLOAD)
        r = await client.post(
            "/auth/token",
            data={"username": _REGISTER_PAYLOAD["email"], "password": _REGISTER_PAYLOAD["password"]},
        )
        data = r.json()
        assert data["access_token"] != data["refresh_token"]


# ─────────────────────────────────────────────────────────────────────
# POST /auth/refresh
# ─────────────────────────────────────────────────────────────────────

class TestAuthRefresh:
    async def test_refresh_returns_new_tokens(self, client: AsyncClient):
        await client.post("/auth/register", json=_REGISTER_PAYLOAD)
        login_r = await client.post(
            "/auth/token",
            data={"username": _REGISTER_PAYLOAD["email"], "password": _REGISTER_PAYLOAD["password"]},
        )
        refresh_token = login_r.json()["refresh_token"]

        r = await client.post("/auth/refresh", json={"refresh_token": refresh_token})
        assert r.status_code == 200
        data = r.json()
        assert "access_token" in data
        assert "refresh_token" in data

    async def test_refresh_with_access_token_fails_401(self, client: AsyncClient):
        await client.post("/auth/register", json=_REGISTER_PAYLOAD)
        login_r = await client.post(
            "/auth/token",
            data={"username": _REGISTER_PAYLOAD["email"], "password": _REGISTER_PAYLOAD["password"]},
        )
        access_token = login_r.json()["access_token"]  # wrong token type

        r = await client.post("/auth/refresh", json={"refresh_token": access_token})
        assert r.status_code == 401

    async def test_refresh_with_garbage_fails_401(self, client: AsyncClient):
        r = await client.post("/auth/refresh", json={"refresh_token": "not-a-real-token"})
        assert r.status_code == 401


# ─────────────────────────────────────────────────────────────────────
# GET /auth/me
# ─────────────────────────────────────────────────────────────────────

class TestAuthMe:
    async def test_me_returns_profile(self, client: AsyncClient):
        token, _ = await _register_and_login(client)
        r = await client.get("/auth/me", headers={"Authorization": f"Bearer {token}"})
        assert r.status_code == 200
        data = r.json()
        assert data["email"] == _REGISTER_PAYLOAD["email"]
        assert data["preferred_language"] == "bn"

    async def test_me_unauthenticated_401(self, client: AsyncClient):
        r = await client.get("/auth/me")
        assert r.status_code == 401

    async def test_me_invalid_token_401(self, client: AsyncClient):
        r = await client.get("/auth/me", headers={"Authorization": "Bearer garbage"})
        assert r.status_code == 401


# ─────────────────────────────────────────────────────────────────────
# POST /ask
# ─────────────────────────────────────────────────────────────────────

class TestAskEndpoint:
    _MOCK_CREW_OUTPUT = (
        '{"explanation": "Force equals mass times acceleration.", '
        '"worked_example": "F=ma example", '
        '"practice_problems": [{"question": "What is F?", "answer": "F=ma"}]}'
    )

    async def test_ask_success(self, client: AsyncClient):
        token, _ = await _register_and_login(client)
        with patch("app.routers.ask._run_crew_sync", return_value=self._MOCK_CREW_OUTPUT):
            r = await client.post(
                "/ask",
                json={"question": "What is Newton's second law?"},
                headers={"Authorization": f"Bearer {token}"},
            )
        assert r.status_code == 200
        data = r.json()
        assert "explanation" in data
        assert data["language"] == "bn"  # student's preferred_language
        assert len(data["practice_problems"]) == 1

    async def test_ask_language_override(self, client: AsyncClient):
        token, _ = await _register_and_login(client)
        with patch("app.routers.ask._run_crew_sync", return_value=self._MOCK_CREW_OUTPUT):
            r = await client.post(
                "/ask",
                json={"question": "What is Newton's second law?", "language": "hi"},
                headers={"Authorization": f"Bearer {token}"},
            )
        assert r.status_code == 200
        assert r.json()["language"] == "hi"

    async def test_ask_unauthenticated_401(self, client: AsyncClient):
        r = await client.post("/ask", json={"question": "Any question"})
        assert r.status_code == 401

    async def test_ask_question_too_short_422(self, client: AsyncClient):
        token, _ = await _register_and_login(client)
        r = await client.post(
            "/ask",
            json={"question": "Hi"},
            headers={"Authorization": f"Bearer {token}"},
        )
        assert r.status_code == 422

    async def test_ask_non_json_crew_output_still_returns_200(self, client: AsyncClient):
        token, _ = await _register_and_login(client)
        with patch("app.routers.ask._run_crew_sync", return_value="I cannot answer that."):
            r = await client.post(
                "/ask",
                json={"question": "What is Newton's second law?"},
                headers={"Authorization": f"Bearer {token}"},
            )
        assert r.status_code == 200
        data = r.json()
        assert data["raw_output"] == "I cannot answer that."

    async def test_ask_crew_error_returns_503(self, client: AsyncClient):
        token, _ = await _register_and_login(client)
        with patch("app.routers.ask._run_crew_sync", side_effect=RuntimeError("NIM down")):
            r = await client.post(
                "/ask",
                json={"question": "What is Newton's second law?"},
                headers={"Authorization": f"Bearer {token}"},
            )
        assert r.status_code == 503
        assert r.json()["detail"]["error"] == "agent_unavailable"

    async def test_ask_invalid_language_422(self, client: AsyncClient):
        token, _ = await _register_and_login(client)
        r = await client.post(
            "/ask",
            json={"question": "What is gravity?", "language": "xx"},
            headers={"Authorization": f"Bearer {token}"},
        )
        assert r.status_code == 422


# ─────────────────────────────────────────────────────────────────────
# GET /plan/{student_id}
# ─────────────────────────────────────────────────────────────────────

class TestPlanEndpoint:
    async def test_plan_not_found_404(self, client: AsyncClient):
        token, sid = await _register_and_login(client)
        r = await client.get(
            f"/plan/{sid}",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert r.status_code == 404
        assert r.json()["detail"]["error"] == "plan_not_found"

    async def test_plan_forbidden_for_other_student(self, client: AsyncClient):
        token, _ = await _register_and_login(client)
        other_id = str(uuid.uuid4())
        r = await client.get(
            f"/plan/{other_id}",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert r.status_code == 403
        assert r.json()["detail"]["error"] == "forbidden"

    async def test_plan_unauthenticated_401(self, client: AsyncClient):
        r = await client.get(f"/plan/{uuid.uuid4()}")
        assert r.status_code == 401

    async def test_plan_returns_plan_when_exists(self, client: AsyncClient, db_session: AsyncSession):
        from app.models.student import StudyPlan
        from datetime import date

        token, sid = await _register_and_login(client)
        # Insert a study plan directly into the test DB
        plan = StudyPlan(
            student_id=uuid.UUID(sid),
            plan_date=date.today(),
            plan_json=[{"topic": "Kinematics", "duration_min": 45, "priority": 1}],
        )
        db_session.add(plan)
        await db_session.flush()

        r = await client.get(
            f"/plan/{sid}",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert r.status_code == 200
        data = r.json()
        assert data["student_id"] == sid
        assert len(data["topics"]) == 1
        assert data["topics"][0]["topic"] == "Kinematics"


# ─────────────────────────────────────────────────────────────────────
# POST /sync-answers
# ─────────────────────────────────────────────────────────────────────

class TestSyncAnswers:
    _ANSWERS = [
        {
            "question": "What is the speed of light?",
            "topic": "Optics",
            "subject": "physics",
            "is_correct": True,
        },
        {
            "question": "What is Avogadro's number?",
            "topic": "Mole Concept",
            "subject": "chemistry",
            "is_correct": False,
        },
    ]

    async def test_sync_returns_counts(self, client: AsyncClient):
        token, _ = await _register_and_login(client)
        r = await client.post(
            "/sync-answers",
            json={"answers": self._ANSWERS},
            headers={"Authorization": f"Bearer {token}"},
        )
        assert r.status_code == 200
        data = r.json()
        assert data["synced"] == 2
        assert data["skipped"] == 0

    async def test_sync_empty_list_422(self, client: AsyncClient):
        token, _ = await _register_and_login(client)
        r = await client.post(
            "/sync-answers",
            json={"answers": []},
            headers={"Authorization": f"Bearer {token}"},
        )
        assert r.status_code == 422

    async def test_sync_unauthenticated_401(self, client: AsyncClient):
        r = await client.post("/sync-answers", json={"answers": self._ANSWERS})
        assert r.status_code == 401

    async def test_sync_stores_answers_in_db(
        self, client: AsyncClient, db_session: AsyncSession
    ):
        from app.models.student import QuizAnswer
        from sqlalchemy import select

        token, sid = await _register_and_login(client)
        await client.post(
            "/sync-answers",
            json={"answers": self._ANSWERS},
            headers={"Authorization": f"Bearer {token}"},
        )
        result = await db_session.execute(
            select(QuizAnswer).where(QuizAnswer.student_id == uuid.UUID(sid))
        )
        rows = result.scalars().all()
        assert len(rows) == 2
        topics = {r.topic for r in rows}
        assert "Optics" in topics


# ─────────────────────────────────────────────────────────────────────
# GET /progress/{student_id}
# ─────────────────────────────────────────────────────────────────────

class TestProgressEndpoint:
    async def test_progress_empty(self, client: AsyncClient):
        token, sid = await _register_and_login(client)
        r = await client.get(
            f"/progress/{sid}",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert r.status_code == 200
        data = r.json()
        assert data["total_questions"] == 0
        assert data["topics"] == []
        assert data["weak_topics"] == []

    async def test_progress_aggregates_correctly(
        self, client: AsyncClient, db_session: AsyncSession
    ):
        from app.models.student import QuizAnswer

        token, sid = await _register_and_login(client)
        now = datetime.now(tz=timezone.utc)
        # 2 correct + 1 wrong on Kinematics → 66.7% — NOT weak
        # 1 correct + 3 wrong on Thermodynamics → 25% — weak
        for is_correct, topic in [
            (True, "Kinematics"), (True, "Kinematics"), (False, "Kinematics"),
            (True, "Thermodynamics"), (False, "Thermodynamics"),
            (False, "Thermodynamics"), (False, "Thermodynamics"),
        ]:
            db_session.add(QuizAnswer(
                student_id=uuid.UUID(sid),
                question=f"Q about {topic}",
                topic=topic,
                subject="physics",
                is_correct=is_correct,
                answered_at=now - timedelta(hours=1),
                synced=True,
            ))
        await db_session.flush()

        r = await client.get(
            f"/progress/{sid}",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert r.status_code == 200
        data = r.json()
        assert data["total_questions"] == 7
        assert "Thermodynamics" in data["weak_topics"]
        assert "Kinematics" not in data["weak_topics"]

    async def test_progress_forbidden_for_other_student(self, client: AsyncClient):
        token, _ = await _register_and_login(client)
        other_id = str(uuid.uuid4())
        r = await client.get(
            f"/progress/{other_id}",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert r.status_code == 403

    async def test_progress_unauthenticated_401(self, client: AsyncClient):
        r = await client.get(f"/progress/{uuid.uuid4()}")
        assert r.status_code == 401


# ─────────────────────────────────────────────────────────────────────
# Rate limiting (freemium daily cap)
# ─────────────────────────────────────────────────────────────────────

class TestRateLimiting:
    async def test_free_student_hits_daily_limit(
        self, client: AsyncClient, db_session: AsyncSession
    ):
        from app.models.student import QuizAnswer
        from app.routers.ask import FREE_DAILY_LIMIT

        token, sid = await _register_and_login(client)
        now = datetime.now(tz=timezone.utc)

        # Pre-fill daily_limit answers for today
        for i in range(FREE_DAILY_LIMIT):
            db_session.add(QuizAnswer(
                student_id=uuid.UUID(sid),
                question=f"Question {i}",
                is_correct=True,
                answered_at=now - timedelta(minutes=i),
                synced=True,
            ))
        await db_session.flush()

        with patch("app.routers.ask._run_crew_sync", return_value="{}"):
            r = await client.post(
                "/ask",
                json={"question": "One more question after the limit"},
                headers={"Authorization": f"Bearer {token}"},
            )
        assert r.status_code == 429
        assert r.json()["detail"]["error"] == "daily_limit_reached"
