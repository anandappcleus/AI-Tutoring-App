"""
HyDE (Hypothetical Document Embeddings) query rewriter.

HyDE improves retrieval quality for factual/conceptual questions by replacing
the raw student question with a *hypothetical* textbook passage that would
answer it.  The embedding of a well-formed answer sentence is closer to real
corpus chunks than the embedding of a short question fragment.

Reference: Gao et al. 2022 — "Precise Zero-Shot Dense Retrieval without
Relevance Labels"  (https://arxiv.org/abs/2212.10496)

Design:
  • Uses the fast 8B model (LLM_FAST_MODEL) for low-latency generation.
  • Hard 3-second wall-clock timeout — falls back to the original query on any
    failure (timeout, LLM error, empty response).
  • Skipped for purely numeric / "solve" queries where the question embedding
    is already close to worked-solution passages in the corpus.
  • Singleton pattern: one QueryRewriter instance reused across requests.
"""

from __future__ import annotations

import asyncio
import logging
import re
import time

from litellm import acompletion

from app.config import get_settings

log = logging.getLogger(__name__)

# Patterns that indicate a numeric/procedural question — skip HyDE for these
# because the question itself is a good query (it contains the formula / values).
_SKIP_PATTERNS = re.compile(
    r"\b(solve|calculate|find the value|compute|evaluate|differentiate|integrate"
    r"|simplify|prove that|if .{0,30}= .{0,30}find)\b",
    re.IGNORECASE,
)

_HYDE_SYSTEM_PROMPT = (
    "You are a JEE/NEET textbook author. Given a student question, write a single "
    "2-sentence textbook passage (in English) that directly answers it. "
    "Use precise academic language, include any relevant formula or law name, "
    "and match the style of NCERT or HC Verma. Output ONLY the passage — no preamble."
)

_HYDE_TIMEOUT_S = 3.0


class QueryRewriter:
    """
    Rewrites a student query into a hypothetical answer passage for better RAG
    retrieval (HyDE strategy).

    Usage::

        rewriter = QueryRewriter()
        rewritten = await rewriter.rewrite("What is Newton's second law?", exam_type="JEE")
        # returns a textbook-style passage embedding target
    """

    async def rewrite(
        self,
        query: str,
        exam_type: str = "JEE",
        subject: str | None = None,
    ) -> str:
        """
        Return a hypothetical passage for retrieval, or the original query on failure.

        Args:
            query:      The student's original question text.
            exam_type:  "JEE" | "NEET" | "WBCHSE" — included in context hint.
            subject:    Optional subject hint (e.g. "Physics") for targeted HyDE.

        Returns:
            A hypothetical textbook passage string, or the original query string.
        """
        s = get_settings()
        if not s.HYDE_ENABLED:
            log.debug("hyde: disabled via HYDE_ENABLED=False  query=%r", query[:60])
            return query

        # Skip HyDE for numeric/solve queries
        if _SKIP_PATTERNS.search(query):
            log.info(
                "hyde: skip  reason=numeric_or_procedural  query=%r",
                query[:80],
            )
            return query

        subject_hint = f" ({subject})" if subject else ""
        user_msg = (
            f"Exam: {exam_type}{subject_hint}\n"
            f"Student question: {query}\n\n"
            "Write the 2-sentence textbook passage:"
        )

        t0 = time.perf_counter()
        try:
            response = await asyncio.wait_for(
                acompletion(
                    model=f"openai/{s.LLM_FAST_MODEL}",
                    api_base=s.LLM_BASE_URL,
                    api_key=s.LLM_API_KEY,
                    messages=[
                        {"role": "system", "content": _HYDE_SYSTEM_PROMPT},
                        {"role": "user", "content": user_msg},
                    ],
                    max_tokens=120,
                    temperature=0.3,
                ),
                timeout=_HYDE_TIMEOUT_S,
            )
            elapsed_ms = (time.perf_counter() - t0) * 1_000
            passage = response.choices[0].message.content.strip()
            if passage:
                log.info(
                    "hyde: rewrite_ok  exam=%s  subject=%s  elapsed_ms=%.0f"
                    "  query=%r  passage_chars=%d  passage=%r",
                    exam_type, subject, elapsed_ms,
                    query[:60], len(passage), passage[:100],
                )
                return passage
            log.warning(
                "hyde: empty_response  model=%s  elapsed_ms=%.0f  query=%r"
                "  — falling back to original query",
                s.LLM_FAST_MODEL, elapsed_ms, query[:60],
            )
        except asyncio.TimeoutError:
            elapsed_ms = (time.perf_counter() - t0) * 1_000
            log.warning(
                "hyde: timeout  model=%s  timeout_s=%.1f  elapsed_ms=%.0f  query=%r"
                "  — falling back to original query",
                s.LLM_FAST_MODEL, _HYDE_TIMEOUT_S, elapsed_ms, query[:60],
            )
        except Exception as exc:
            elapsed_ms = (time.perf_counter() - t0) * 1_000
            log.warning(
                "hyde: error  model=%s  elapsed_ms=%.0f  error=%s  query=%r"
                "  — falling back to original query",
                s.LLM_FAST_MODEL, elapsed_ms, exc, query[:60],
            )

        return query


# ── Module-level singleton ────────────────────────────────────────────

_rewriter: QueryRewriter | None = None


def get_query_rewriter() -> QueryRewriter:
    global _rewriter
    if _rewriter is None:
        _rewriter = QueryRewriter()
    return _rewriter
