"""
SymPy-based answer verifier for JEE/NEET math and physics problems.

Flow
────
1. Fast 8B LLM translates the question text into executable SymPy Python code.
2. Code is executed in a restricted sandbox (whitelisted globals + AST check).
3. On success → returns SympyResult with the verified numerical/symbolic answer.
4. On any failure (timeout, bad code, CANNOT_EVALUATE) → returns None so the
   caller falls through to the normal unverified LLM path.

Security model
──────────────
• AST whitelist: only sympy / math / cmath / fractions / decimal allowed as imports.
• Dangerous builtins blocked at AST level (eval, exec, open, __import__, etc.).
• Runtime sandbox: __builtins__ replaced with a minimal whitelist dict.
• Hard execution timeout via asyncio.wait_for + ThreadPoolExecutor.
• Generated code is compiled to bytecode with a fake filename <sympy_sandbox>
  so traceback leakage is minimised.

Coverage
────────
✅  JEE/NEET math  — logarithms, trigonometry, algebra, calculus, series, limits
✅  Physics        — kinematics, forces, energy, work (numerical problems)
✅  Chemistry      — stoichiometry, equilibrium constants, gas laws
⚠️  Partial        — problems that mix concepts + numbers (fallback to LLM)
❌  Conceptual     — theory / explanation / organic-chemistry mechanisms → CANNOT_EVALUATE
"""

from __future__ import annotations

import ast
import asyncio
import contextlib
import io
import logging
import re
from concurrent.futures import ThreadPoolExecutor
from typing import Optional

from litellm import acompletion

from app.config import get_settings

log = logging.getLogger(__name__)

# ── Thread pool for CPU-bound SymPy execution ──────────────────────────
_SYMPY_EXECUTOR = ThreadPoolExecutor(max_workers=2, thread_name_prefix="sympy")

# ── Timeouts ───────────────────────────────────────────────────────────
_LLM_TRANSLATE_TIMEOUT_S = 12.0   # 8B code-gen call
_SYMPY_EXEC_TIMEOUT_S = 8.0       # CPU execution of generated SymPy code

# ── Allowed top-level import modules ──────────────────────────────────
_ALLOWED_IMPORTS = frozenset(
    {"sympy", "math", "cmath", "fractions", "decimal", "itertools", "functools"}
)

# ── Builtins blocked even at AST level ────────────────────────────────
_DANGEROUS_BUILTINS = frozenset({
    "eval", "exec", "compile", "__import__", "open", "breakpoint",
    "input", "memoryview", "vars", "locals", "globals", "getattr",
    "setattr", "delattr", "__builtins__",
})

