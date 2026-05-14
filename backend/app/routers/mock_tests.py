"""
Mock Tests router — GET /mock-tests

Returns the catalog of available past-paper mock tests, optionally filtered
by exam_type query param.  The catalog is static content (no DB needed) that
matches the iOS MockTestsViewModel.MockTestResponse shape so the iOS static
fallback is no longer used.

Endpoint:
    GET /mock-tests?exam_type=JEE   (exam_type optional: JEE | NEET | WBCHSE)
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel

from app.routers.auth import get_current_student
from app.models.student import Student

log = logging.getLogger(__name__)
router = APIRouter()


# ── Pydantic schema ───────────────────────────────────────────────────

class MockTestResponse(BaseModel):
    id: str
    title: str
    exam_type: str          # JEE | NEET | WBCHSE
    subjects: str           # human-readable subject list
    year: int
    question_count: int
    duration_minutes: int
    difficulty: str         # Easy | Medium | Hard


# ── Static catalog ────────────────────────────────────────────────────
# Source of truth for the iOS app.  Add new papers here and they will be
# delivered to the iOS app on next cold-start without a client-side change.

_MOCK_TEST_CATALOG: list[MockTestResponse] = [
    # ── JEE ─────────────────────────────────────────────────────────
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
        id="neet-2024", title="NEET UG 2024",
        exam_type="NEET", subjects="Physics · Chemistry · Biology",
        year=2024, question_count=180, duration_minutes=200, difficulty="Hard",
    ),
    MockTestResponse(
        id="neet-2023", title="NEET UG 2023",
        exam_type="NEET", subjects="Physics · Chemistry · Biology",
        year=2023, question_count=180, duration_minutes=200, difficulty="Medium",
    ),
    MockTestResponse(
        id="neet-2022", title="NEET UG 2022",
        exam_type="NEET", subjects="Physics · Chemistry · Biology",
        year=2022, question_count=180, duration_minutes=200, difficulty="Medium",
    ),
    MockTestResponse(
        id="neet-2021", title="NEET UG 2021",
        exam_type="NEET", subjects="Physics · Chemistry · Biology",
        year=2021, question_count=180, duration_minutes=200, difficulty="Easy",
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


# ── Route ─────────────────────────────────────────────────────────────

@router.get("", response_model=list[MockTestResponse], summary="List mock test papers")
async def list_mock_tests(
    exam_type: str | None = Query(
        default=None,
        pattern="^(JEE|NEET|WBCHSE)$",
        description="Filter by exam type. Omit to return all papers.",
    ),
    current_student: Student = Depends(get_current_student),
) -> list[MockTestResponse]:
    """
    Return the catalog of past-paper mock tests.

    - **exam_type**: optional filter (JEE | NEET | WBCHSE).  If omitted, returns
      all papers sorted by year descending.
    - Requires a valid JWT (student must be logged in).
    """
    catalog = _MOCK_TEST_CATALOG

    if exam_type:
        catalog = [t for t in catalog if t.exam_type == exam_type]
        log.info("mock_tests.list  exam_type=%s  count=%d", exam_type, len(catalog))
    else:
        log.info("mock_tests.list  exam_type=all  count=%d", len(catalog))

    # Sort by year descending so newest papers appear first
    return sorted(catalog, key=lambda t: t.year, reverse=True)
