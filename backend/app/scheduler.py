"""
APScheduler nightly crew job.

Schedule:
    02:00 IST (= 20:30 UTC) every night — runs the full NightlyTutorCrew for
    every active student who has answered at least one question in the last 7 days.

Design:
    - Uses AsyncIOScheduler so it integrates cleanly with FastAPI's asyncio loop.
    - The actual crew execution is synchronous (CrewAI) and is dispatched to a
      thread pool — the async runner just orchestrates student fetching and dispatch.
    - Each student's crew run is isolated: one student's failure never aborts others.
    - Overlapping runs are prevented: the job is marked misfire_grace_time=3600s
      (skip if the previous run is still in progress after 1 h).
    - All students without a registered phone number get WhatsApp skipped gracefully.

Logging:
    - Job start/finish logged at INFO with student count and elapsed time.
    - Per-student success/failure logged individually.
    - Scheduler lifecycle (start/stop) logged at INFO.
    - Any scheduler internal error logged at ERROR.
"""

from __future__ import annotations

import asyncio
import logging
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timezone

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger
from sqlalchemy import select

from app.database import AsyncSessionFactory
from app.models.student import Student

log = logging.getLogger(__name__)

_scheduler: AsyncIOScheduler | None = None
_crew_executor = ThreadPoolExecutor(max_workers=2, thread_name_prefix="nightly_crew")


# ── Public lifecycle API (called from main.py lifespan) ───────────────

def start_scheduler() -> None:
    """Start the APScheduler. Called once at FastAPI startup."""
    global _scheduler
    if _scheduler and _scheduler.running:
        log.warning("scheduler.start  already_running — skipping")
        return

    _scheduler = AsyncIOScheduler(timezone="Asia/Kolkata")
    _scheduler.add_job(
        run_nightly_crew,
        trigger=CronTrigger(hour=2, minute=0, timezone="Asia/Kolkata"),
        id="nightly_crew",
        name="Nightly diagnostic + planning + monitoring crew",
        replace_existing=True,
        misfire_grace_time=3600,  # skip if delayed > 1 h (e.g. server restart)
        coalesce=True,            # collapse missed runs into one
    )
    _scheduler.start()
    log.info(
        "scheduler.started  next_run=%s",
        _scheduler.get_job("nightly_crew").next_run_time,
    )


def stop_scheduler() -> None:
    """Stop the scheduler gracefully. Called at FastAPI shutdown."""
    global _scheduler
    if _scheduler and _scheduler.running:
        _scheduler.shutdown(wait=False)
        log.info("scheduler.stopped")
    else:
        log.debug("scheduler.stop  not_running — nothing to do")


# ── Main job ──────────────────────────────────────────────────────────

async def run_nightly_crew() -> None:
    """
    Nightly job: fetch active students with recent activity and run the
    NightlyTutorCrew for each one sequentially (to stay within NIM rate limits).
    """
    t0 = time.perf_counter()
    today = date.today()
    log.info("nightly_crew.start  date=%s", today.isoformat())

    students = await _fetch_active_students()
    if not students:
        log.info("nightly_crew.skip  reason=no_active_students")
        return

    log.info("nightly_crew.students  count=%d", len(students))

    success = 0
    failed = 0
    for student in students:
        sid = str(student.id)
        try:
            await _run_student_crew(student, today)
            success += 1
        except Exception:
            failed += 1
            log.error(
                "nightly_crew.student_failed  student_id=%s", sid, exc_info=True
            )
        # Small sleep between students to respect NIM rate limits
        await asyncio.sleep(1)

    elapsed_s = time.perf_counter() - t0
    log.info(
        "nightly_crew.done  date=%s  success=%d  failed=%d  elapsed=%.1fs",
        today.isoformat(), success, failed, elapsed_s,
    )


async def _fetch_active_students() -> list[Student]:
    """
    Return active students who have answered at least one question in the last 7 days.
    This avoids running the crew for completely dormant accounts.
    """
    from datetime import timedelta
    from app.models.student import QuizAnswer

    since = datetime.now(tz=timezone.utc) - timedelta(days=7)
    try:
        async with AsyncSessionFactory() as session:
            # Students who have recent quiz activity
            result = await session.execute(
                select(Student)
                .join(QuizAnswer, QuizAnswer.student_id == Student.id)
                .where(
                    Student.is_active.is_(True),
                    QuizAnswer.answered_at >= since,
                )
                .distinct()
            )
            return list(result.scalars().all())
    except Exception:
        log.error("nightly_crew.fetch_students_failed", exc_info=True)
        return []


async def _run_student_crew(student: Student, today: date) -> None:
    """Dispatch one student's nightly crew to the thread pool."""
    from app.agents.crew import NightlyTutorCrew

    sid = str(student.id)
    phone = getattr(student, "phone_number", "") or ""  # phone not in model yet — Sprint 6
    plan_date = today.isoformat()

    log.info(
        "nightly_crew.student_start  student_id=%s  lang=%s  date=%s",
        sid, student.preferred_language, plan_date,
    )
    t0 = time.perf_counter()
    loop = asyncio.get_running_loop()
    await loop.run_in_executor(
        _crew_executor,
        _crew_sync,
        sid, phone, plan_date, student.preferred_language,
    )
    elapsed_ms = (time.perf_counter() - t0) * 1_000
    log.info(
        "nightly_crew.student_done  student_id=%s  %.0fms", sid, elapsed_ms
    )


def _crew_sync(
    student_id: str,
    phone_number: str,
    plan_date: str,
    language: str,
) -> None:
    """Synchronous crew execution — runs in a thread pool executor."""
    NightlyTutorCrew().run(
        student_id=student_id,
        phone_number=phone_number,
        plan_date=plan_date,
        language=language,
    )