# ── Translation prompt ─────────────────────────────────────────────────
_TRANSLATE_SYSTEM_PROMPT = """\
You convert math/physics/chemistry problems into executable Python SymPy code.

⚠ CRITICAL — USE ONLY EXACT VALUES FROM THE PROBLEM ⚠
Every numerical value in your code MUST be copied verbatim from the problem statement.
NEVER invent, guess, or substitute different numbers.
Example: if the problem states forces 5N (+x), 6N (-x), 7N (+y), 8N (-y) then your
code MUST use exactly 5, 6, 7, 8 — using 1, 2, 3, 4 or any other values is WRONG.
Read the problem text carefully before writing a single line of code.

STRICT RULES
1. Import ONLY from: sympy, math, cmath, fractions, decimal
2. The LAST statement must assign to `result` and then: print(result)
3. For answers that simplify to a CLEAN integer or simple fraction, use nsimplify().
   For answers that are irrational logarithmic expressions (log ratios, etc.),
   use round(float(expr), 4) to give a decimal — it is unambiguous for MCQ matching.
   Use sympy.N(expr, 6) as an alternative for longer decimals.
4. Logarithm syntax: sympy.log(x, base)  e.g. log(9, 2) = log₂(9)
5. CRITICAL — log-exponent identity: for ((expr)^k)^(1/log_b(expr)), set u = expr,
   compute u**(k / log(u, b)) using sympy directly — DO NOT expand expr first.
6. For MCQ: COMPUTE the numerical/symbolic answer value. NEVER output an option
   letter (A/B/C/D) or option number (1/2/3/4). The tutor model picks the option
   — your job is to produce the computable value that the option represents.
   If you cannot compute a value (conceptual/identify question), output CANNOT_EVALUATE.
7. For physics word problems: set up equations symbolically, substitute, solve.
8. For stoichiometry: use sympy.Matrix row-reduction to balance equations.
9. Strip any markdown code fences from your output.
10. If the problem is ANY of:
      • conceptual / theory ("explain", "describe", "what is", "why", "state", "define")
      • organic chemistry mechanisms or named reactions
      • asking to draw / label a diagram
      • subjective / essay style
      • MCQ asking to IDENTIFY a named entity — a type of bond, force, interaction,
        structure, compound, element, reaction, functional group, or biological concept
        where the answer is a NAME not a number
        (e.g. "which force stabilises α-helix?", "which bond is present in H₂O?",
         "which hybridisation does carbon have in ethene?", "which cell organelle...")
      • biology questions: protein/DNA/RNA/cell/genetics/ecology/physiology
      • requests to GENERATE or PRACTICE questions ("practice X", "give me questions",
        "mock test", "quiz me", "JEE mock", "NEET practice", "solve problems on X")
      • single-word or short topic/subject names with no mathematical content
        ("Algebra", "Trigonometry", "Physics", "Chemistry", "Mechanics", "Optics")
      • exam/course overview requests ("JEE syllabus", "NEET course", "what is JEE")
    → output exactly (nothing else): CANNOT_EVALUATE
11. If you are not confident you can compute it correctly → output: CANNOT_EVALUATE

OUTPUT: Only the Python code or CANNOT_EVALUATE. No explanation. No markdown fences.

─────────────────────────── EXAMPLES ───────────────────────────

Problem: ((log₂9)²)^(1/log₂(log₂9)) × (√7)^(1/log₄7)
Code:
from sympy import log, sqrt, nsimplify
u = log(9, 2)
term1 = u ** (2 / log(u, 2))
term2 = sqrt(7) ** (1 / log(7, 4))
result = nsimplify(term1 * term2)
print(result)

Problem: Find the value of sin²(15°) + sin²(75°)
Code:
from sympy import sin, pi, nsimplify
result = nsimplify(sin(pi/12)**2 + sin(5*pi/12)**2)
print(result)

Problem: Differentiate x³ + 2x² – 5x + 1 and find the value at x=2
Code:
from sympy import symbols, diff, nsimplify
x = symbols('x')
expr = x**3 + 2*x**2 - 5*x + 1
result = nsimplify(diff(expr, x).subs(x, 2))
print(result)

Problem: If 3^x = 4^(x-1), then x = ? [JEE-Advanced 2013]
Code:
from sympy import symbols, log, solve
# NEVER do solve(3**x - 4**(x-1), x) — SymPy cannot solve transcendental eqs.
# Instead take ln of both sides to get a LINEAR equation in x:
# x*ln3 = (x-1)*ln4  =>  x*(ln3 - ln4) = -ln4  =>  x = ln4/(ln4-ln3)
x = symbols('x')
eq = x * log(3) - (x - 1) * log(4)
sol = solve(eq, x)[0]
result = round(float(sol), 4)   # decimal approx — unambiguous for MCQ matching
print(result)

Problem: A ball is projected at 30 m/s at 60° angle. Find horizontal range (g=10).
Code:
from sympy import sin, cos, pi, nsimplify
v, theta, g = 30, pi/3, 10
result = nsimplify(v**2 * sin(2*theta) / g)
print(result)

Problem: Find the value of 6 + log_{3/2}(1/(3*sqrt(2)) * sqrt(4 - 1/(3*sqrt(2)) * sqrt(4 - ...))) [infinite nested radical]
Code:
from sympy import symbols, sqrt, solve, log, Rational, nsimplify
# Let y = (1/(3*sqrt(2))) * sqrt(4 - y)  [infinite self-similar structure]
# Then: (3*sqrt(2)*y)^2 = 4 - y  =>  18*y^2 + y - 4 = 0
y = symbols('y', positive=True)
eq = 18*y**2 + y - 4
y_val = solve(eq, y)[0]        # positive root = 4/9
base = Rational(3, 2)
result = nsimplify(6 + log(y_val) / log(base))
print(result)

Problem: Forces on a body: 5N (+x), 6N (-x), 7N (+y), 8N (-y). Find the additional force (magnitude and angle) for equilibrium.
Code:
from sympy import sqrt, atan2, pi, nsimplify
# Net of given forces
Fx_net = 5 - 6   # -1 N
Fy_net = 7 - 8   # -1 N
# Balancing force = exact negative of net
Fx_bal = -Fx_net  # +1
Fy_bal = -Fy_net  # +1
mag = nsimplify(sqrt(Fx_bal**2 + Fy_bal**2))   # sqrt(2)
angle_deg = nsimplify(atan2(Fy_bal, Fx_bal) * 180 / pi)  # 45
result = f"{mag} N at {angle_deg} degrees"
print(result)

Problem: Explain Newton's third law.
Output: CANNOT_EVALUATE

Problem: A body falls from H, hits inclined plane at height h, velocity becomes horizontal. Find h for maximum total time to reach ground.
Code:
from sympy import symbols, sqrt, diff, solve, nsimplify
# Total time T ∝ sqrt(H-h) + sqrt(h)  (g cancels in the ratio)
# Maximise by differentiating w.r.t. h and setting = 0
H, h = symbols('H h', positive=True)
T = sqrt(H - h) + sqrt(h)
h_opt = solve(diff(T, h), h)[0]   # dT/dh = 0
result = nsimplify(h_opt)          # gives H/2
print(result)

Problem: Find the value of x that maximises f(x) = sqrt(a-x) + sqrt(x) for x in [0,a].
Code:
from sympy import symbols, sqrt, diff, solve, nsimplify
a, x = symbols('a x', positive=True)
f = sqrt(a - x) + sqrt(x)
x_opt = solve(diff(f, x), x)[0]
result = nsimplify(x_opt)   # a/2
print(result)

Problem: What is the electronic configuration of Iron?
Output: CANNOT_EVALUATE
"""


