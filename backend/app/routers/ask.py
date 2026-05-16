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
from datetime import date, datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import Integer, cast, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from litellm import acompletion

from app.config import get_settings
from app.database import get_db
from app.models.student import QuizAnswer, Student, StudyPlan
from app.routers.auth import get_current_student

log = logging.getLogger(__name__)
router = APIRouter()

FREE_DAILY_LIMIT = 50           # free-tier questions per UTC day (raised for testing)
_executor = ThreadPoolExecutor(max_workers=4, thread_name_prefix="crewai")
_VISION_MODEL = "meta/llama-3.2-11b-vision-instruct"


# ── Pydantic schemas ──────────────────────────────────────────────────

class AskRequest(BaseModel):
    question: str = Field(..., min_length=3, max_length=2000)
    language: str | None = Field(
        None,
        pattern=r"^(bn|hi|ta|te|mr|gu|kn|ml|or|pa|en)$",
        description="Override preferred language for this question. Defaults to student profile.",
    )
    exam_type: str | None = Field(
        None,
        pattern=r"^(JEE|NEET|WBCHSE)$",
        description="Student's exam target — used to frame practice problems in the right style.",
    )
    image_b64: str | None = Field(
        None,
        max_length=4_000_000,   # ~3 MB raw image — generous limit
        description="JPEG image as base64 string. When present, the 11B vision model extracts math text.",
    )


class PracticeProblem(BaseModel):
    question: str
    answer: str
    question_type: str | None = None   # MCQ | Integer | Short Answer | Long Answer
    marks: int | None = None
    marking_scheme: str | None = None  # e.g. "+4/-1", "+4/0", "no negative marking"


class AskResponse(BaseModel):
    explanation: str
    worked_example: str
    practice_problems: list[PracticeProblem]
    language: str
    question_type: str | None = None   # top-level question type for the whole answer
    marks: int | None = None
    marking_scheme: str | None = None
    raw_output: str | None = None  # populated when LLM returns non-JSON


# ── Helpers ───────────────────────────────────────────────────────────

async def _extract_image_content(image_b64: str) -> str:
    """
    Use llama-3.2-11b-vision-instruct (NIM) to analyse the attached image.

    Returns:
      - "NOT_EDUCATIONAL" (exact string) if the image is not a textbook problem.
      - Extracted math/text content preserving fractions (e.g. H/2, not "H 2")
        for any educational image.

    The returned text is appended to the student's question before handing off
    to the 70B reasoning crew.
    """
    s = get_settings()
    response = await asyncio.wait_for(
        acompletion(
            model=f"openai/{_VISION_MODEL}",
            api_base=s.LLM_BASE_URL,
            api_key=s.LLM_API_KEY,
            messages=[{
                "role": "user",
                "content": [
                    {
                        "type": "image_url",
                        "image_url": {"url": f"data:image/jpeg;base64,{image_b64}"},
                    },
                    {
                        "type": "text",
                        "text": (
                            "You are helping a JEE/NEET student with their studies.\n"
                            "Examine this image carefully:\n"
                            "1. If it shows a textbook/exam question, equation, formula, "
                            "diagram, or graph: extract ALL text exactly with these rules:\n"
                            "   - Fractions: write H/2 not 'H 2', use '/' for all fraction bars.\n"
                            "   - Superscripts/exponents: write EXACTLY what is shown. "
                            "If the exponent is 'ln 2' write '^(ln 2)', if it is '2' write '^2'. "
                            "NEVER convert 'ln 2' to '1/2' or 'ln 3' to '1/3' — they are different.\n"
                            "   - Subscripts: write log_2(x) for log base 2 of x.\n"
                            "   - Nested radicals: preserve all sqrt() nesting explicitly.\n"
                            "   - If multiple questions are present (e.g., 1. 2. 3.), "
                            "extract all of them with their original numbering and all answer options.\n"
                            "Output ONLY the extracted text — nothing else.\n"
                            "2. If it is NOT educational content (selfie, food, landscape, "
                            "random photo, meme, screenshot of a chat): "
                            "output exactly: NOT_EDUCATIONAL\n"
                            "No explanations, no preamble — only the extracted text or "
                            "NOT_EDUCATIONAL."
                        ),
                    },
                ],
            }],
            max_tokens=350,
        ),
        timeout=25.0,   # hard wall-clock deadline — litellm's timeout= param is ignored by NIM
    )
    return response.choices[0].message.content.strip()


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


