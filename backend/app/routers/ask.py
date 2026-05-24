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
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import Integer, cast, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from litellm import acompletion

from app.config import get_settings
from app.database import get_db
from app.models.student import QuizAnswer, Student, StudyPlan
from app.routers.auth import get_current_student
from app.services.redis_client import get_redis

log = logging.getLogger(__name__)
router = APIRouter()

# Fallback model used when the primary (large) model is queue-throttled on NIM.
# Override via LLM_FAST_MODEL env var — e.g. llama-3.1-8b-instant on Groq.
_FAST_FALLBACK_MODEL = "meta/llama-3.1-8b-instruct"  # resolved at runtime from settings

FREE_DAILY_LIMIT = 50           # free-tier questions per UTC day (raised for testing)
_executor = ThreadPoolExecutor(max_workers=4, thread_name_prefix="crewai")
_VISION_MODEL = "meta/llama-3.2-90b-vision-instruct"  # resolved at runtime from settings


# ── Pydantic schemas ──────────────────────────────────────────────────

class ConversationTurnIn(BaseModel):
    """A single prior turn sent by the iOS client for multi-turn context."""
    role: str = Field(..., pattern=r"^(user|assistant)$")
    content: str = Field(..., max_length=10_000)  # generous upper bound; trimmed below

    @field_validator("content")
    @classmethod
    def truncate_content(cls, v: str) -> str:
        """Silently truncate overlong turns rather than rejecting the request."""
        return v[:1800]


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
        description="JPEG image as base64 string. When present, the 90B vision model extracts math text.",
    )
    history: list[ConversationTurnIn] = Field(
        default_factory=list,
        max_length=10,
        description=(
            "Previous conversation turns (oldest first, newest last). "
            "Max 10 turns = 5 Q&A pairs. Used to give the LLM multi-turn context."
        ),
    )


class PracticeProblem(BaseModel):
    question: str
    answer: str
    question_type: str | None = None   # MCQ | Integer | Short Answer | Long Answer
    marks: int | None = None
    marking_scheme: str | None = None  # e.g. "+4/-1", "+4/0", "no negative marking"