# ── Data class ─────────────────────────────────────────────────────────

class SympyResult:
    """Holds a verified answer from SymPy execution."""

    def __init__(self, answer: str, is_integer: bool = False):
        self.answer = answer        # e.g. "8", "4*sqrt(2)", "45.0"
        self.is_integer = is_integer  # True when answer is a clean whole number

    def __repr__(self) -> str:
        return f"SympyResult(answer={self.answer!r}, is_integer={self.is_integer})"


# ── Safety helpers ─────────────────────────────────────────────────────

def _is_safe_ast(code: str) -> bool:
    """
    AST-level safety gate.

    Returns True only when:
    • All import statements reference allowed modules.
    • No dangerous builtin names are called directly.
    """
    try:
        tree = ast.parse(code)
    except SyntaxError:
        return False

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                top = alias.name.split(".")[0]
                if top not in _ALLOWED_IMPORTS:
                    log.warning("sympy_verifier.blocked_import  module=%s", alias.name)
                    return False

        elif isinstance(node, ast.ImportFrom):
            top = (node.module or "").split(".")[0]
            if top not in _ALLOWED_IMPORTS:
                log.warning("sympy_verifier.blocked_from_import  module=%s", node.module)
                return False

        elif isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name) and node.func.id in _DANGEROUS_BUILTINS:
                log.warning("sympy_verifier.blocked_builtin_call  name=%s", node.func.id)
                return False

    return True


# ── Sandbox execution ─────────────────────────────────────────────────

