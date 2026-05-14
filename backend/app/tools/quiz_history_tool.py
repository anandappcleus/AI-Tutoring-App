"""
Quiz History Tool — retrieves a student's recent quiz answers from PostgreSQL.

Used by:
    Diagnostic Agent — analyse accuracy by topic over the last N days.
"""

from __future__ import annotations

import json
import logging
import uuid
from datetime import datetime, timedelta, timezone

from crewai.tools import BaseTool
from pydantic import BaseModel, Field
from sqlalchemy import select

from app.database import ToolSessionFactory
from app.models.student import QuizAnswer
from app.tools.db_sync import run_async

log = logging.getLogger(__name__)


class QuizHistoryInput(BaseModel):
    student_id: str = Field(
        ...,
        description="UUID of the student whose quiz history to retrieve.",
    )
    days: int = Field(
        7,
        ge=1,
        le=30,
        description="Number of past days to include (default 7, max 30).",
    )


class QuizHistoryTool(BaseTool):
    """Retrieve a student's quiz answer history from the last N days."""

    name: str = "Quiz History Tool"
    description: str = (
        "Fetch a student's quiz answer history from the database. "
        "Returns a JSON list of answers with topic, subject, is_correct, and date. "
        "Use this to identify which topics the student is struggling with."
    )
    args_schema: type[BaseModel] = QuizHistoryInput

    def _run(self, student_id: str, days: int = 7) -> str:
        log.info("quiz_history_tool  student_id=%s  days=%d", student_id, days)
        return run_async(self._fetch(student_id, days))

    async def _fetch(self, student_id: str, days: int) -> str:
        since = datetime.now(tz=timezone.utc) - timedelta(days=days)
        try:
            student_uuid = uuid.UUID(student_id)
        except ValueError:
            raise ValueError(f"Invalid student_id '{student_id}': must be a UUID.")

        try:
            async with ToolSessionFactory() as session:
                result = await session.execute(
                    select(QuizAnswer)
                    .where(
                        QuizAnswer.student_id == student_uuid,
                        QuizAnswer.answered_at >= since,
                    )
                    .order_by(QuizAnswer.answered_at.desc())
                )
                answers = result.scalars().all()
        except Exception:
            log.error(
                "quiz_history_tool.fetch failed  student_id=%s", student_id, exc_info=True
            )
            raise

        records = [
            {
                "question": a.question[:200],  # truncate long questions for LLM context
                "topic": a.topic,
                "subject": a.subject,
                "is_correct": a.is_correct,
                "answered_at": a.answered_at.date().isoformat(),
            }
            for a in answers
        ]
        log.info(
            "quiz_history_tool  student_id=%s  records=%d", student_id, len(records)
        )
        return json.dumps(records, ensure_ascii=False)


quiz_history_tool = QuizHistoryTool()
