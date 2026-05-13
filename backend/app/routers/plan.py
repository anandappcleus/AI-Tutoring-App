"""
Plan router — read today's (or a requested date's) study plan.

Endpoints:
    GET /plan/{student_id}               Today's study plan for a student
    GET /plan/{student_id}?date=YYYY-MM-DD  Study plan for a specific date

Auth:
    Students can only read their own plan (student_id in path must match JWT).
    This prevents horizontal privilege escalation without a separate admin role.

Logging:
    - plan_date logged on every request
    - Explicit logging when no plan exists (helps the planner crew debug)
    - DB errors logged at ERROR with exc_info
"""

from __future__ import annotations

import logging
from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.student import Student, StudyPlan
from app.routers.auth import get_current_student

log = logging.getLogger(__name__)
router = APIRouter()


# ── Pydantic schemas ──────────────────────────────────────────────────

class TopicSlotResponse(BaseModel):
    topic: str
    duration_min: int
    priority: int


class StudyPlanResponse(BaseModel):
    student_id: str
    plan_date: date
    topics: list[TopicSlotResponse]
    created_at: str


# ── Endpoint ──────────────────────────────────────────────────────────

@router.get("/plan/{student_id}", response_model=StudyPlanResponse, tags=["plan"])
async def get_plan(
    student_id: str,
    plan_date: date = Query(default_factory=date.today, description="Plan date (defaults to today)."),
    db: AsyncSession = Depends(get_db),
    current_student: Student = Depends(get_current_student),
):
    """
    Return the study plan for a student on a given date.
    Returns 404 if no plan has been generated yet for that date.
    """
    # ── Authorisation: students may only read their own plans ────────
    if str(current_student.id) != student_id:
        log.warning(
            "plan.forbidden  requester=%s  target=%s",
            current_student.id, student_id,
        )
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "error": "forbidden",
                "message": "You can only access your own study plan.",
            },
        )

    log.info(
        "plan.get  student_id=%s  date=%s", student_id, plan_date.isoformat()
    )

    try:
        result = await db.execute(
            select(StudyPlan).where(
                StudyPlan.student_id == current_student.id,
                StudyPlan.plan_date == plan_date,
            )
        )
        plan = result.scalar_one_or_none()
    except Exception:
        log.error(
            "plan.get.db_error  student_id=%s  date=%s",
            student_id, plan_date, exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={"error": "db_unavailable", "message": "Database temporarily unavailable."},
        )

    if plan is None:
        log.info(
            "plan.not_found  student_id=%s  date=%s  "
            "(nightly crew may not have run yet for this date)",
            student_id, plan_date,
        )
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "error": "plan_not_found",
                "message": (
                    f"No study plan found for {plan_date.isoformat()}. "
                    "Plans are generated nightly at 2 AM IST."
                ),
            },
        )

    log.info(
        "plan.get.ok  student_id=%s  date=%s  topics=%d",
        student_id, plan_date, len(plan.plan_json),
    )
    return StudyPlanResponse(
        student_id=student_id,
        plan_date=plan.plan_date,
        topics=[TopicSlotResponse(**t) for t in plan.plan_json if isinstance(t, dict)],
        created_at=plan.created_at.isoformat(),
    )
