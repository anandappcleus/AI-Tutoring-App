"""
Mock Tests router

Endpoints:
    GET  /mock-tests                                  — catalog listing
    GET  /mock-tests/{paper_id}/questions             — all questions for a paper
    POST /mock-tests/{paper_id}/attempts              — start a new attempt
    PATCH /mock-tests/{paper_id}/attempts/{id}        — auto-save answers in-progress
    POST /mock-tests/{paper_id}/attempts/{id}/submit  — submit + score
    GET  /mock-tests/attempts/{id}/result             — fetch scored result
"""

from __future__ import annotations

import logging
import uuid
from datetime import datetime, timezone
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.mock_test import MockTestAttempt, MockTestQuestion
from app.models.student import Student
from app.routers.auth import get_current_student

log = logging.getLogger(__name__)
router = APIRouter()


# ── Pydantic schemas ──────────────────────────────────────────────────

class MockTestResponse(BaseModel):
    id: str
    title: str
    exam_type: str          # JEE | NEET | WBCHSE
    subjects: str
    year: int
    question_count: int
    duration_minutes: int
    difficulty: str         # Easy | Medium | Hard
    questions_available: bool = False  # True when questions are loaded in DB


class QuestionOut(BaseModel):
    id: str
    question_number: int
    subject: str
    topic: str | None
    question_text: str
    options: list[str] | None   # None for integer-type questions
    question_type: str          # MCQ | integer | multi_correct
    has_image: bool


class AttemptStartResponse(BaseModel):
    attempt_id: str
    paper_id: str
    started_at: str          # ISO-8601
    duration_minutes: int    # client-side countdown seed


class SaveAnswersRequest(BaseModel):
    answers: dict[str, str]  # {question_id: answer_string}


class SubmitResponse(BaseModel):
    attempt_id: str
    score: int
    max_score: int
    accuracy_pct: float
    time_taken_seconds: int | None
    subject_breakdown: dict   # {"physics": {"score": 48, "max": 120, "accuracy": 40.0}, ...}


class AttemptResultResponse(SubmitResponse):
    answers: dict[str, str]         # student's answers
    correct_answers: dict[str, str] # question_id → correct answer


# ── Static catalog ────────────────────────────────────────────────────