class AskResponse(BaseModel):
    answer: str = ""               # MCQ option letter / numerical value / one-line answer
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
    Use llama-3.2-90b-vision-instruct (NIM) to analyse the attached image.

    Returns:
      - "NOT_EDUCATIONAL" (exact string) if the image is not a textbook problem.
      - Extracted math/text content preserving fractions (e.g. H/2, not "H 2")
        for any educational image.

    The returned text is appended to the student's question before handing off
    to the 70B reasoning crew.
    """
    s = get_settings()
    vision_model = s.LLM_VISION_MODEL
    response = await asyncio.wait_for(
        acompletion(
            model=f"openai/{vision_model}",
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
                            "Examine this image carefully.\n"
                            "1. If it shows a textbook/exam question, equation, formula, "
                            "diagram, or graph: extract ALL text EXACTLY with these rules:\n"
                            "   - Fractions: write H/2 not 'H 2', use '/' for all fraction bars.\n"
                            "   - Superscripts/exponents: write EXACTLY what is shown. "
                            "If the exponent is 'ln 2' write '^(ln 2)', if it is '2' write '^2'. "
                            "NEVER convert 'ln 2' to '1/2' or 'ln 3' to '1/3' — they are different.\n"
                            "   - CRITICAL — multi-level exponents: if a bracketed expression "
                            "like (log_2 9) has a small superscript immediately after the closing "
                            "bracket (e.g. a small '2' above-right of ')'), write it as "
                            "(log_2 9)^2. Example: ((log_2 9)^2)^(1/log_2(log_2 9)) — the outer "
                            "^2 on (log_2 9) MUST be captured before the outer exponent. "
                            "Scan every closing bracket for a superscript — do not skip any.\n"
                            "   - CRITICAL — logarithm base: the SUBSCRIPT of 'log' is the BASE. "
                            "If the subscript is a fraction like '3/2', write log_{3/2}(x). "
                            "log_{3/2} means base THREE-HALVES (1.5), NOT base 3. "
                            "A small '2' below '3' next to 'log' means base 3/2, not base 3 — "
                            "NEVER drop the denominator of a fractional base.\n"
                            "   - CRITICAL — infinite nested radicals: if you see a sqrt (radical) "
                            "containing an expression that has another sqrt of the SAME pattern "
                            "(with or without '...' dots indicating continuation), this is an "
                            "INFINITE nested radical — NOT a power/exponent. "
                            "Write it using '...' to show the infinite repetition. "
                            "Example: sqrt(4 - (1/(3*sqrt(2)))*sqrt(4 - (1/(3*sqrt(2)))*sqrt(4 - ...))). "
                            "Do NOT rewrite an infinite nested radical as a base raised to a power.\n"
                            "   - Subscripts: write log_2(x) for log base 2 of x.\n"
                            "   - Nested radicals: preserve all sqrt() nesting explicitly.\n"
                            "   - CRITICAL — MCQ answer options: if the question has labeled "
                            "answer choices (A/B/C/D, (1)/(2)/(3)/(4), or a)/b)/c)/d)), you MUST "
                            "extract EVERY option with its label and full mathematical content. "
                            "For example: 'A) 2/(2-log_2 3)  B) 2/(2-log_3 2)  "
                            "C) 1/(1-log_4 3)  D) 2√2/(2-log_√2 3)'. "
                            "Never skip or summarise options — they are needed to pick the correct one.\n"
                            "   - CRITICAL — diagram/figure numerical labels: for force diagrams, "
                            "free body diagrams, circuit diagrams, graphs, or any labeled figure, "
                            "you MUST explicitly list ALL numerical values shown IN the diagram "
                            "(on arrows, axes, components, nodes). "
                            "For a force/FBD diagram, state each force with its direction, e.g. "
                            "'Forces: 5N in +x direction (right), 6N in -x direction (left), "
                            "7N in +y direction (up), 8N in -y direction (down)'. "
                            "These labels are the most important part of the problem — NEVER omit them.\n"
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
            max_tokens=700,
        ),
        timeout=30.0,   # 90B needs a bit more time; hard wall-clock deadline
    )
    return response.choices[0].message.content.strip()


async def _check_daily_limit(student: Student, db: AsyncSession) -> None:
    """Raise 429 if a free-tier student has hit their daily question cap.

    Redis-first: O(1) INCR counter keyed by (student_id, UTC date).
    Falls back to a Postgres COUNT query when Redis is unavailable.
    """
    if student.is_premium:
        return

    redis = get_redis()
    if redis is not None:
        today = date.today().isoformat()
        rate_key = f"rate:{student.id}:{today}"
        try:
            count = await redis.get(rate_key)
            count = int(count) if count is not None else 0
            if count >= FREE_DAILY_LIMIT:
                log.info(
                    "ask.rate_limit(redis)  student_id=%s  daily_count=%d  limit=%d",
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
            return  # Redis check passed — skip Postgres
        except HTTPException:
            raise
        except Exception:
            log.warning("ask.rate_limit: Redis error — falling back to Postgres", exc_info=True)

    # Postgres fallback
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
                if nxt in ('"', '\\', '/'):
                    out.append(ch)
                    out.append(nxt)
                    i += 2
                elif nxt in ('t', 'n', 'r'):
                    # \t / \n / \r are valid JSON escapes, BUT many LaTeX commands
                    # start with these same letters (\theta, \tau, \tan, \times,
                    # \nu, \nabla, \rho, \right …).  When the LLM omits the outer
                    # double-backslash, json.loads would eat the control char and
                    # corrupt the LaTeX.  Detect known LaTeX suffixes and double
                    # the backslash so they survive json.loads intact.
                    rest = text[i + 2:] if i + 2 < len(text) else ""
                    _latex_suffixes: dict[str, tuple[str, ...]] = {
                        't': ('heta', 'au', 'an', 'imes', 'ext', 'ilde'),
                        'n': ('u', 'abla', 'eg', 'ot'),
                        'r': ('ho', 'ight', 'angle'),
                    }
                    if any(rest.startswith(s) for s in _latex_suffixes.get(nxt, ())):
                        # LaTeX command — double the backslash
                        out.append('\\\\')
                        i += 1
                    else:
                        # Real JSON control char — keep as-is
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


def _dedup_repetition(text: str) -> str:
    """
    Detect and truncate infinite-loop artifacts from small (8B) LLMs.

    When NIM throttles the 70B model and the 8B fallback handles a hard
    algebraic question, the 8B can enter a token-spinning loop: it keeps
    writing the same LaTeX fragment (e.g. '= \\frac{\\log 4}{\\log 3 - \\log 4}')
    over and over until max_tokens is reached.  This function finds any
    substring whose *repeated content* accounts for ≥ MIN_DENSITY fraction
    of the total text (genuine loops are 60–90% density) and truncates after
    the Nth occurrence, keeping only a clean prefix.

    Key insight: natural prose repeats short key terms (e.g. "hydrogen bond"
    in a bio explanation) but density stays ≪ 30%.  A real LLM loop has the
    same 35–100-char fragment filling 50–90% of the output.

    Per-length config: (min_occurrences, cut_after_hit, min_density)
    """
    n = len(text)
    if n < 400:
        return text  # too short to have a meaningful loop

    _THRESHOLDS = {
        100: (5, 3, 0.35),   # 8B LaTeX loops: ~16–26 occ, density ~70–80%
        60:  (6, 3, 0.35),
        35:  (10, 4, 0.40),  # raised: natural prose hits 5–8 occ at <15% density
    }

    for pat_len in (100, 60, 35):
        min_occ, cut_after, min_density = _THRESHOLDS[pat_len]
        probe_end = min(n // 2, 1200)
        for start in range(0, probe_end - pat_len, pat_len // 3):
            pattern = text[start:start + pat_len]
            occ = text.count(pattern)
            if occ < min_occ:
                continue
            # Density check: repeated content must dominate the text.
            # e.g. 6×35/2044 = 10% → natural prose, skip.
            #      20×35/1200 = 58% → genuine loop, truncate.
            density = (occ * pat_len) / n
            if density < min_density:
                continue
            # Found a genuine repetition loop — walk to cut_after-th occurrence
            pos, hit = 0, 0
            while hit < cut_after:
                idx = text.find(pattern, pos)
                if idx == -1:
                    break
                pos = idx + 1
                hit += 1
            cut = pos - 1
            log.warning(
                "ask.repetition_truncated  pat_len=%d  occurrences=%d  density=%.2f  cut_at=%d  total=%d",
                pat_len, occ, density, cut, n,
            )
            return text[:cut] + "..."
    return text


def _recover_truncated_json(text: str) -> str | None:
    """
    Attempt to close a truncated JSON object.

    Most common case: LLM hits max_tokens mid-string inside the 'explanation'
    field — the JSON looks like  {"explanation": "long text [CUTOFF]
    The old approach (truncate to last clean endpoint) produced {"explanation"}
    (no value) which is invalid.  This version instead COMPLETES the open
    string with '...' and closes all open brackets/braces, giving:
        {"explanation": "long text [CUTOFF]..."}
    which is valid JSON and preserves what was generated.
    Returns None if text doesn't look like a truncated JSON object.
    """
    text = text.strip()
    if not text.startswith("{"):
        return None

    depth_stack: list[str] = []
    in_string = False
    escaped = False

    for c in text:
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
            depth_stack.append("}")
        elif c == "[":
            depth_stack.append("]")
        elif c in "}]":
            if depth_stack and depth_stack[-1] == c:
                depth_stack.pop()

    if not depth_stack and not in_string:
        return None  # already balanced — recovery not needed

    recovered = text
    # If we're inside a string value, close it first
    if in_string:
        recovered += '...'   # ellipsis signals truncation to callers
        recovered += '"'     # close the string

    # Strip trailing comma before closing (trailing commas are invalid JSON)
    stripped = recovered.rstrip()
    if stripped.endswith(','):
        recovered = stripped[:-1]

    # Close all open arrays / objects in reverse order
    recovered += ''.join(reversed(depth_stack))
    return recovered


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


# ── Keyword-based topic/subject fallback ─────────────────────────────────────
# Used when the LLM omits topic/subject from its JSON response.
# Each entry: (keywords_tuple, canonical_topic, subject)
# Entries are checked in order against the lowercased question — first match wins.
_TOPIC_KEYWORD_MAP: list[tuple[tuple[str, ...], str, str]] = [
    # Physics — canonical names match iOS jeeSyllabus chapter titles exactly
    (("newton", "f=ma", "law of motion", "laws of motion", "friction", "normal force", "tension"), "Laws of Motion", "Physics"),
    (("kinematics", "displacement", "projectile", "uniform motion", "distance vs displacement", "equations of motion"), "Kinematics", "Physics"),
    (("velocity", "speed", "retardation", "deceleration"), "Kinematics", "Physics"),
    (("acceleration", "mass and acceleration"), "Kinematics", "Physics"),
    (("work done", "kinetic energy", "potential energy", "conservation of energy", "mechanical energy", "power output"), "Work, Energy & Power", "Physics"),
    (("gravitation", "gravitational", "satellite", "orbital velocity", "escape velocity", "kepler"), "Gravitation", "Physics"),
    (("carnot", "isothermal", "adiabatic", "heat engine", "efficiency of engine"), "Thermodynamics", "Physics"),
    # Waves & Oscillations covers both wave phenomena and SHM (iOS has a single chapter)
    (("frequency", "wavelength", "amplitude", "sound wave", "resonance", "standing wave", "doppler"), "Waves & Oscillations", "Physics"),
    (("simple harmonic", "shm", "oscillation", "pendulum", "time period of spring"), "Waves & Oscillations", "Physics"),
    (("refraction", "reflection", "lens", "mirror", "snell", "critical angle", "total internal reflection", "ray optics", "prism"), "Optics", "Physics"),
    (("electric field", "electric potential", "capacitor", "coulomb", "gauss", "electrostatics"), "Electrostatics", "Physics"),
    (("current", "voltage", "resistance", "ohm", "circuit", "kirchhoff", "potentiometer", "wheatstone"), "Current Electricity", "Physics"),
    (("magnetic field", "solenoid", "magnetic flux", "biot-savart", "ampere law", "magnetism"), "Magnetism", "Physics"),
    (("faraday", "electromagnetic induction", "lenz", "self inductance", "mutual inductance"), "Electromagnetic Induction", "Physics"),
    (("photoelectric", "nuclear", "radioactive", "photon", "x-ray", "de broglie", "bohr model", "atomic spectrum"), "Modern Physics", "Physics"),
    (("torque", "angular velocity", "angular momentum", "moment of inertia", "rolling"), "Rotational Motion", "Physics"),
    (("fluid", "viscosity", "buoyancy", "archimedes", "bernoulli", "surface tension", "capillary"), "Fluid Mechanics", "Physics"),
    (("momentum", "impulse", "elastic collision", "inelastic collision", "centre of mass"), "Centre of Mass & Momentum", "Physics"),
    (("semiconductor", "diode", "transistor", "logic gate", "rectifier"), "Semiconductors", "Physics"),
    # Chemistry
    (("atomic structure", "orbital", "quantum number", "aufbau", "heisenberg", "pauli", "hund"), "Atomic Structure", "Chemistry"),
    (("ionic bond", "covalent bond", "hybridization", "vsepr", "polarity of bond", "molecular orbital"), "Chemical Bonding", "Chemistry"),
    (("enthalpy", "gibbs free energy", "hess", "endothermic", "exothermic", "born-haber"), "Thermochemistry", "Chemistry"),
    (("chemical equilibrium", "le chatelier", "ksp", "equilibrium constant"), "Equilibrium", "Chemistry"),
    (("acid", "base", "ph", "neutralization", "buffer solution", "titration"), "Equilibrium", "Chemistry"),
    (("oxidation", "reduction", "redox", "electrochemical cell", "electrolysis", "galvanic", "nernst", "electrolytic"), "Electrochemistry", "Chemistry"),
    # Organic Chemistry — II: functional-group reactions (more specific, checked first)
    (("alcohol", "aldehyde", "ketone", "carboxylic acid", "ester", "polymer", "amide", "amine"), "Organic Chemistry — II", "Chemistry"),
    # Organic Chemistry — I: naming, mechanisms, structure
    (("alkane", "alkene", "alkyne", "benzene", "aromatic", "organic chemistry", "iupac", "isomerism", "carbonyl", "functional group", "reaction mechanism"), "Organic Chemistry — I", "Chemistry"),
    (("periodic table", "periodicity", "transition metal", "lanthanide", "halogen", "noble gas"), "Periodic Table", "Chemistry"),
    (("solution", "molality", "molarity", "colligative", "osmosis", "vapour pressure lowering"), "Solutions", "Chemistry"),
    (("rate of reaction", "rate law", "activation energy", "catalyst", "order of reaction", "half life", "arrhenius"), "Chemical Kinetics", "Chemistry"),
    (("coordination compound", "ligand", "crystal field", "cfse", "chelate"), "Coordination Compounds", "Chemistry"),
    (("solid state", "unit cell", "crystal lattice", "packing efficiency"), "Solid State", "Chemistry"),
    (("mole concept", "stoichiometry", "limiting reagent", "avogadro"), "Mole Concept", "Chemistry"),
    # Mathematics — canonical names match iOS chapter titles
    (("differentiation", "chain rule", "implicit differentiation", "first principle", "maxima", "minima"), "Differential Calculus", "Mathematics"),
    (("limit", "continuity", "l'hopital", "left hand limit"), "Differential Calculus", "Mathematics"),
    (("integration", "definite integral", "area under curve", "volume of revolution"), "Integral Calculus", "Mathematics"),
    (("differential equation", "order of differential"), "Differential Equations", "Mathematics"),
    (("matrix", "determinant", "inverse matrix", "system of linear equations", "cramer"), "Matrices & Determinants", "Mathematics"),
    (("binomial theorem", "binomial expansion", "binomial coefficient", "permutation", "combination", "counting principle"), "Permutation & Combination", "Mathematics"),
    (("probability", "random variable", "expected value", "bayes theorem", "statistics", "standard deviation", "mean and variance"), "Probability & Statistics", "Mathematics"),
    (("arithmetic progression", "geometric progression", " ap ", " gp ", "sum of series", "harmonic progression"), "Sequences & Series", "Mathematics"),
    (("trigonometric", "sin ", "cos ", "tan ", "cotangent", "secant", "cosecant", "sine rule", "cosine rule", "inverse trig"), "Trigonometry", "Mathematics"),
    (("complex number", "imaginary unit", "argand", "modulus of complex"), "Complex Numbers", "Mathematics"),
    (("quadratic equation", "discriminant", "roots of equation", "sum of roots"), "Quadratic Equations", "Mathematics"),
    # Coordinate Geometry covers straight lines, circles, and conics (single iOS chapter)
    (("straight line", "slope intercept", "pair of lines", "angle bisector", "conic section", "parabola", "ellipse", "hyperbola", "focus of", "circle equation"), "Coordinate Geometry", "Mathematics"),
    (("direction cosines", "direction ratios", "distance in 3d", "three dimensional geometry", "dot product", "cross product", "unit vector", "vector addition"), "3D Geometry & Vectors", "Mathematics"),
    (("set theory", "venn diagram", "bijection", "domain and range", "sets and relations", "relation and function"), "Sets & Relations", "Mathematics"),
    # Biology
    (("mitosis", "meiosis", "cell division", "chromosome", "cell cycle"), "Cell Biology", "Biology"),
    (("dna replication", "transcription", "translation", "protein synthesis", "rna"), "Molecular Biology", "Biology"),
    (("genetics", "mendelian", "allele", "heredity", "punnett square", "dominant recessive"), "Genetics", "Biology"),
    (("evolution", "natural selection", "mutation", "speciation", "darwin"), "Evolution", "Biology"),
    (("heart", "blood pressure", "cardiac", "circulation", "artery", "vein"), "Circulatory System", "Biology"),
    (("breathing", "lung", "alveoli", "respiratory", "oxygen transport"), "Respiratory System", "Biology"),
    (("kidney", "nephron", "excretion", "urine formation", "dialysis"), "Excretory System", "Biology"),
    (("digestion", "stomach", "intestine", "liver", "pancreas", "enzyme in digestion"), "Digestive System", "Biology"),
    (("neuron", "synapse", "reflex arc", "spinal cord", "nervous system"), "Nervous System", "Biology"),
    (("hormone", "endocrine", "insulin", "thyroid", "pituitary", "adrenaline"), "Endocrine System", "Biology"),
    (("photosynthesis", "chlorophyll", "light reaction", "dark reaction", "calvin cycle"), "Plant Physiology", "Biology"),
    (("transpiration", "stomata", "xylem", "phloem", "root pressure"), "Transport in Plants", "Biology"),
    (("ecosystem", "food chain", "food web", "biodiversity", "biome", "trophic level"), "Ecology", "Biology"),
]


def _infer_topic_subject(question: str) -> tuple[str | None, str | None]:
    """
    Keyword fallback: infer (topic, subject) from the question text when the
    LLM omits them. Returns (None, None) if no match is found.
    """
    q = question.lower()
    for keywords, topic, subject in _TOPIC_KEYWORD_MAP:
        if any(kw in q for kw in keywords):
            return topic, subject
    return None, None


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

    # Pass 1: always fix LaTeX backslash escapes first, THEN parse.
    # json.loads silently accepts \f as form-feed (U+000C), which corrupts
    # \frac → <FF>rac, \beta → <BS>eta, etc. — preprocessing catches this.
    try:
        return json.loads(_escape_latex_backslashes(text))
    except (json.JSONDecodeError, Exception):
        pass

    # Pass 2: try raw parse (edge-case fallback for already-clean JSON)
    try:
        return json.loads(text)
    except json.JSONDecodeError:
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
        pass

    # Pass 5: truncation recovery — LLM hit max_tokens mid-JSON.
    # _extract_last_json_object already returned None (no complete object).
    # Try to close the truncated JSON and parse what we have.
    # At minimum this rescues the explanation field which is always written first.
    recovered = _recover_truncated_json(raw.strip())
    if recovered:
        for transform in (
            lambda s: s,
            _escape_latex_backslashes,
            _fix_control_chars_in_strings,
            lambda s: _escape_latex_backslashes(_fix_control_chars_in_strings(s)),
        ):
            try:
                result = json.loads(transform(recovered))
                if isinstance(result, dict) and result:
                    log.warning("ask.parse_recovered_truncated  keys=%s", list(result.keys()))
                    return result
            except (json.JSONDecodeError, Exception):
                pass

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
                answer="",
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

    # ── SymPy verification: ground-truth answer before 70B explanation ──
    # Runs sequentially here (after vision+RAG) so the verified answer can be
    # injected into the LLM prompt.  Falls through silently on any failure.
    # IMPORTANT: when an image is present, pass only the extracted image text
    # to SymPy — the user's question ("Which one is correct?", "Solve this") is
    # a meta-question that causes the 8B to return CANNOT_EVALUATE.  The actual
    # math is entirely in the image content.
    from app.tools.sympy_verifier import verify_with_sympy
    sympy_answer: str | None = None
    _sympy_input = (
        extracted
        if body.image_b64 and extracted and extracted not in ("", "NOT_EDUCATIONAL")
        else effective_question
    )
    try:
        sympy_result = await verify_with_sympy(_sympy_input)
        if sympy_result:
            sympy_answer = sympy_result.answer
            log.info(
                "ask.sympy_verified  student_id=%s  answer=%s",
                student_id, sympy_answer,
            )
    except Exception:
        log.warning("ask.sympy_failed  student_id=%s", student_id, exc_info=True)

    # ── Direct RAG + single LLM call (3-4× faster than CrewAI ReAct loop) ────
    # Hard wall-clock cap: the iOS client times out at 120 s (timeoutIntervalForRequest).
    # SymPy + all LLM fallbacks can theoretically consume ~115 s.  Capping at 90 s here
    # guarantees a clean 504 response reaches the client well before the iOS silent timeout.
    t0 = time.perf_counter()
    try:
        raw_output: str = await asyncio.wait_for(
            _ask_direct(
                effective_question,
                student_id,
                lang,
                weak_topics,
                body.exam_type,
                pre_chunks=pre_chunks,
                sympy_answer=sympy_answer,
                history=body.history or None,
            ),
            timeout=90.0,
        )
    except asyncio.TimeoutError:
        elapsed_ms = (time.perf_counter() - t0) * 1_000
        log.error(
            "ask.llm_timeout  student_id=%s  lang=%s  %.0fms",
            student_id, lang, elapsed_ms,
        )
        raise HTTPException(
            status_code=status.HTTP_504_GATEWAY_TIMEOUT,
            detail={
                "error": "llm_timeout",
                "message": "The AI is taking too long to respond. Please try again in a moment.",
            },
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
    llm_topic = parsed.get("topic") if parsed else None
    llm_subject = parsed.get("subject") if parsed else None
    # Keyword fallback: fill topic/subject when the LLM omits them so that
    # progress tracking (which filters WHERE topic IS NOT NULL) counts every
    # academically-relevant question the student asks.
    if not llm_topic:
        llm_topic, llm_subject = _infer_topic_subject(body.question)
    answer_record = QuizAnswer(
        student_id=current_student.id,
        question=body.question[:1000],  # cap at column limit; store original question
        topic=llm_topic,
        subject=llm_subject,
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

    # ── Redis: increment rate-limit counter + persist conversation history ─
    redis = get_redis()
    if redis is not None:
        try:
            # Rate-limit counter: INCR with TTL to end of UTC day
            today = date.today().isoformat()
            rate_key = f"rate:{student_id}:{today}"
            now_utc = datetime.now(timezone.utc)
            midnight_utc = datetime.combine(
                date.today() + timedelta(days=1), datetime.min.time()
            ).replace(tzinfo=timezone.utc)
            ttl_secs = max(1, int((midnight_utc - now_utc).total_seconds()))
            await redis.incr(rate_key)
            await redis.expire(rate_key, ttl_secs)

            # Conversation history: append this Q&A pair, keep last 20 turns (= 10 Q&A pairs)
            hist_key = f"chat:history:{student_id}"
            stored_raw = await redis.get(hist_key)
            stored: list = json.loads(stored_raw) if stored_raw else []
            # Append user question
            stored.append({"role": "user", "content": body.question[:600]})
            # Append assistant answer (core explanation, capped for storage)
            asst_content = (parsed.get("explanation") or "")[:800]
            stored.append({"role": "assistant", "content": asst_content})
            # Keep last 20 turns (= 10 Q&A pairs) — 7-day TTL
            stored = stored[-20:]
            await redis.set(hist_key, json.dumps(stored), ex=604800)  # 7-day TTL
        except Exception:
            log.warning("ask.redis_post_save_failed  student_id=%s", student_id, exc_info=True)

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
        answer=parsed.get("answer", ""),
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


@router.get("/ask/history", tags=["ask"])
async def get_chat_history(
    current_student: Student = Depends(get_current_student),
):
    """
    Return the last 20 conversation turns (10 Q&A pairs) for the current student.

    Used by the iOS app on StudyView appear to restore the previous session.
    Returns an empty list when Redis is not configured or the student has no history.
    """
    redis = get_redis()
    if redis is None:
        return {"history": []}
    hist_key = f"chat:history:{current_student.id}"
    try:
        raw = await redis.get(hist_key)
        if raw is None:
            return {"history": []}
        turns = json.loads(raw)
        # Sanitize any legacy turns whose content exceeds the client-side max_length.
        _MAX = 1800
        sanitized = [
            {**t, "content": t["content"][:_MAX]} if len(t.get("content", "")) > _MAX else t
            for t in turns
        ]
        return {"history": sanitized}
    except Exception:
        log.warning("get_chat_history: Redis error  student_id=%s", current_student.id, exc_info=True)
        return {"history": []}


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
    sympy_answer: str | None = None,        # SymPy-verified answer (None = not available)
    history: list | None = None,            # list of ConversationTurnIn (prior Q&A turns)
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
    primary_model = s.LLM_AGENT_MODEL if language == "en" else s.LLM_CHAT_MODEL

    # Build optional SymPy verification block injected before the steps
    _sympy_block = ""
    if sympy_answer is not None:
        _sympy_block = (
            f"\n⚠️  NUMERICALLY VERIFIED ANSWER (SymPy symbolic computation): "
            f"{sympy_answer}\n"
            f"If this matches one of the given MCQ options, pick that option and explain "
            f"the step-by-step working that arrives at {sympy_answer}.\n"
            f"If it does NOT match any option (SymPy may have used wrong values), "
            f"ignore it and solve the question using ONLY the values stated in the question.\n"
            f"NEVER invent a different question to fit the SymPy value.\n"
        )

    # Build optional conversation history block injected before the question
    _history_block = ""
    if history:
        turns_text = "\n".join(
            f"[{'Student' if t.role == 'user' else 'Tutor'}]: {t.content[:600]}"
            for t in history[-10:]
        )
        _history_block = (
            f"\n\n--- CONVERSATION HISTORY (most recent last) ---\n"
            f"{turns_text}\n"
            f"--- END CONVERSATION HISTORY ---\n"
            f"The student's NEW question is below. Use the history for context "
            f"(e.g. 'that formula', 'another example', 'step 2 from before') "
            f"but answer only the NEW question.\n"
        )

    user_message = (
        f"A student (ID: {student_id}) has asked: {question}\n"
        f"Exam context: {exam_context_str}\n"
        f"Student's weak topics (supplementary context only): {weak_topics_str}\n"
        f"{_history_block}"
        f"\n"
        f"CRITICAL RULE: Your response MUST address the student's EXACT question. "
        f"Do NOT pivot to a different topic because it appears in the weak topics list.\n"
        f"CRITICAL RULE: The JSON 'explanation' field must begin DIRECTLY with the educational "
        f"content. Do NOT include any of the following in the explanation:\n"
        f"  - Your classification reasoning ('Since the student has asked...', 'This is classified as...')\n"
        f"  - Meta-commentary about the question ('The concept is not specified, so I will choose...')\n"
        f"  - Any preamble about what you are about to explain\n"
        f"  Start immediately with the concept, definition, formula, or answer.\n"
        f"CRITICAL RULE: If the question is vague (e.g. 'explain a concept from Physics'), pick ONE "
        f"specific concept from the reference material and explain it directly — do NOT narrate your "
        f"selection process.\n"
        f"{_sympy_block}"
        f"\n"
        f"\n--- REFERENCE MATERIAL (textbook/past-paper extracts for background — "
        f"this is NOT the student's question) ---\n"
        f"{rag_context}\n"
        f"--- END REFERENCE MATERIAL ---\n"
        f"\n"
        f"Steps:\n"
        f"1. Classify the question as ONE of:\n"
        f"   MCQ PROBLEM — question already has numbered/lettered answer options\n"
        f"   ACADEMIC TOPIC — concept/formula/problem WITHOUT pre-supplied options\n"
        f"   PRACTICE REQUEST — student wants practice/mock questions on a topic or exam\n"
        f"   META QUERY — about an exam, course, or syllabus overview\n"
        f"2. For MCQ PROBLEM: compute the answer numerically first, match to the option whose "
        f"value equals your result, then COMMIT — do NOT re-evaluate after matching. "
        f"For force/equilibrium problems: the balancing force is the EXACT NEGATIVE of the "
        f"vector sum of all given forces (opposite direction). "
        f"Start explanation with 'Correct Answer: Option N — value'.\n"
        f"   For ACADEMIC TOPIC: explanation + worked example + 2 practice problems.\n"
        f"   For PRACTICE REQUEST: generate 3 actual JEE/NEET-style questions (with full "
        f"solutions) on the requested topic/exam. NEVER say 'the question is not provided' "
        f"— you are the generator. Set \"answer\" to empty string in the JSON.\n"
        f"   For META QUERY: concise topic/exam overview + 2 practice problems. "
        f"Set \"answer\" to empty string in the JSON.\n"
        f"3. Respond in {lang_name} at Class 11-12 level.\n"
        f"4. Format practice problems per the exam context above.\n"
        f'Return ONLY valid JSON: {{"answer":"<option letter or value>","explanation":"...","worked_example":"...",'
        f'"practice_problems":[{{"question":"...","answer":"...","question_type":"...",'
        f'"marks":4,"marking_scheme":"..."}}],'
        f'"topic":"...","subject":"...","question_type":"...","marks":4,"marking_scheme":"..."}}'
    )

    async def _call_model(model_name: str, timeout_s: float, max_tok: int = 3500) -> str:
        resp = await asyncio.wait_for(
            acompletion(
                model=f"openai/{model_name}",
                api_base=s.LLM_BASE_URL,
                api_key=s.LLM_API_KEY,
                messages=[
                    {"role": "system", "content": get_tutor_prompt(language)},
                    {"role": "user",   "content": user_message},
                ],
                max_tokens=max_tok,
                temperature=0.1,
            ),
            timeout=timeout_s,
        )
        raw = resp.choices[0].message.content.strip()
        return _dedup_repetition(raw)  # truncate 8B infinite-loop artifacts

    async def _call_groq(timeout_s: float, max_tok: int = 3500) -> str:
        """Call Groq API when available — ~2 s latency vs NIM's 40-60 s queue."""
        resp = await asyncio.wait_for(
            acompletion(
                model=f"groq/{s.GROQ_MODEL}",
                api_key=s.GROQ_API_KEY,
                messages=[
                    {"role": "system", "content": get_tutor_prompt(language)},
                    {"role": "user",   "content": user_message},
                ],
                max_tokens=max_tok,
                temperature=0.1,
            ),
            timeout=timeout_s,
        )
        raw = resp.choices[0].message.content.strip()
        return _dedup_repetition(raw)

    # ── Model routing ──────────────────────────────────────────────────────
    # 1. Try primary NIM model (70B or sarvam-m for non-EN)
    # 2. On timeout OR connection error: if Groq key is set, use Groq (fast + reliable)
    # 3. Final fallback: NIM 8B (only if Groq is not configured)
    nim_error: Exception | None = None
    try:
        # 55 s: NIM 70B queues for 40–60 s under load; 55 s gives it a fair
        # chance to respond before falling back to the smaller model.
        return await _call_model(primary_model, 55.0, max_tok=3500)
    except (asyncio.TimeoutError, Exception) as exc:
        nim_error = exc
        log.warning(
            "ask.primary_failed  student_id=%s  primary=%s  error=%s  groq_available=%s",
            student_id, primary_model, type(exc).__name__, bool(s.GROQ_API_KEY),
        )

    # Prefer Groq when configured — much faster than NIM 8B and works when NIM is unreachable
    if s.GROQ_API_KEY:
        try:
            return await _call_groq(20.0, max_tok=3500)
        except Exception:
            log.warning(
                "ask.groq_fallback_failed  student_id=%s — retrying with NIM 8B",
                student_id, exc_info=True,
            )

    # Last resort: NIM 8B fallback (only useful when primary NIM model is throttled,
    # not when the entire NIM service is unreachable)
    if isinstance(nim_error, asyncio.TimeoutError):
        # 8B gets 1500 tokens: enough for a clear answer, short enough to cap loops
        return await _call_model(s.LLM_FAST_MODEL, 35.0, max_tok=1500)

    # NIM is unreachable and no Groq key — re-raise to produce informative 503
    raise nim_error