def _fix_control_chars_in_strings(text: str) -> str:
    """
    Replace literal control characters that appear INSIDE JSON string values
    with their JSON escape sequences.

    json.loads() rejects raw \\n / \\r / \\t inside a string literal — they must
    be written as the two-character sequences \\\\n etc.  Thinking models like
    sarvam-m frequently emit multi-line explanations with real newlines.
    """
    result: list[str] = []
    in_string = False
    escaped = False
    for c in text:
        if escaped:
            result.append(c)
            escaped = False
        elif c == "\\" and in_string:
            result.append(c)
            escaped = True
        elif c == '"':
            result.append(c)
            in_string = not in_string
        elif in_string and c == "\n":
            result.append("\\n")
        elif in_string and c == "\r":
            result.append("\\r")
        elif in_string and c == "\t":
            result.append("\\t")
        else:
            result.append(c)
    return "".join(result)


def _extract_last_json_object(text: str) -> str | None:
    """
    Walk *text* character-by-character tracking brace depth.

    Returns the LAST complete top-level {...} block found.  Correctly ignores
    braces that appear inside JSON string values AND inside the agent's ReAct
    thought trace (e.g. Action Input: {"query": "..."}).
    """
    best: str | None = None
    depth = 0
    start = -1
    in_string = False
    escaped = False

    for i, c in enumerate(text):
        if escaped:
            escaped = False
            continue
        if c == "\\" and in_string:
            escaped = True
            continue
        if c == '"':
            in_string = not in_string
            continue
        if in_string:
            continue
        if c == "{":
            if depth == 0:
                start = i
            depth += 1
        elif c == "}" and depth > 0:
            depth -= 1
            if depth == 0 and start != -1:
                best = text[start : i + 1]  # keep overwriting → last wins
                start = -1

    return best


