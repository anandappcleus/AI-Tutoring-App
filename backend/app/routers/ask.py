"""
Ask router — student question answering via the Question Generator Agent.

Endpoint:
    POST /ask    Receive a student question, run the QuestionCrew, return JSON answer.

Design notes:
    - Auth required: get_current_student() validates the JWT and loads the student.
    - The student's preferred_language is automatically applied unless the caller
      overrides it with the optional `language` field.
    - CrewAI runs synchronously inside a thread pool executor so it doesn't block
      the asyncio event loop during the (slow) LLM inference step.
    - The raw crew output is always returned — parsing is best-effort; if the LLM
      returned non-JSON the raw string is preserved in `raw_output` so the iOS
      client can still display something.
    - Freemium gate: non-premium students are limited to FREE_DAILY_LIMIT questions
      per UTC day, tracked via a COUNT query on quiz_answers.

Logging:
    - Request logged with student_id, language, question length.
    - Crew start/finish times and latency logged at INFO.
    - Parse errors logged at WARNING (non-fatal — raw output still returned).
    - Rate limit hits logged at INFO so we can track conversion pressure.
    - All unexpected errors logged at ERROR with exc_info.
"""

from __future__ import annotations

import asyncio
import json
import logging
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.student import QuizAnswer, Student
from app.routers.auth import get_current_student

log = logging.getLogger(__name__)
router = APIRouter()

FREE_DAILY_LIMIT = 10           # free-tier questions per UTC day
_executor = ThreadPoolExecutor(max_workers=4, thread_name_prefix="crewai")


# ── Pydantic schemas ──────────────────────────────────────────────────

class AskRequest(BaseModel):
    question: str = Field(..., min_length=3, max_length=2000)
    language: str | None = Field(
        None,
        pattern=r"^(bn|hi|ta|te|mr|gu|kn|ml|or|pa|en)$",
        description="Override preferred language for this question. Defaults to student profile.",
    )


class PracticeProblem(BaseModel):
    question: str
    answer: str


class AskResponse(BaseModel):
    explanation: str
    worked_example: str
    practice_problems: list[PracticeProblem]
    language: str
    raw_output: str | None = None  # populated when LLM returns non-JSON


# ── Helpers ───────────────────────────────────────────────────────────

async def _check_daily_limit(student: Student, db: AsyncSession) -> None:
    """Raise 429 if a free-tier student has hit their daily question cap."""
    if student.is_premium:
        return

    today_start = datetime.combine(date.today(), datetime.min.time()).replace(
        tzinfo=timezone.utc
    )
    result = await db.execute(
        select(func.count())
        .select_from(QuizAnswer)
        .where(
            QuizAnswer.student_id == student.id,
            QuizAnswer.answered_at >= today_start,
        )
    )
    count = result.scalar_one()
    if count >= FREE_DAILY_LIMIT:
        log.info(
            "ask.rate_limit  student_id=%s  daily_count=%d  limit=%d",
            student.id, count, FREE_DAILY_LIMIT,
        )
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail={
                "error": "daily_limit_reached",
                "message": f"Free plan allows {FREE_DAILY_LIMIT} questions per day. Upgrade to continue.",
                "limit": FREE_DAILY_LIMIT,
                "used": count,
            },
        )


def _escape_latex_backslashes(text: str) -> str:
    """
    Walk through a JSON document character-by-character.
    Inside string values, double-escape any backslash that is not part of a
    valid 2-char JSON escape sequence (\\\\, \\", \\/, \\b, \\f, \\n, \\r, \\t)
    or a \\\\uNNNN Unicode escape.

    This preserves intentional JSON whitespace escapes (\\\\n, \\\\t ...) while
    fixing invalid LaTeX sequences like \\(, \\int, \\frac so they survive
    json.loads and arrive in the parsed dict as the literal characters \\(, \\int.
    """
    out = []
    in_str = False
    i = 0
    while i < len(text):
        ch = text[i]
        if not in_str:
            out.append(ch)
            if ch == '"':
                in_str = True
            i += 1
        else:
            if ch == '\\':
                nxt = text[i + 1] if i + 1 < len(text) else ""
                if nxt in ('"', '\\', '/', 'n', 'r', 't'):
                    out.append(ch)
                    out.append(nxt)
                    i += 2
                elif nxt == 'u' and i + 5 < len(text) and all(
                    c in '0123456789abcdefABCDEF' for c in text[i + 2: i + 6]
                ):
                    out.append(text[i: i + 6])
                    i += 6
                else:
                    # Invalid JSON escape — double the backslash
                    out.append('\\\\')
                    i += 1  # process nxt on the next iteration
            elif ch == '"':
                in_str = False
                out.append(ch)
                i += 1
            else:
                out.append(ch)
                i += 1
    return "".join(out)