def _execute_sympy_sync(code: str) -> Optional[str]:
    """
    Execute SymPy code inside a restricted sandbox.

    Returns the last non-empty printed line (the final answer), or None on any error.
    Must be called inside a ThreadPoolExecutor — it is synchronous and CPU-bound.
    """
    if not _is_safe_ast(code):
        return None

    import cmath as _cmath
    import decimal as _decimal
    import fractions as _fractions
    import math as _math
    import builtins as _real_builtins

    import sympy

    # Restricted __import__: Python's `from X import Y` syntax compiles to
    # __import__('X', ...).  We must provide it in __builtins__ or every
    # `from sympy import ...` line raises ImportError at runtime.
    # We allow only the whitelisted modules — the AST gate already validated
    # the import statements, this is a defence-in-depth runtime check.
    _real_import = _real_builtins.__import__
    def _restricted_import(name, globals=None, locals=None, fromlist=(), level=0):
        top = name.split(".")[0]
        if top not in _ALLOWED_IMPORTS:
            raise ImportError(f"import of '{top}' is blocked in sandbox")
        return _real_import(name, globals, locals, fromlist, level)

    # Minimal safe builtins
    safe_builtins: dict = {
        "__import__": _restricted_import,   # needed for `from X import Y`
        "print": print,
        "abs": abs, "round": round, "min": min, "max": max,
        "len": len, "range": range, "enumerate": enumerate, "zip": zip,
        "int": int, "float": float, "str": str, "bool": bool,
        "list": list, "tuple": tuple, "dict": dict, "set": set,
        "True": True, "False": False, "None": None,
        "sum": sum, "map": map, "filter": filter, "sorted": sorted,
        "isinstance": isinstance, "type": type, "hasattr": hasattr,
        "ValueError": ValueError, "TypeError": TypeError,
        "NotImplementedError": NotImplementedError,
    }

    sandbox: dict = {
        "__builtins__": safe_builtins,
        "sympy": sympy,
        "math": _math,
        "cmath": _cmath,
        "fractions": _fractions,
        "decimal": _decimal,
    }

    # Inject all top-level SymPy names (symbols, log, sqrt, pi, oo, …)
    for _name in dir(sympy):
        if not _name.startswith("_"):
            sandbox[_name] = getattr(sympy, _name)

    stdout_buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(stdout_buf):
            exec(  # noqa: S102
                compile(code, "<sympy_sandbox>", "exec"),
                sandbox,
            )
        output = stdout_buf.getvalue().strip()
        if not output:
            # Fallback: model may have used a variable name other than 'result'
            # Check common alternatives in the order most likely to be the answer
            for _varname in ("result", "answer", "ans", "res", "value", "output", "val"):
                _v = sandbox.get(_varname)
                if _v is not None:
                    _s = str(_v).strip()
                    if _s and _s not in ("None", ""):
                        output = _s
                        log.debug("sympy_verifier.used_var  name=%s", _varname)
                        break
        if not output:
            return None
        # Last non-empty line = final answer
        lines = [ln.strip() for ln in output.splitlines() if ln.strip()]
        return lines[-1] if lines else None

    except Exception as exc:
        log.info(
            "sympy_verifier.exec_exception  type=%s  msg=%s",
            type(exc).__name__, exc,
        )
        return None


# ── Public API ─────────────────────────────────────────────────────────