_MOCK_TEST_CATALOG: list[MockTestResponse] = [
    # ── JEE Mains 2024 ───────────────────────────────────────────────
    MockTestResponse(
        id="jee-2024-j1-s1", title="JEE Mains Jan 2024 — Shift 1",
        exam_type="JEE", subjects="Physics · Chemistry · Maths",
        year=2024, question_count=90, duration_minutes=180, difficulty="Hard",
    ),
    MockTestResponse(
        id="jee-2024-j1-s2", title="JEE Mains Jan 2024 — Shift 2",
        exam_type="JEE", subjects="Physics · Chemistry · Maths",
        year=2024, question_count=90, duration_minutes=180, difficulty="Hard",
    ),
    MockTestResponse(
        id="jee-2024-a1-s1", title="JEE Mains Apr 2024 — Shift 1",
        exam_type="JEE", subjects="Physics · Chemistry · Maths",
        year=2024, question_count=90, duration_minutes=180, difficulty="Hard",
    ),
    # ── JEE Mains 2023 ───────────────────────────────────────────────
    MockTestResponse(
        id="jee-2023-j1-s1", title="JEE Mains Jan 2023 — Shift 1",
        exam_type="JEE", subjects="Physics · Chemistry · Maths",
        year=2023, question_count=90, duration_minutes=180, difficulty="Medium",
    ),
    MockTestResponse(
        id="jee-2023-j1-s2", title="JEE Mains Jan 2023 — Shift 2",
        exam_type="JEE", subjects="Physics · Chemistry · Maths",
        year=2023, question_count=90, duration_minutes=180, difficulty="Medium",
    ),
    # ── JEE Mains 2019 — Jan session ─────────────────────────────────
    MockTestResponse(
        id="jee-2019-0109-am", title="JEE Mains Jan 2019 — 9 Jan Morning",
        exam_type="JEE", subjects="Physics · Chemistry · Maths",
        year=2019, question_count=90, duration_minutes=180, difficulty="Medium",
        questions_available=True,
    ),
    MockTestResponse(
        id="jee-2019-0109-pm", title="JEE Mains Jan 2019 — 9 Jan Evening",
        exam_type="JEE", subjects="Physics · Chemistry · Maths",
        year=2019, question_count=90, duration_minutes=180, difficulty="Medium",
        questions_available=True,
    ),
    MockTestResponse(
        id="jee-2019-0110-am", title="JEE Mains Jan 2019 — 10 Jan Morning",
        exam_type="JEE", subjects="Physics · Chemistry · Maths",
        year=2019, question_count=90, duration_minutes=180, difficulty="Medium",
        questions_available=True,
    ),
    MockTestResponse(
        id="jee-2019-0110-pm", title="JEE Mains Jan 2019 — 10 Jan Evening",
        exam_type="JEE", subjects="Physics · Chemistry · Maths",
        year=2019, question_count=90, duration_minutes=180, difficulty="Medium",
        questions_available=True,
    ),
    MockTestResponse(
        id="jee-2019-0111-am", title="JEE Mains Jan 2019 — 11 Jan Morning",
        exam_type="JEE", subjects="Physics · Chemistry · Maths",
        year=2019, question_count=90, duration_minutes=180, difficulty="Medium",
        questions_available=True,
    ),
    MockTestResponse(
        id="jee-2019-0111-pm", title="JEE Mains Jan 2019 — 11 Jan Evening",
        exam_type="JEE", subjects="Physics · Chemistry · Maths",
        year=2019, question_count=90, duration_minutes=180, difficulty="Medium",
        questions_available=True,
    ),
    MockTestResponse(
        id="jee-2019-0112-am", title="JEE Mains Jan 2019 — 12 Jan Morning",
        exam_type="JEE", subjects="Physics · Chemistry · Maths",
        year=2019, question_count=90, duration_minutes=180, difficulty="Medium",
        questions_available=True,
    ),
    MockTestResponse(
        id="jee-2019-0112-pm", title="JEE Mains Jan 2019 — 12 Jan Evening",
        exam_type="JEE", subjects="Physics · Chemistry · Maths",
        year=2019, question_count=90, duration_minutes=180, difficulty="Medium",
        questions_available=True,
    ),
    # ── JEE Mains 2019 — April session ───────────────────────────────
    MockTestResponse(
        id="jee-2019-0408-am", title="JEE Mains Apr 2019 — 8 Apr Morning",
        exam_type="JEE", subjects="Physics · Chemistry · Maths",
        year=2019, question_count=90, duration_minutes=180, difficulty="Medium",
        questions_available=True,
    ),
    MockTestResponse(
        id="jee-2019-0408-pm", title="JEE Mains Apr 2019 — 8 Apr Evening",
        exam_type="JEE", subjects="Physics · Chemistry · Maths",
        year=2019, question_count=90, duration_minutes=180, difficulty="Medium",
        questions_available=True,
    ),
    MockTestResponse(
        id="jee-2019-0409-am", title="JEE Mains Apr 2019 — 9 Apr Morning",
        exam_type="JEE", subjects="Physics · Chemistry · Maths",
        year=2019, question_count=90, duration_minutes=180, difficulty="Medium",
        questions_available=True,
    ),
    MockTestResponse(
        id="jee-2019-0409-pm", title="JEE Mains Apr 2019 — 9 Apr Evening",
        exam_type="JEE", subjects="Physics · Chemistry · Maths",
        year=2019, question_count=90, duration_minutes=180, difficulty="Medium",
        questions_available=True,
    ),
    MockTestResponse(
        id="jee-2019-0410-am", title="JEE Mains Apr 2019 — 10 Apr Morning",
        exam_type="JEE", subjects="Physics · Chemistry · Maths",
        year=2019, question_count=90, duration_minutes=180, difficulty="Medium",
        questions_available=True,
    ),
    MockTestResponse(
        id="jee-2019-0410-pm", title="JEE Mains Apr 2019 — 10 Apr Evening",
        exam_type="JEE", subjects="Physics · Chemistry · Maths",
        year=2019, question_count=90, duration_minutes=180, difficulty="Medium",
        questions_available=True,
    ),
    MockTestResponse(
        id="jee-2019-0412-am", title="JEE Mains Apr 2019 — 12 Apr Morning",
        exam_type="JEE", subjects="Physics · Chemistry · Maths",
        year=2019, question_count=90, duration_minutes=180, difficulty="Medium",
        questions_available=True,
    ),
    MockTestResponse(
        id="jee-2019-0412-pm", title="JEE Mains Apr 2019 — 12 Apr Evening",
        exam_type="JEE", subjects="Physics · Chemistry · Maths",
        year=2019, question_count=90, duration_minutes=180, difficulty="Medium",
        questions_available=True,
    ),
    # ── JEE Advanced ─────────────────────────────────────────────────
    MockTestResponse(
        id="jee-adv-2024-p1", title="JEE Advanced 2024 — Paper 1",
        exam_type="JEE", subjects="Physics · Chemistry · Maths",
        year=2024, question_count=54, duration_minutes=180, difficulty="Hard",
    ),
    MockTestResponse(
        id="jee-adv-2024-p2", title="JEE Advanced 2024 — Paper 2",
        exam_type="JEE", subjects="Physics · Chemistry · Maths",
        year=2024, question_count=54, duration_minutes=180, difficulty="Hard",
    ),
    MockTestResponse(
        id="jee-adv-2023-p1", title="JEE Advanced 2023 — Paper 1",
        exam_type="JEE", subjects="Physics · Chemistry · Maths",
        year=2023, question_count=54, duration_minutes=180, difficulty="Hard",
    ),
    # ── NEET ─────────────────────────────────────────────────────────
    MockTestResponse(
        id="neet-2025", title="NEET UG 2025",
        exam_type="NEET", subjects="Physics · Chemistry · Biology",
        year=2025, question_count=180, duration_minutes=200, difficulty="Hard",
        questions_available=True,
    ),
    MockTestResponse(
        id="neet-2023", title="NEET UG 2023",
        exam_type="NEET", subjects="Physics · Chemistry · Biology",
        year=2023, question_count=180, duration_minutes=200, difficulty="Medium",
        questions_available=True,
    ),
    MockTestResponse(
        id="neet-2022", title="NEET UG 2022",
        exam_type="NEET", subjects="Physics · Chemistry · Biology",
        year=2022, question_count=180, duration_minutes=200, difficulty="Medium",
        questions_available=True,
    ),
    MockTestResponse(
        id="neet-2021", title="NEET UG 2021",
        exam_type="NEET", subjects="Physics · Chemistry · Biology",
        year=2021, question_count=180, duration_minutes=200, difficulty="Easy",
        questions_available=True,
    ),
    MockTestResponse(
        id="neet-2020", title="NEET UG 2020",
        exam_type="NEET", subjects="Physics · Chemistry · Biology",
        year=2020, question_count=180, duration_minutes=200, difficulty="Easy",
        questions_available=True,
    ),
    MockTestResponse(
        id="neet-2019", title="NEET UG 2019",
        exam_type="NEET", subjects="Physics · Chemistry · Biology",
        year=2019, question_count=180, duration_minutes=200, difficulty="Medium",
        questions_available=True,
    ),
    MockTestResponse(
        id="neet-2018", title="NEET UG 2018",
        exam_type="NEET", subjects="Physics · Chemistry · Biology",
        year=2018, question_count=180, duration_minutes=200, difficulty="Medium",
        questions_available=True,
    ),
    MockTestResponse(
        id="neet-2016", title="NEET UG 2016",
        exam_type="NEET", subjects="Physics · Chemistry · Biology",
        year=2016, question_count=180, duration_minutes=200, difficulty="Easy",
        questions_available=True,
    ),
    # ── WBCHSE ───────────────────────────────────────────────────────
    MockTestResponse(
        id="wbchse-phy-2024", title="WBCHSE Physics 2024",
        exam_type="WBCHSE", subjects="Physics",
        year=2024, question_count=50, duration_minutes=90, difficulty="Medium",
    ),
    MockTestResponse(
        id="wbchse-chem-2024", title="WBCHSE Chemistry 2024",
        exam_type="WBCHSE", subjects="Chemistry",
        year=2024, question_count=50, duration_minutes=90, difficulty="Medium",
    ),
    MockTestResponse(
        id="wbchse-math-2024", title="WBCHSE Mathematics 2024",
        exam_type="WBCHSE", subjects="Mathematics",
        year=2024, question_count=50, duration_minutes=90, difficulty="Medium",
    ),
    MockTestResponse(
        id="wbchse-bio-2024", title="WBCHSE Biology 2024",
        exam_type="WBCHSE", subjects="Biology",
        year=2024, question_count=50, duration_minutes=90, difficulty="Easy",
    ),
    MockTestResponse(
        id="wbchse-phy-2023", title="WBCHSE Physics 2023",
        exam_type="WBCHSE", subjects="Physics",
        year=2023, question_count=50, duration_minutes=90, difficulty="Medium",
    ),
    MockTestResponse(
        id="wbchse-chem-2023", title="WBCHSE Chemistry 2023",
        exam_type="WBCHSE", subjects="Chemistry",
        year=2023, question_count=50, duration_minutes=90, difficulty="Medium",
    ),
]