def _parse_crew_output(raw: str) -> dict:
    """
    Best-effort parse of the crew's raw string output into a dict.

    Pre-pass — strip <think>...</think> reasoning blocks emitted by thinking
               models (sarvam-m, Qwen3, etc.). Everything before the last
               </think> tag is discarded; only the actual answer is parsed.
    Pass 1   — strip markdown code fences (```json ... ```) then parse.
    Pass 2   — fix invalid JSON escape sequences that the LLM emits for LaTeX
               (\\(, \\int, \\frac, \\pi …) by doubling backslashes that aren't
               part of a valid JSON escape sequence.
    """
    text = raw.strip()

    # Pre-pass: strip <think>...</think> reasoning blocks
    end_tag = "</think>"
    end_pos = text.rfind(end_tag)
    if end_pos != -1:
        text = text[end_pos + len(end_tag):].strip()

    # Strip ```json ... ``` or ``` ... ``` fences
    if text.startswith("```"):
        lines = text.splitlines()
        text = "\n".join(
            l for l in lines if not l.strip().startswith("```")
        ).strip()

    # Pass 1: standard JSON parse
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass

    # Pass 2: fix LaTeX backslash escapes inside string values
    try:
        return json.loads(_escape_latex_backslashes(text))
    except (json.JSONDecodeError, Exception):
        return {}


# ── Endpoint ──────────────────────────────────────────────────────────

@router.post("/ask", response_model=AskResponse, tags=["ask"])
async def ask(
    body: AskRequest,
    db: AsyncSession = Depends(get_db),
    current_student: Student = Depends(get_current_student),
):
    """
    Answer a student's question in their preferred language.

    Runs the QuestionCrew (RAG search + Sarvam-M/GPT-4o mini) in a thread pool
    so the async event loop stays free during LLM inference (~2–5 s).
    """
    lang = body.language or current_student.preferred_language
    student_id = str(current_student.id)

    log.info(
        "ask.start  student_id=%s  lang=%s  q_len=%d",
        student_id, lang, len(body.question),
    )

    # ── Freemium gate ────────────────────────────────────────────────
    await _check_daily_limit(current_student, db)

    # ── Run crew in thread pool (blocks; must not run on event loop) ─
    t0 = time.perf_counter()
    try:
        loop = asyncio.get_running_loop()
        raw_output: str = await loop.run_in_executor(
            _executor,
            _run_crew_sync,
            body.question,
            student_id,
            lang,
        )
    except Exception:
        log.error(
            "ask.crew_failed  student_id=%s  lang=%s", student_id, lang, exc_info=True
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={
                "error": "agent_unavailable",
                "message": "AI agent is temporarily unavailable. Please try again in a moment.",
            },
        )

    elapsed_ms = (time.perf_counter() - t0) * 1_000
    log.info(
        "ask.crew_done  student_id=%s  lang=%s  %.0fms",
        student_id, lang, elapsed_ms,
    )

    # ── Parse crew output ────────────────────────────────────────────
    parsed = _parse_crew_output(raw_output)
    if not parsed:
        log.warning(
            "ask.parse_failed  student_id=%s  raw_len=%d  raw_preview=%r",
            student_id, len(raw_output), raw_output[:120],
        )

    # ── Persist to quiz_answers for rate-limiting + progress tracking ─
    answer_record = QuizAnswer(
        student_id=current_student.id,
        question=body.question[:1000],  # cap at column limit
        topic=parsed.get("topic"),
        subject=parsed.get("subject"),
        is_correct=True,  # open-ended questions are not graded; treated as "attempted"
        synced=True,
    )
    db.add(answer_record)
    try:
        await db.commit()
    except Exception:
        # Non-fatal: answer tracking failure must not break the response
        log.error(
            "ask.answer_save_failed  student_id=%s", student_id, exc_info=True
        )
        await db.rollback()

    # ── Build response ───────────────────────────────────────────────
    return AskResponse(
        explanation=parsed.get("explanation", raw_output),
        worked_example=parsed.get("worked_example", ""),
        practice_problems=[
            PracticeProblem(**p)
            for p in parsed.get("practice_problems", [])
            if isinstance(p, dict) and "question" in p and "answer" in p
        ],
        language=lang,
        raw_output=raw_output if not parsed else None,
    )


def _run_crew_sync(question: str, student_id: str, lang: str) -> str:
    """Synchronous wrapper around QuestionCrew — runs in a thread pool."""
    from app.agents.crew import QuestionCrew
    return QuestionCrew().run(question=question, student_id=student_id, language=lang)