def _parse_crew_output(raw: str) -> dict:
    """
    Best-effort parse of the crew's raw string output into a dict.

    Pre-pass — strip <think>...</think> reasoning blocks emitted by thinking
               models (sarvam-m, Qwen3, etc.). Everything before the last
               </think> tag is discarded; only the actual answer is parsed.
    Pass 0   — use _extract_last_json_object() to find the final top-level
               JSON object even when the model omits <think> tags or appends
               trailing text / ReAct traces that contain their own { } pairs.
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

    # Pass 0: extract the LAST complete JSON object — handles ReAct traces
    # where the thinking text contains its own { } pairs (tool inputs, etc.)
    extracted = _extract_last_json_object(text)
    if extracted:
        text = extracted

    # Pass 1: standard JSON parse
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass

    # Pass 2: fix LaTeX backslash escapes inside string values
    try:
        return json.loads(_escape_latex_backslashes(text))
    except (json.JSONDecodeError, Exception):
        pass

    # Pass 3: fix literal control characters (newlines, tabs) inside string values.
    # Thinking models like sarvam-m frequently write real newline chars in JSON strings.
    try:
        return json.loads(_fix_control_chars_in_strings(text))
    except (json.JSONDecodeError, Exception):
        pass

    # Pass 4: fix both control chars AND LaTeX escapes
    try:
        return json.loads(_escape_latex_backslashes(_fix_control_chars_in_strings(text)))
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

    # ── Fetch student's weak topics for personalised context ────────
    weak_topics = await _get_weak_topics(current_student.id, db)
    log.info(
        "ask.weak_topics  student_id=%s  topics=%s",
        student_id, weak_topics or "none",
    )

    # ── RAG pre-fetch: start immediately, runs concurrently with vision ─
    from app.tools.rag_search_tool import rag_search_tool as _rst
    _loop = asyncio.get_running_loop()
    _rag_future = _loop.run_in_executor(_executor, _rst._run, body.question, 3)

    # ── Vision pipeline: image extraction / validation ───────────────
    effective_question = body.question
    if body.image_b64:
        log.info("ask.vision_start  student_id=%s", student_id)
        try:
            extracted = await _extract_image_content(body.image_b64)
        except Exception:
            log.error(
                "ask.vision_failed  student_id=%s", student_id, exc_info=True
            )
            extracted = ""  # degrade gracefully — proceed without image text

        if extracted == "NOT_EDUCATIONAL":
            log.info("ask.vision_irrelevant  student_id=%s", student_id)
            return AskResponse(
                explanation=(
                    "I can see your image, but it doesn't look like a textbook question, "
                    "equation, or diagram. Please send a photo of a maths or science problem "
                    "you need help with, and I'll solve it step by step!"
                ),
                worked_example="",
                practice_problems=[],
                language=lang,
            )
        elif extracted:
            log.info(
                "ask.vision_extracted  student_id=%s  chars=%d",
                student_id, len(extracted),
            )
            effective_question = f"{body.question}\n\n[Image content: {extracted}]"

    # ── Collect pre-fetched RAG chunks (should be ready by now) ──────
    try:
        pre_chunks: list[dict] = await asyncio.wait_for(
            asyncio.shield(_rag_future), timeout=8.0
        )
    except Exception:
        log.warning("ask.rag_prefetch_failed  student_id=%s", student_id, exc_info=True)
        pre_chunks = []

    # ── Direct RAG + single LLM call (3-4× faster than CrewAI ReAct loop) ────
    t0 = time.perf_counter()
    try:
        raw_output: str = await _ask_direct(
            effective_question,
            student_id,
            lang,
            weak_topics,
            body.exam_type,
            pre_chunks=pre_chunks,
        )
    except Exception:
        log.error(
            "ask.direct_failed  student_id=%s  lang=%s", student_id, lang, exc_info=True
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
        "ask.direct_done  student_id=%s  lang=%s  %.0fms",
        student_id, lang, elapsed_ms,
    )

    # ── Parse crew output ────────────────────────────────────────────
    parsed = _parse_crew_output(raw_output)
    if not parsed:
        extracted_preview = ""
        json_err = ""
        try:
            _extracted = _extract_last_json_object(raw_output.strip())
            if _extracted:
                extracted_preview = _extracted[:300]
                json.loads(_fix_control_chars_in_strings(_extracted))
        except json.JSONDecodeError as e:
            json_err = str(e)
        log.warning(
            "ask.parse_failed  student_id=%s  raw_len=%d  "
            "raw_preview=%r  extracted_preview=%r  json_err=%s",
            student_id, len(raw_output), raw_output[:120],
            extracted_preview, json_err,
        )

    # ── Persist to quiz_answers for rate-limiting + progress tracking ─
    answer_record = QuizAnswer(
        student_id=current_student.id,
        question=body.question[:1000],  # cap at column limit; store original question
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
    # Fallback explanation when JSON parsing failed completely:
    # prefer text after "Final Answer:" over the raw thinking dump.
    if not parsed:
        fallback_explanation = raw_output
        for marker in ("Final Answer:", "final answer:", "FINAL ANSWER:"):
            pos = raw_output.rfind(marker)
            if pos != -1:
                fallback_explanation = raw_output[pos + len(marker):].strip()
                break
        else:
            # No JSON and no Final Answer marker — return a user-friendly message
            # so the student sees something actionable rather than raw thinking.
            if not _extract_last_json_object(raw_output):
                fallback_explanation = (
                    "Sorry, I had trouble generating a structured response for this question. "
                    "Please try rephrasing or ask a more specific question."
                )
    else:
        fallback_explanation = ""

    return AskResponse(
        explanation=parsed.get("explanation") or fallback_explanation,
        worked_example=parsed.get("worked_example", ""),
        practice_problems=[
            PracticeProblem(
                question=p["question"],
                answer=p["answer"],
                question_type=p.get("question_type"),
                marks=p.get("marks"),
                marking_scheme=p.get("marking_scheme"),
            )
            for p in parsed.get("practice_problems", [])
            if isinstance(p, dict) and "question" in p and "answer" in p
        ],
        language=lang,
        question_type=parsed.get("question_type"),
        marks=parsed.get("marks"),
        marking_scheme=parsed.get("marking_scheme"),
        raw_output=raw_output if not parsed else None,
    )


async def _get_weak_topics(student_id, db: AsyncSession) -> list[str]:
    """
    Return up to 3 weak topic names for the student.

    Priority:
      1. Today's study plan topics (the nightly crew already identified these).
      2. Fallback: topics from the last 7 days of quiz_answers where accuracy < 60%
         across at least 2 attempts.
    """
    # 1. Today's plan
    result = await db.execute(
        select(StudyPlan).where(
            StudyPlan.student_id == student_id,
            StudyPlan.plan_date == date.today(),
        )
    )
    plan = result.scalar_one_or_none()
    if plan and plan.plan_json:
        topics = [slot["topic"] for slot in plan.plan_json if "topic" in slot]
        if topics:
            return topics[:3]

    # 2. Fallback: derive from recent quiz answers
    cutoff = datetime.combine(
        date.today() - timedelta(days=7), datetime.min.time()
    ).replace(tzinfo=timezone.utc)
    rows = (await db.execute(
        select(
            QuizAnswer.topic,
            func.count().label("total"),
            func.sum(cast(QuizAnswer.is_correct, Integer)).label("correct"),
        )
        .where(
            QuizAnswer.student_id == student_id,
            QuizAnswer.answered_at >= cutoff,
            QuizAnswer.topic.isnot(None),
        )
        .group_by(QuizAnswer.topic)
        .having(func.count() >= 2)
    )).all()
    weak = [
        row.topic for row in rows
        if row.total > 0 and (row.correct or 0) / row.total < 0.60
    ]
    return weak[:3]


def _run_crew_sync(
    question: str,
    student_id: str,
    lang: str,
    weak_topics: list[str],
    exam_type: str | None = None,
) -> str:
    """Synchronous wrapper around QuestionCrew — kept for the nightly crew; no longer
    used by the /ask endpoint (replaced by _ask_direct for lower latency)."""
    from app.agents.crew import QuestionCrew
    return QuestionCrew().run(
        question=question,
        student_id=student_id,
        language=lang,
        weak_topics=weak_topics,
        exam_type=exam_type,
    )


async def _ask_direct(
    question: str,
    student_id: str,
    language: str,
    weak_topics: list[str] | None,
    exam_type: str | None,
    pre_chunks: list[dict] | None = None,   # pre-fetched concurrently with vision
) -> str:
    """
    Fast path: RAG search + single LLM call, bypassing the CrewAI ReAct loop.

    The ReAct loop makes 2-3 sequential LLM calls (plan → call RAG tool → answer).
    This function makes exactly 1, reducing latency from ~80-130 s to ~25-35 s.
    Same model, same RAG corpus, same JSON schema — output quality is unchanged.
    """
    from app.agents.crew import QuestionCrew
    from app.agents.prompts import LANGUAGE_NAMES, get_tutor_prompt
    from app.tools.rag_search_tool import rag_search_tool

    s = get_settings()

    # 1. RAG search — use pre-fetched chunks when available (saved ~1s for image
    # queries by running concurrently with the vision model); otherwise fetch now.
    loop = asyncio.get_running_loop()
    if pre_chunks is not None:
        chunks: list[dict] = pre_chunks
    else:
        chunks = await loop.run_in_executor(
            _executor, rag_search_tool._run, question, 3
        )

    # 2. Format RAG context block
    if chunks:
        rag_context = "\n\n".join(
            f"[Source: {c.get('source', 'corpus')}  score={c.get('score', 0):.2f}]\n"
            f"{c.get('text', '')}"
            for c in chunks
        )
    else:
        rag_context = "No relevant context found — answer from your own knowledge."

    # 3. Exam + weak-topic context strings (mirrors QuestionCrew._EXAM_CONTEXTS)
    exam_context_str = QuestionCrew._EXAM_CONTEXTS.get(
        exam_type or "",
        "General academic style. Use appropriate question_type (MCQ, Short Answer, etc.) "
        "and marks (2-4) for the topic.",
    )
    weak_topics_str = ", ".join(weak_topics) if weak_topics else "none identified yet"
    lang_name = LANGUAGE_NAMES.get(language, "English")

    # 4. Model routing — mirror make_question_generator_agent()
    model = s.LLM_AGENT_MODEL if language == "en" else s.LLM_CHAT_MODEL

    user_message = (
        f"A student (ID: {student_id}) has asked: {question}\n"
        f"Exam context: {exam_context_str}\n"
        f"Student's weak topics (supplementary context only): {weak_topics_str}\n"
        f"\n"
        f"CRITICAL RULE: Your response MUST address the student's EXACT question. "
        f"Do NOT pivot to a different topic because it appears in the weak topics list.\n"
        f"\n"
        f"--- RELEVANT KNOWLEDGE BASE CONTEXT ---\n"
        f"{rag_context}\n"
        f"--- END CONTEXT ---\n"
        f"\n"
        f"Steps:\n"
        f"1. Classify the question as ONE of:\n"
        f"   MCQ PROBLEM — question already has numbered/lettered answer options\n"
        f"   ACADEMIC TOPIC — concept/formula/problem WITHOUT pre-supplied options\n"
        f"   META QUERY — about an exam, course, or syllabus overview\n"
        f"2. For MCQ PROBLEM: solve step by step, evaluate EACH option explicitly, "
        f"start explanation with 'Correct Answer: Option N — value'.\n"
        f"   For ACADEMIC TOPIC: explanation + worked example + 2 practice problems.\n"
        f"   For META QUERY: concise exam overview + 1 practice problem.\n"
        f"3. Respond in {lang_name} at Class 11-12 level.\n"
        f"4. Format practice problems per the exam context above.\n"
        f'Return ONLY valid JSON: {{"explanation":"...","worked_example":"...",'
        f'"practice_problems":[{{"question":"...","answer":"...","question_type":"...",'
        f'"marks":4,"marking_scheme":"..."}}],'
        f'"topic":"...","subject":"...","question_type":"...","marks":4,"marking_scheme":"..."}}'
    )

    response = await asyncio.wait_for(
        acompletion(
            model=f"openai/{model}",
            api_base=s.LLM_BASE_URL,
            api_key=s.LLM_API_KEY,
            messages=[
                {"role": "system", "content": get_tutor_prompt(language)},
                {"role": "user",   "content": user_message},
            ],
            max_tokens=1500,
            temperature=0.1,
        ),
        timeout=60.0,   # hard wall-clock deadline — litellm's timeout= param is ignored by NIM
    )
    return response.choices[0].message.content.strip()