# Build a lookup for duration by paper_id (used when starting an attempt)
_PAPER_DURATION: dict[str, int] = {p.id: p.duration_minutes for p in _MOCK_TEST_CATALOG}


# ── Scoring engine ────────────────────────────────────────────────────

def _score_attempt(
    questions: list[MockTestQuestion],
    answers: dict[str, str],   # {question_uuid_str: answer_str}
) -> tuple[int, int, dict]:
    """
    Score a submitted attempt.

    Marking scheme:
        JEE MCQ:      +4 correct / -1 incorrect / 0 unattempted
        JEE integer:  +4 correct /  0 incorrect / 0 unattempted
        NEET MCQ:     +4 correct / -1 incorrect / 0 unattempted

    Returns (score, max_score, subject_breakdown).
    subject_breakdown: {"physics": {"score": int, "max": int, "accuracy": float}, ...}
    """
    score = 0
    breakdown: dict[str, dict] = {}

    for q in questions:
        subj = q.subject
        if subj not in breakdown:
            breakdown[subj] = {"score": 0, "max": 0}
        breakdown[subj]["max"] += 4  # every question is worth 4 marks

        given = answers.get(str(q.id), "").strip()
        if not given:
            continue  # unattempted — 0 marks

        correct = (q.correct_answer or "").strip()
        if given == correct:
            breakdown[subj]["score"] += 4
            score += 4
        else:
            # integer-type: no negative marking
            if q.question_type != "integer":
                breakdown[subj]["score"] -= 1
                score -= 1

    max_score = sum(v["max"] for v in breakdown.values())

    for subj, vals in breakdown.items():
        vals["accuracy"] = round(
            (vals["score"] / vals["max"] * 100) if vals["max"] else 0.0, 2
        )

    return score, max_score, breakdown