async def verify_with_sympy(question_text: str) -> Optional[SympyResult]:
    """
    Main entry point.  Never raises — all errors return None.

    Steps:
    1. Call the fast LLM (8B) to translate question_text → SymPy Python code.
    2. AST-safety-check the generated code.
    3. Execute in a sandboxed ThreadPoolExecutor thread.
    4. Parse and clean the printed output into a SympyResult.

    Returns None for:
    • Conceptual / theory questions (CANNOT_EVALUATE from LLM)
    • LLM translation timeout / error
    • AST safety check failure
    • SymPy execution error or timeout
    • Empty output
    """
    s = get_settings()

    # ── Step 1: LLM translation ─────────────────────────────────────
    try:
        resp = await asyncio.wait_for(
            acompletion(
                model=f"openai/{s.LLM_FAST_MODEL}",
                api_base=s.LLM_BASE_URL,
                api_key=s.LLM_API_KEY,
                messages=[
                    {"role": "system", "content": _TRANSLATE_SYSTEM_PROMPT},
                    {"role": "user",   "content": question_text},
                ],
                max_tokens=500,
                temperature=0.0,
            ),
            timeout=_LLM_TRANSLATE_TIMEOUT_S,
        )
    except asyncio.TimeoutError:
        log.info("sympy_verifier.llm_timeout")
        return None
    except Exception as exc:
        log.info("sympy_verifier.llm_error  error=%s", exc)
        return None

    code = resp.choices[0].message.content.strip()

    # Strip markdown fences even if model ignores the instruction
    code = re.sub(r"^```(?:python)?\s*\n?", "", code, flags=re.MULTILINE)
    code = re.sub(r"\n?```\s*$", "", code, flags=re.MULTILINE)
    code = code.strip()

    if not code or "CANNOT_EVALUATE" in code:
        log.info("sympy_verifier.cannot_evaluate")
        return None

    log.info("sympy_verifier.code  chars=%d  preview=%.200s", len(code), code)

    # ── Step 2: Sandboxed execution ─────────────────────────────────
    loop = asyncio.get_running_loop()
    try:
        raw: Optional[str] = await asyncio.wait_for(
            loop.run_in_executor(_SYMPY_EXECUTOR, _execute_sympy_sync, code),
            timeout=_SYMPY_EXEC_TIMEOUT_S,
        )
    except asyncio.TimeoutError:
        log.info("sympy_verifier.exec_timeout")
        return None
    except Exception as exc:
        log.info("sympy_verifier.exec_error  error=%s", exc)
        return None

    if not raw:
        log.info("sympy_verifier.no_output")
        return None

    answer = raw.strip()

    # Reject answers that are guesses, not SymPy computations.
    import re as _re
    # (a) Single MCQ option letter: A / B / C / D / (A) / a. etc.
    if _re.match(r'^\(?[A-Da-d][.):]?\)?$', answer):
        log.info("sympy_verifier.option_letter_rejected  answer=%s", answer)
        return None
    # (b) Multi-word plain-English phrase: no digits, no math operators.
    #     e.g. "Van der Waals forces", "H-bond", "ionic bond".
    #     Real SymPy results: numbers, symbolic exprs, or single tokens (pi, oo).
    if ' ' in answer and _re.match(r'^[A-Za-z][\w\s\-\']*$', answer):
        log.info("sympy_verifier.string_guess_rejected  answer=%.80s", answer)
        return None

    # Normalise floats that are actually integers (8.0 → 8, -3.0 → -3)
    is_integer = False
    try:
        fval = float(answer)
        if abs(fval) < 1e15 and fval == int(fval):
            answer = str(int(fval))
            is_integer = True
    except (ValueError, OverflowError):
        pass  # symbolic result like "4*sqrt(2)" — keep as-is

    # Sanity guard: reject implausibly large or obviously broken strings
    if len(answer) > 120:
        log.info("sympy_verifier.answer_too_long  len=%d", len(answer))
        return None

    log.info("sympy_verifier.success  answer=%s  is_integer=%s", answer, is_integer)
    return SympyResult(answer=answer, is_integer=is_integer)


# ── CrewAI tool wrapper ───────────────────────────────────────────────
# Wraps verify_with_sympy() as a synchronous BaseTool for use inside CrewAI
# agents (Verifier Agent).  Runs the async function in a new event loop.

from crewai.tools import BaseTool  # noqa: E402
from pydantic import BaseModel, Field as PydanticField  # noqa: E402


class SymPyVerifierInput(BaseModel):
    question_text: str = PydanticField(
        ...,
        description=(
            "The math/physics/chemistry problem text to verify. "
            "Include all numerical values and options if an MCQ."
        ),
    )


class SymPyVerifierTool(BaseTool):
    """
    Verify a JEE/NEET math or physics answer using SymPy.

    Translates the problem into SymPy code via LLM, executes it in a sandbox,
    and returns the computed answer or CANNOT_EVALUATE for conceptual problems.
    """

    name: str = "SymPy Verifier Tool"
    description: str = (
        "Verify a numerical or algebraic answer by translating the problem into "
        "executable SymPy Python code and running it in a secure sandbox. "
        "Returns the computed ground-truth answer, or CANNOT_EVALUATE if the "
        "problem is conceptual or cannot be solved symbolically."
    )
    args_schema: type[BaseModel] = SymPyVerifierInput

    def _run(self, question_text: str) -> str:
        import asyncio as _asyncio
        loop = _asyncio.new_event_loop()
        try:
            result: Optional[SympyResult] = loop.run_until_complete(
                verify_with_sympy(question_text)
            )
        finally:
            loop.close()

        if result is None:
            return "CANNOT_EVALUATE"
        return f"VERIFIED_ANSWER: {result.answer}"


# Instantiated tool — imported by agents.py
sympy_verifier_tool = SymPyVerifierTool()
