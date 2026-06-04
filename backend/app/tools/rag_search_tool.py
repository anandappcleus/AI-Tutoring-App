"""
RAG Search Tool — CrewAI tool wrapping the enhanced hybrid retriever.

Enhancements over the original:
  • HyDE query rewriting — conceptual queries are rewritten to a hypothetical
    passage before embedding, improving recall for "explain X" style questions.
  • Cross-encoder re-ranking — NIM nv-rerankqa-mistral-4b-v3 re-scores the
    top-20 hybrid results and returns the top top_k.
  • Metadata filtering — agents can pass exam_type / subject to restrict
    retrieval to the relevant corpus slice (e.g. JEE Physics only).

Used by:
    Question Generator Agent  — fetch relevant JEE/NEET content for a student question
    Diagnostic Agent          — map wrong answers back to syllabus topics

The tool is a singleton: the retriever is initialised once and reused across
agent tasks in the same process to avoid redundant Chroma connections.
"""

from __future__ import annotations

import asyncio
import logging
import time

from crewai.tools import BaseTool
from pydantic import BaseModel, Field

from app.rag.retriever import BaseRetriever, get_retriever

log = logging.getLogger(__name__)

_retriever: BaseRetriever | None = None
_retriever_unavailable: bool = False


def _get_retriever() -> BaseRetriever | None:
    """Return the singleton retriever, or None if chroma is unavailable."""
    global _retriever, _retriever_unavailable
    if _retriever_unavailable:
        return None
    if _retriever is None:
        try:
            _retriever = get_retriever()
        except Exception as exc:
            _retriever_unavailable = True
            log.warning(
                "rag_search_tool: retriever unavailable — RAG context disabled  error=%s",
                exc,
            )
            return None
    return _retriever


# ── Input schema ──────────────────────────────────────────────────────

class RAGSearchInput(BaseModel):
    query: str = Field(
        ...,
        description=(
            "Search query — can be in English, Bengali, Hindi, or any Indian language. "
            "Example: 'Newton second law of motion' or 'নিউটনের দ্বিতীয় সূত্র'"
        ),
    )
    top_k: int = Field(
        5,
        ge=1,
        le=20,
        description="Number of relevant chunks to return (default 5, max 20).",
    )
    exam_type: str | None = Field(
        None,
        description=(
            "Optional exam filter: 'JEE' | 'NEET' | 'WBCHSE'. "
            "When set, restricts retrieval to corpus chunks tagged for this exam. "
            "Pass the student's exam_target here for best results."
        ),
    )
    subject: str | None = Field(
        None,
        description=(
            "Optional subject filter: 'physics' | 'chemistry' | 'mathematics' | 'biology'. "
            "When set, restricts retrieval to the matching subject slice of the corpus."
        ),
    )


# ── Tool ──────────────────────────────────────────────────────────────

class RAGSearchTool(BaseTool):
    """Search the JEE/NEET/WBCHSE knowledge base with hybrid retrieval + re-ranking."""

    name: str = "RAG Search Tool"
    description: str = (
        "Search the JEE/NEET/WBCHSE syllabus and past paper knowledge base. "
        "Uses hybrid dense+BM25 retrieval with cross-encoder re-ranking. "
        "Returns the most relevant text passages along with their source file, "
        "page number, subject tag, and relevance score. "
        "Optionally filter by exam_type (JEE/NEET/WBCHSE) and subject. "
        "Use this tool before generating any explanation or practice problem."
    )
    args_schema: type[BaseModel] = RAGSearchInput

    def _run(
        self,
        query: str,
        top_k: int = 5,
        exam_type: str | None = None,
        subject: str | None = None,
    ) -> list[dict]:
        t_total = time.perf_counter()
        log.info(
            "rag_search_tool.start  query=%r  top_k=%d  exam=%s  subject=%s",
            query[:80], top_k, exam_type, subject,
        )
        retriever = _get_retriever()
        if retriever is None:
            log.warning("rag_search_tool: retriever unavailable — returning empty")
            return []

        # ── HyDE: rewrite conceptual queries to a hypothetical passage ─
        retrieval_query = query
        hyde_ms = 0.0
        try:
            from app.rag.query_rewriter import get_query_rewriter
            rewriter = get_query_rewriter()
            # Run the async rewriter synchronously from the (sync) CrewAI tool context
            t_hyde = time.perf_counter()
            loop = asyncio.new_event_loop()
            try:
                retrieval_query = loop.run_until_complete(
                    rewriter.rewrite(query, exam_type=exam_type or "JEE", subject=subject)
                )
            finally:
                loop.close()
            hyde_ms = (time.perf_counter() - t_hyde) * 1_000
            rewritten = retrieval_query != query
            log.debug(
                "rag_search_tool.hyde  rewritten=%s  hyde_ms=%.0f",
                rewritten, hyde_ms,
            )
        except Exception as exc:
            log.warning("rag_search_tool: hyde rewrite skipped  error=%s", exc)

        # ── Hybrid retrieval (dense + BM25 + RRF, with metadata filter) ─
        # Fetch top-20 candidates for the re-ranker to work from.
        fetch_k = min(top_k * 4, 20)
        t_retrieval = time.perf_counter()
        try:
            chunks = retriever.search(
                retrieval_query,
                top_k=fetch_k,
                exam_filter=exam_type,
                subject_filter=subject,
            )
        except Exception:
            log.error("rag_search_tool.retrieval_failed  query=%r", query[:80], exc_info=True)
            return []
        retrieval_ms = (time.perf_counter() - t_retrieval) * 1_000

        if not chunks:
            log.info(
                "rag_search_tool.no_results  query=%r  exam=%s  subject=%s"
                "  retrieval_ms=%.0f",
                query[:80], exam_type, subject, retrieval_ms,
            )
            return []

        # ── Cross-encoder re-ranking ───────────────────────────────────
        rerank_ms = 0.0
        t_rerank = time.perf_counter()
        try:
            from app.rag.reranker import get_reranker
            reranker = get_reranker()
            chunks = reranker.rerank(query, chunks, top_k=top_k)
        except Exception as exc:
            log.warning(
                "rag_search_tool.reranker_skipped  error=%s  using_raw_order_top_%d",
                exc, top_k,
            )
            chunks = chunks[:top_k]
        rerank_ms = (time.perf_counter() - t_rerank) * 1_000

        total_ms = (time.perf_counter() - t_total) * 1_000
        top_score = chunks[0].get("score", 0.0) if chunks else 0.0
        log.info(
            "rag_search_tool.done  query=%r  exam=%s  subject=%s"
            "  returned=%d  top_score=%.3f"
            "  hyde_ms=%.0f  retrieval_ms=%.0f  rerank_ms=%.0f  total_ms=%.0f",
            query[:80], exam_type, subject,
            len(chunks), top_score,
            hyde_ms, retrieval_ms, rerank_ms, total_ms,
        )
        return chunks


# Instantiated tool — imported by agents.py
rag_search_tool = RAGSearchTool()