# ── Routes ────────────────────────────────────────────────────────────

@router.get("", response_model=list[MockTestResponse], summary="List mock test papers")
async def list_mock_tests(
    exam_type: str | None = Query(
        default=None,
        pattern="^(JEE|NEET|WBCHSE)$",
        description="Filter by exam type. Omit to return all papers.",
    ),
    db: AsyncSession = Depends(get_db),
    current_student: Student = Depends(get_current_student),
) -> list[MockTestResponse]:
    """Return the catalog of past-paper mock tests, sorted by year descending.
    The questions_available flag is determined live from the DB so it is always
    accurate regardless of what the static catalog says.
    """
    # Fetch the set of paper_ids that actually have questions in the DB
    rows = await db.execute(
        select(MockTestQuestion.paper_id).distinct()
    )
    papers_with_questions: set[str] = {row[0] for row in rows.all()}

    catalog = list(_MOCK_TEST_CATALOG)
    if exam_type:
        catalog = [t for t in catalog if t.exam_type == exam_type]
        log.info("mock_tests.list  exam_type=%s  count=%d", exam_type, len(catalog))
    else:
        log.info("mock_tests.list  exam_type=all  count=%d", len(catalog))

    # Patch questions_available based on real DB state
    result = []
    for entry in sorted(catalog, key=lambda t: t.year, reverse=True):
        available = entry.id in papers_with_questions
        result.append(entry.model_copy(update={"questions_available": available}))

    return result


