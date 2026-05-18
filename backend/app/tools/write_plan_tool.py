"""
Write Plan Tool — upsert a student's daily study plan into PostgreSQL.

Used by:
    Curriculum Planner Agent — persist the generated study schedule.
"""

from __future__ import annotations

import json
import logging
import uuid
from datetime import date

from crewai.tools import BaseTool
from pydantic import BaseModel, Field
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.database import new_tool_session
from app.models.student import StudyPlan
from app.tools.db_sync import run_async

log = logging.getLogger(__name__)


class TopicSlot(BaseModel):
    topic: str = Field(..., description="Topic or chapter name (e.g. 'Newton's Laws').")
    duration_min: int = Field(
        ..., ge=10, le=240, description="Recommended study time in minutes."
    )
    priority: int = Field(
        ..., ge=1, le=5, description="Priority rank: 1 = highest, 5 = lowest."
    )


class WritePlanInput(BaseModel):
    student_id: str = Field(..., description="UUID of the student.")
    plan_date: str = Field(
        ..., description="Date for the study plan in YYYY-MM-DD format."
    )
    topics: list[TopicSlot] = Field(
        ...,
        min_length=1,
        description="Ordered list of topic slots for the day.",
    )


class WritePlanTool(BaseTool):
    """Insert or update a student's daily study plan in the database."""

    name: str = "Write Plan Tool"
    description: str = (
        "Upsert (insert or replace) a student's daily study plan. "
        "Provide student_id, plan_date (YYYY-MM-DD), and a list of topic slots "
        "each with topic name, duration_min, and priority (1 = highest)."
    )
    args_schema: type[BaseModel] = WritePlanInput

    def _run(
        self,
        student_id: str,
        plan_date: str,
        topics: list[dict],
    ) -> str:
        log.info(
            "write_plan_tool  student_id=%s  date=%s  topics=%d",
            student_id,
            plan_date,
            len(topics),
        )
        return run_async(self._upsert(student_id, plan_date, topics))

    async def _upsert(
        self, student_id: str, plan_date: str, topics: list[dict]
    ) -> str:
        try:
            student_uuid = uuid.UUID(student_id)
        except ValueError:
            raise ValueError(f"Invalid student_id '{student_id}': must be a UUID.")

        try:
            parsed_date = date.fromisoformat(plan_date)
        except ValueError:
            raise ValueError(f"Invalid plan_date '{plan_date}': expected YYYY-MM-DD.")

        # Normalise topics: accept TopicSlot objects or plain dicts
        normalised = [
            t.model_dump() if hasattr(t, "model_dump") else dict(t)
            for t in topics
        ]

        try:
            async with new_tool_session() as session:
                async with session.begin():
                    stmt = (
                        pg_insert(StudyPlan)
                        .values(
                            student_id=student_uuid,
                            plan_date=parsed_date,
                            plan_json=normalised,
                        )
                        .on_conflict_do_update(
                            constraint="uq_study_plan_student_date",
                            set_={"plan_json": normalised},
                        )
                    )
                    await session.execute(stmt)
        except Exception:
            log.error(
                "write_plan_tool.upsert failed  student_id=%s  date=%s",
                student_id,
                plan_date,
                exc_info=True,
            )
            raise

        log.info(
            "write_plan_tool  upserted  student_id=%s  date=%s  topics=%d",
            student_id,
            plan_date,
            len(normalised),
        )
        return json.dumps(
            {"status": "ok", "student_id": student_id, "plan_date": plan_date},
            ensure_ascii=False,
        )


write_plan_tool = WritePlanTool()
