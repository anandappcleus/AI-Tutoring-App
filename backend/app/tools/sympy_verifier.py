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

STRICT RULES
1. Import ONLY from: sympy, math, cmath, fractions, decimal
2. The LAST statement must assign to `result` and then: print(result)
3. Use sympy.nsimplify() on the final value — gives exact symbolic form.
   Use sympy.N(expr, 10) only when you need a decimal approximation.
4. Logarithm syntax: sympy.log(x, base)  e.g. log(9, 2) = log₂(9)
5. CRITICAL — log-exponent identity: for ((expr)^k)^(1/log_b(expr)), set u = expr,
   compute u**(k / log(u, b)) using sympy directly — DO NOT expand expr first.
6. For MCQ: compute only the numerical value. Do NOT pick an option letter.
7. For physics word problems: set up equations symbolically, substitute, solve.
8. For stoichiometry: use sympy.Matrix row-reduction to balance equations.
9. Strip any markdown code fences from your output.
10. If the problem is ANY of:
      • conceptual / theory ("explain", "describe", "what is", "why", "state", "define")
      • organic chemistry mechanisms or named reactions
      • asking to draw / label a diagram
      • subjective / essay style
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
from sympy import symbols, log, solve, nsimplify
# NEVER do solve(3**x - 4**(x-1), x) — SymPy cannot solve transcendental eqs.
# Instead take ln of both sides to get a LINEAR equation in x:
# x*ln3 = (x-1)*ln4  =>  x*(ln3 - ln4) = -ln4  =>  x = ln4/(ln4-ln3)
x = symbols('x')
eq = x * log(3) - (x - 1) * log(4)
result = nsimplify(solve(eq, x)[0])
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

Problem: Explain Newton's third law.
Output: CANNOT_EVALUATE

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

    import sympy

    # Minimal safe builtins — no open, no eval, no exec, no __import__
    safe_builtins: dict = {
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