@router.get(
    "/{paper_id}/questions",
    response_model=list[QuestionOut],
    summary="Fetch all questions for a paper (Full Paper Mode)",
)
async def get_paper_questions(
    paper_id: str,
    db: AsyncSession = Depends(get_db),
    current_student: Student = Depends(get_current_student),
) -> list[QuestionOut]:
    """
    Return all questions for a paper_id, ordered by subject then question_number.
    Returns 404 if no questions are loaded for this paper yet.
    """
    result = await db.execute(
        select(MockTestQuestion)
        .where(MockTestQuestion.paper_id == paper_id)
        .order_by(MockTestQuestion.subject, MockTestQuestion.question_number)
    )
    questions = result.scalars().all()
    if not questions:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"No questions found for paper '{paper_id}'. "
                   "Run the extraction pipeline first.",
        )
    log.info("mock_tests.questions  paper_id=%s  count=%d", paper_id, len(questions))
    return [
        QuestionOut(
            id=str(q.id),
            question_number=q.question_number,
            subject=q.subject,
            topic=q.topic,
            question_text=q.question_text,
            options=q.options,
            question_type=q.question_type,
            has_image=q.has_image,
        )
        for q in questions
    ]


@router.post(
    "/{paper_id}/attempts",
    response_model=AttemptStartResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Start a new full-paper attempt",
)
async def start_attempt(
    paper_id: str,
    db: AsyncSession = Depends(get_db),
    current_student: Student = Depends(get_current_student),
) -> AttemptStartResponse:
    """Create a new attempt record. Client uses returned attempt_id for all subsequent calls."""
    # Verify paper exists in catalog
    if paper_id not in _PAPER_DURATION:
        raise HTTPException(status_code=404, detail=f"Unknown paper_id '{paper_id}'")

    attempt = MockTestAttempt(
        id=uuid.uuid4(),
        student_id=current_student.id,
        paper_id=paper_id,
        started_at=datetime.now(timezone.utc),
        answers={},
    )
    db.add(attempt)
    await db.commit()
    log.info(
        "mock_tests.attempt.start  student=%s  paper=%s  attempt=%s",
        current_student.id, paper_id, attempt.id,
    )
    return AttemptStartResponse(
        attempt_id=str(attempt.id),
        paper_id=paper_id,
        started_at=attempt.started_at.isoformat(),
        duration_minutes=_PAPER_DURATION[paper_id],
    )


@router.patch(
    "/{paper_id}/attempts/{attempt_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Auto-save answers during a live attempt",
)
async def save_answers(
    paper_id: str,
    attempt_id: uuid.UUID,
    body: SaveAnswersRequest,
    db: AsyncSession = Depends(get_db),
    current_student: Student = Depends(get_current_student),
) -> None:
    """Merge the provided answers dict into the attempt's stored answers."""
    attempt = await db.get(MockTestAttempt, attempt_id)
    if not attempt or attempt.student_id != current_student.id:
        raise HTTPException(status_code=404, detail="Attempt not found")
    if attempt.submitted_at is not None:
        raise HTTPException(status_code=409, detail="Attempt already submitted")

    # Merge (client sends only changed answers, not the full dict)
    merged = dict(attempt.answers or {})
    merged.update(body.answers)
    attempt.answers = merged
    await db.commit()


