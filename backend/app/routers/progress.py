"""
Progress router — sync offline quiz answers and retrieve weekly progress.

Endpoints:
    POST /sync-answers          Batch-insert quiz answers from the iOS offline queue
    GET  /progress/{student_id} Weekly accuracy breakdown by topic for parent dashboard

Design:
    - sync-answers is idempotent: duplicate question records (same student + question +
      answered_at within 1 second) are silently skipped to protect against iOS retry storms.
    - progress aggregates the last 7 days of quiz_answers by topic. The iOS app calls
      this for the parent dashboard and the student progress chart.
    - Both endpoints enforce student_id == current_student.id to prevent horizontal
      privilege escalation.

Logging:
    - Sync batch size, success count, and skip count logged per request.
    - Per-row errors logged at WARNING (non-fatal — rest of batch continues).
    - Progress query date range logged for traceability.
    - All DB errors logged at ERROR with exc_info.
"""

from __future__ import annotations

import logging
import uuid
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select, func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.student import QuizAnswer, Student
from app.routers.auth import get_current_student

log = logging.getLogger(__name__)
router = APIRouter()


# ── Pydantic schemas ──────────────────────────────────────────────────

class QuizAnswerIn(BaseModel):
    question: str = Field(..., min_length=1, max_length=2000)
    topic: str | None = Field(None, max_length=200)
    subject: str | None = Field(None, max_length=100)
    is_correct: bool
    answered_at: datetime = Field(
        default_factory=lambda: datetime.now(tz=timezone.utc)
    )


class SyncRequest(BaseModel):
    answers: list[QuizAnswerIn] = Field(..., min_length=1, max_length=100)


class SyncResponse(BaseModel):
    synced: int
    skipped: int


class TopicAccuracy(BaseModel):
    topic: str
    subject: str | None
    total: int
    correct: int
    accuracy_pct: float


class ProgressResponse(BaseModel):
    student_id: str
    week_start: date
    week_end: date
    total_questions: int
    correct_questions: int
    overall_accuracy_pct: float
    topics: list[TopicAccuracy]
    weak_topics: list[str]   # topics with accuracy < 50%


# ── POST /sync-answers ────────────────────────────────────────────────

@router.post("/sync-answers", response_model=SyncResponse, tags=["progress"])
async def sync_answers(
    body: SyncRequest,
    db: AsyncSession = Depends(get_db),
    current_student: Student = Depends(get_current_student),
):
    """
    Upload a batch of quiz answers from the iOS offline queue.
    Duplicate rows are silently skipped. Returns counts of synced vs skipped.
    """
    student_id = current_student.id
    log.info(
        "sync_answers.start  student_id=%s  batch=%d",
        student_id, len(body.answers),
    )

    synced = 0
    skipped = 0

    for i, ans in enumerate(body.answers):
        record = QuizAnswer(
            student_id=student_id,
            question=ans.question,
            topic=ans.topic,
            subject=ans.subject,
            is_correct=ans.is_correct,
            answered_at=ans.answered_at,
            synced=True,
        )
        db.add(record)
        try:
            await db.flush()  # send to DB within transaction; catch constraint errors per row
            synced += 1
        except IntegrityError:
            await db.rollback()
            # Re-open transaction for the next row
            log.debug(
                "sync_answers.duplicate_skipped  student_id=%s  row=%d  q=%r",
                student_id, i, ans.question[:60],
            )
            skipped += 1
        except Exception:
            await db.rollback()
            log.warning(
                "sync_answers.row_error  student_id=%s  row=%d",
                student_id, i, exc_info=True,
            )
            skipped += 1

    try:
        await db.commit()
    except Exception:
        await db.rollback()
        log.error(
            "sync_answers.commit_failed  student_id=%s", student_id, exc_info=True
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={"error": "db_error", "message": "Failed to save answers. Please retry."},
        )

    log.info(
        "sync_answers.done  student_id=%s  synced=%d  skipped=%d",
        student_id, synced, skipped,
    )
    return SyncResponse(synced=synced, skipped=skipped)


# ── GET /progress/{student_id} ────────────────────────────────────────

@router.get("/progress/{student_id}", response_model=ProgressResponse, tags=["progress"])
async def get_progress(
    student_id: str,
    db: AsyncSession = Depends(get_db),
    current_student: Student = Depends(get_current_student),
):
    """
    Return a weekly accuracy breakdown by topic for the student.
    The iOS parent dashboard and student progress charts call this endpoint.
    """
    # ── Authorisation ────────────────────────────────────────────────
    if str(current_student.id) != student_id:
        log.warning(
            "progress.forbidden  requester=%s  target=%s",
            current_student.id, student_id,
        )
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"error": "forbidden", "message": "You can only view your own progress."},
        )

    week_end = date.today()
    week_start = week_end - timedelta(days=6)
    since = datetime.combine(week_start, datetime.min.time()).replace(tzinfo=timezone.utc)

    log.info(
        "progress.get  student_id=%s  from=%s  to=%s",
        student_id, week_start, week_end,
    )

    try:
        result = await db.execute(
            select(QuizAnswer).where(
                QuizAnswer.student_id == current_student.id,
                QuizAnswer.answered_at >= since,
            )
        )
        answers = result.scalars().all()
    except Exception:
        log.error(
            "progress.get.db_error  student_id=%s", student_id, exc_info=True
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={"error": "db_unavailable", "message": "Database temporarily unavailable."},
        )

    # ── Aggregate by topic ───────────────────────────────────────────
    topic_stats: dict[str, dict[str, Any]] = defaultdict(
        lambda: {"total": 0, "correct": 0, "subject": None}
    )
    total_q = 0
    total_correct = 0

    for a in answers:
        total_q += 1
        if a.is_correct:
            total_correct += 1
        key = a.topic or "Uncategorised"
        topic_stats[key]["total"] += 1
        if a.is_correct:
            topic_stats[key]["correct"] += 1
        if a.subject:
            topic_stats[key]["subject"] = a.subject

    topic_list: list[TopicAccuracy] = []
    weak_topics: list[str] = []
    for topic, stats in sorted(topic_stats.items(), key=lambda x: x[1]["total"], reverse=True):
        acc = (stats["correct"] / stats["total"] * 100) if stats["total"] else 0.0
        topic_list.append(TopicAccuracy(
            topic=topic,
            subject=stats["subject"],
            total=stats["total"],
            correct=stats["correct"],
            accuracy_pct=round(acc, 1),
        ))
        if acc < 50.0 and topic != "Uncategorised":
            weak_topics.append(topic)

    overall_acc = (total_correct / total_q * 100) if total_q else 0.0

    log.info(
        "progress.get.ok  student_id=%s  total=%d  topics=%d  weak=%d",
        student_id, total_q, len(topic_list), len(weak_topics),
    )
    return ProgressResponse(
        student_id=student_id,
        week_start=week_start,
        week_end=week_end,
        total_questions=total_q,
        correct_questions=total_correct,
        overall_accuracy_pct=round(overall_acc, 1),
        topics=topic_list,
        weak_topics=weak_topics,
    )
