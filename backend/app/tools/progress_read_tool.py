"""
Progress Read Tool — detect topic plateaus from a student's quiz history.

A plateau is declared when a student's accuracy on a topic falls below
_WEAK_THRESHOLD (40%) for _PLATEAU_DAYS (3) or more consecutive days.

Used by:
    Progress Monitor Agent — decide which students need a WhatsApp alert.
"""

from __future__ import annotations

import json
import logging
import uuid
from collections import defaultdict
from datetime import datetime, date, timedelta, timezone

from crewai.tools import BaseTool
from pydantic import BaseModel, Field
from sqlalchemy import select

from app.database import AsyncSessionFactory
from app.models.progress import PlateauFlag
from app.models.student import QuizAnswer
from app.tools.db_sync import run_async

log = logging.getLogger(__name__)

_WEAK_THRESHOLD = 40.0  # accuracy % below which a session is "weak"
_PLATEAU_DAYS = 3       # consecutive weak days needed to declare a plateau


class ProgressReadInput(BaseModel):
    student_id: str = Field(..., description="UUID of the student.")
    days: int = Field(
        7,
        ge=3,
        le=30,
        description="Number of past days to scan for plateaus (min 3, default 7).",
    )


def detect_plateaus(
    answers: list,
    weak_threshold: float = _WEAK_THRESHOLD,
    plateau_days: int = _PLATEAU_DAYS,
) -> list[dict]:
    """
    Pure-Python plateau detection — no DB access.
    Extracted so it can be unit-tested independently.

    Args:
        answers: iterable of objects with .topic, .is_correct, .answered_at
        weak_threshold: accuracy % below which a day is "weak"
        plateau_days: minimum consecutive weak days to flag as a plateau

    Returns:
        List of {"topic": str, "consecutive_weak_days": int}
    """
    # Build (topic, date) → {correct, total}
    by_topic_day: dict[str, dict[date, dict]] = defaultdict(dict)
    for a in answers:
        if not a.topic:
            continue
        d = a.answered_at.date() if hasattr(a.answered_at, "date") else a.answered_at
        bucket = by_topic_day[a.topic].setdefault(d, {"correct": 0, "total": 0})
        bucket["total"] += 1
        if a.is_correct:
            bucket["correct"] += 1

    plateaus: list[dict] = []
    for topic, daily in by_topic_day.items():
        streak = 0
        max_streak = 0
        for d in sorted(daily):
            acc = daily[d]["correct"] / daily[d]["total"] * 100
            if acc < weak_threshold:
                streak += 1
                max_streak = max(max_streak, streak)
            else:
                streak = 0
        if max_streak >= plateau_days:
            plateaus.append({"topic": topic, "consecutive_weak_days": max_streak})
    return plateaus


class ProgressReadTool(BaseTool):
    """
    Detect topic plateaus from quiz history and record them as plateau_flags.

    Returns a JSON list of {topic, consecutive_weak_days} for any topic where
    the student has been below 40% accuracy for 3 or more consecutive days.
    """

    name: str = "Progress Read Tool"
    description: str = (
        "Analyse a student's quiz accuracy over the past N days per topic. "
        "Returns topics where accuracy has been below 40% for 3 or more "
        "consecutive days (plateau). Also writes plateau_flag records to the database."
    )
    args_schema: type[BaseModel] = ProgressReadInput

    def _run(self, student_id: str, days: int = 7) -> str:
        log.info("progress_read_tool  student_id=%s  days=%d", student_id, days)
        return run_async(self._detect(student_id, days))

    async def _detect(self, student_id: str, days: int) -> str:
        try:
            student_uuid = uuid.UUID(student_id)
        except ValueError:
            raise ValueError(f"Invalid student_id '{student_id}': must be a UUID.")

        since = datetime.now(tz=timezone.utc) - timedelta(days=days)

        async with AsyncSessionFactory() as session:
            # ── Fetch quiz history ──────────────────────────────────
            try:
                result = await session.execute(
                    select(QuizAnswer)
                    .where(
                        QuizAnswer.student_id == student_uuid,
                        QuizAnswer.answered_at >= since,
                        QuizAnswer.topic.isnot(None),
                    )
                    .order_by(QuizAnswer.answered_at)
                )
                answers = result.scalars().all()
            except Exception:
                log.error(
                    "progress_read_tool.fetch failed  student_id=%s",
                    student_id,
                    exc_info=True,
                )
                raise

            # ── Detect plateaus ─────────────────────────────────────
            plateaus = detect_plateaus(answers)

            # ── Persist plateau_flags (one per unsent topic) ────────
            if plateaus:
                try:
                    async with session.begin():
                        for p in plateaus:
                            # Only insert if no un-sent flag already exists
                            existing = await session.execute(
                                select(PlateauFlag).where(
                                    PlateauFlag.student_id == student_uuid,
                                    PlateauFlag.topic == p["topic"],
                                    PlateauFlag.alert_sent.is_(False),
                                )
                            )
                            if not existing.scalar():
                                session.add(
                                    PlateauFlag(
                                        student_id=student_uuid,
                                        topic=p["topic"],
                                        consecutive_weak_days=p["consecutive_weak_days"],
                                    )
                                )
                except Exception:
                    log.error(
                        "progress_read_tool.flag_write failed  student_id=%s",
                        student_id,
                        exc_info=True,
                    )
                    # Non-fatal: detection result is still returned below

        log.info(
            "progress_read_tool  student_id=%s  plateaus=%d",
            student_id,
            len(plateaus),
        )
        return json.dumps(plateaus, ensure_ascii=False)


progress_read_tool = ProgressReadTool()
