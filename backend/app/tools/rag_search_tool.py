"""
RAG Search Tool — CrewAI tool wrapping the Chroma/Pinecone retriever.

Used by:
    Question Generator Agent  — fetch relevant JEE/NEET content for a student question
    Diagnostic Agent          — map wrong answers back to syllabus topics (syllabus_map_tool)

The tool is a singleton: the retriever is initialised once and reused across
agent tasks in the same process to avoid redundant Chroma connections.
"""

from __future__ import annotations

import logging

from crewai.tools import BaseTool
from pydantic import BaseModel, Field

from app.rag.retriever import BaseRetriever, get_retriever

log = logging.getLogger(__name__)

_retriever: BaseRetriever | None = None


def _get_retriever() -> BaseRetriever:
    global _retriever
    if _retriever is None:
        _retriever = get_retriever()
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


# ── Tool ──────────────────────────────────────────────────────────────

class RAGSearchTool(BaseTool):
    """Search the JEE/NEET/WBCHSE knowledge base for relevant content chunks."""

    name: str = "RAG Search Tool"
    description: str = (
        "Search the JEE/NEET/WBCHSE syllabus and past paper knowledge base. "
        "Returns the most relevant text passages along with their source file, "
        "page number, subject tag, and relevance score. "
        "Use this tool before generating any explanation or practice problem."
    )
    args_schema: type[BaseModel] = RAGSearchInput

    def _run(self, query: str, top_k: int = 5) -> list[dict]:
        log.debug("rag_search_tool  query=%r  top_k=%d", query[:80], top_k)
        try:
            retriever = _get_retriever()
            chunks = retriever.search(query, top_k=top_k)
        except Exception:
            log.error("rag_search_tool failed  query=%r", query[:80], exc_info=True)
            raise
        log.info(
            "rag_search_tool  returned %d chunks  top_score=%.3f",
            len(chunks),
            chunks[0]["score"] if chunks else 0.0,
        )
        return chunks


# Instantiated tool — imported by agents.py
rag_search_tool = RAGSearchTool()