@router.post(
    "/{paper_id}/attempts/{attempt_id}/submit",
    response_model=SubmitResponse,
    summary="Submit attempt and receive scored result",
)
async def submit_attempt(
    paper_id: str,
    attempt_id: uuid.UUID,
    body: SaveAnswersRequest | None = None,
    db: AsyncSession = Depends(get_db),
    current_student: Student = Depends(get_current_student),
) -> SubmitResponse:
    """
    Finalise an attempt: merge any last answers, score it, persist results.
    Idempotent — calling again returns the cached score.
    """
    attempt = await db.get(MockTestAttempt, attempt_id)
    if not attempt or attempt.student_id != current_student.id:
        raise HTTPException(status_code=404, detail="Attempt not found")

    # Already scored — return cached result
    if attempt.submitted_at is not None and attempt.score is not None:
        return SubmitResponse(
            attempt_id=str(attempt.id),
            score=attempt.score,
            max_score=attempt.max_score or 0,
            accuracy_pct=float(attempt.accuracy_pct or 0),
            time_taken_seconds=attempt.time_taken_seconds,
            subject_breakdown=attempt.subject_breakdown or {},
        )

    # Merge final answers (body may be None if client already auto-saved)
    merged = dict(attempt.answers or {})
    if body is not None:
        merged.update(body.answers)
    attempt.answers = merged

    # Load questions for scoring
    result = await db.execute(
        select(MockTestQuestion).where(MockTestQuestion.paper_id == paper_id)
    )
    questions = result.scalars().all()

    score, max_score, breakdown = _score_attempt(questions, merged)

    now = datetime.now(timezone.utc)
    time_taken = int((now - attempt.started_at).total_seconds())
    accuracy = round((score / max_score * 100) if max_score else 0.0, 2)

    attempt.submitted_at = now
    attempt.time_taken_seconds = time_taken
    attempt.score = score
    attempt.max_score = max_score
    attempt.accuracy_pct = Decimal(str(accuracy))
    attempt.subject_breakdown = breakdown
    await db.commit()

    log.info(
        "mock_tests.attempt.submit  student=%s  paper=%s  score=%d/%d  accuracy=%.1f%%",
        current_student.id, paper_id, score, max_score, accuracy,
    )
    return SubmitResponse(
        attempt_id=str(attempt.id),
        score=score,
        max_score=max_score,
        accuracy_pct=accuracy,
        time_taken_seconds=time_taken,
        subject_breakdown=breakdown,
    )


@router.get(
    "/attempts/{attempt_id}/result",
    response_model=AttemptResultResponse,
    summary="Fetch full scored result with correct answers (post-exam review)",
)
async def get_attempt_result(
    attempt_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_student: Student = Depends(get_current_student),
) -> AttemptResultResponse:
    """
    Returns the scored attempt with the student's answers and the correct answers
    for every question in the paper — used to drive the post-exam review screen.
    """
    attempt = await db.get(MockTestAttempt, attempt_id)
    if not attempt or attempt.student_id != current_student.id:
        raise HTTPException(status_code=404, detail="Attempt not found")
    if attempt.submitted_at is None:
        raise HTTPException(status_code=409, detail="Attempt not yet submitted")

    # Fetch correct answers
    result = await db.execute(
        select(MockTestQuestion).where(MockTestQuestion.paper_id == attempt.paper_id)
    )
    questions = result.scalars().all()
    correct_map = {str(q.id): q.correct_answer for q in questions}

    return AttemptResultResponse(
        attempt_id=str(attempt.id),
        score=attempt.score or 0,
        max_score=attempt.max_score or 0,
        accuracy_pct=float(attempt.accuracy_pct or 0),
        time_taken_seconds=attempt.time_taken_seconds,
        subject_breakdown=attempt.subject_breakdown or {},
        answers=attempt.answers or {},
        correct_answers=correct_map,
    )
