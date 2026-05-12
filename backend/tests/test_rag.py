"""
Sprint 2 — RAG pipeline tests

Tests:
    Unit tests (no API calls, no Chroma on disk):
        test_chunk_text_*         — chunker logic
        test_infer_subject_*      — filename → subject tag
        test_chunk_id_determinism — same inputs → same ID
        test_prompts_*            — multilingual prompt output

    Integration tests (require NIM API key + PDFs — skipped in CI):
        test_embed_query_shape    — NIM returns embedding of correct dimension
        test_retriever_search_*   — Chroma round-trip (embed + store + search)

Run unit tests only (no network, no disk):
    pytest tests/test_rag.py -v -m "not integration"

Run all tests (requires .env with NIM key and at least one PDF ingested):
    pytest tests/test_rag.py -v
"""

from __future__ import annotations

import hashlib
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

# ── helpers from ingest ───────────────────────────────────────────────
from app.rag.ingest import (
    CHUNK_CHARS,
    MIN_CHUNK_CHARS,
    OVERLAP_CHARS,
    _chunk_id,
    _chunk_text,
    _infer_subject,
)
from app.agents.prompts import (
    LANGUAGE_NAMES,
    get_monitor_alert,
    get_tutor_prompt,
)


# ─────────────────────────────────────────────────────────────────────
# Chunker unit tests
# ─────────────────────────────────────────────────────────────────────

class TestChunkText:
    def test_short_text_returns_single_chunk(self):
        text = "A" * 100
        chunks = _chunk_text(text)
        assert len(chunks) == 1

    def test_long_text_produces_multiple_chunks(self):
        # 3× chunk size should yield at least 3 chunks
        text = "W " * (CHUNK_CHARS * 3 // 2)
        chunks = _chunk_text(text)
        assert len(chunks) >= 3

    def test_chunk_max_length(self):
        text = "X" * (CHUNK_CHARS * 5)
        for chunk in _chunk_text(text):
            assert len(chunk) <= CHUNK_CHARS

    def test_overlap_content(self):
        # The tail of chunk[n] should appear at the start of chunk[n+1]
        text = "T" * (CHUNK_CHARS + OVERLAP_CHARS + 100)
        chunks = _chunk_text(text)
        if len(chunks) >= 2:
            tail = chunks[0][-OVERLAP_CHARS:]
            head = chunks[1][:OVERLAP_CHARS]
            assert tail == head

    def test_tiny_chunks_discarded(self):
        # A single very short string below MIN_CHUNK_CHARS should be discarded
        text = "Hi"
        chunks = _chunk_text(text)
        assert chunks == []

    def test_empty_string_returns_empty(self):
        assert _chunk_text("") == []


# ─────────────────────────────────────────────────────────────────────
# Subject inference unit tests
# ─────────────────────────────────────────────────────────────────────

class TestInferSubject:
    @pytest.mark.parametrize(
        "filename, expected",
        [
            ("jee_physics_2023.pdf", "physics"),
            ("WBCHSE_Chemistry_Paper.pdf", "chemistry"),
            ("maths_practice.pdf", "maths"),
            ("neet_biology_2022.pdf", "biology"),
            ("unknown_file.pdf", "general"),
        ],
    )
    def test_infer_subject_from_filename(self, filename, expected):
        assert _infer_subject(Path(filename)) == expected


# ─────────────────────────────────────────────────────────────────────
# Chunk ID determinism
# ─────────────────────────────────────────────────────────────────────

class TestChunkId:
    def test_same_inputs_same_id(self):
        id1 = _chunk_id("file.pdf", 3, 1)
        id2 = _chunk_id("file.pdf", 3, 1)
        assert id1 == id2

    def test_different_page_different_id(self):
        assert _chunk_id("file.pdf", 1, 0) != _chunk_id("file.pdf", 2, 0)

    def test_different_index_different_id(self):
        assert _chunk_id("file.pdf", 1, 0) != _chunk_id("file.pdf", 1, 1)

    def test_id_is_md5_hex(self):
        chunk_id = _chunk_id("file.pdf", 1, 0)
        # MD5 hex is 32 chars
        assert len(chunk_id) == 32
        assert all(c in "0123456789abcdef" for c in chunk_id)


# ─────────────────────────────────────────────────────────────────────
# Multilingual prompts unit tests
# ─────────────────────────────────────────────────────────────────────

class TestPrompts:
    @pytest.mark.parametrize("lang_code", list(LANGUAGE_NAMES.keys()))
    def test_tutor_prompt_mentions_language(self, lang_code):
        prompt = get_tutor_prompt(lang_code)
        lang_name = LANGUAGE_NAMES[lang_code]
        assert lang_name in prompt

    def test_tutor_prompt_requires_json_output(self):
        prompt = get_tutor_prompt("en")
        assert "JSON" in prompt
        assert "explanation" in prompt
        assert "practice_problems" in prompt

    def test_unknown_lang_falls_back_to_english(self):
        prompt = get_tutor_prompt("xx")
        assert "English" in prompt

    @pytest.mark.parametrize("lang_code", ["bn", "hi", "ta", "te", "mr", "en"])
    def test_monitor_alert_under_160_chars(self, lang_code):
        alert = get_monitor_alert(lang_code, "Kinematics")
        assert len(alert) <= 160

    @pytest.mark.parametrize("lang_code", ["bn", "hi", "ta", "te", "mr", "en"])
    def test_monitor_alert_contains_topic(self, lang_code):
        alert = get_monitor_alert(lang_code, "Thermodynamics")
        assert "Thermodynamics" in alert


# ─────────────────────────────────────────────────────────────────────
# Integration tests — skipped unless --run-integration flag or marker
# ─────────────────────────────────────────────────────────────────────

@pytest.mark.integration
class TestEmbedderIntegration:
    """Requires NIM API key in .env. Run with: pytest -m integration"""

    def test_embed_query_returns_vector(self):
        from app.rag.embedder import Embedder

        embedder = Embedder()
        vec = embedder.embed_query("Newton's second law")
        assert isinstance(vec, list)
        assert len(vec) > 100  # nv-embedqa-e5-v5 returns 1024-dim vectors
        assert all(isinstance(v, float) for v in vec)

    def test_embed_passages_batch(self):
        from app.rag.embedder import Embedder

        embedder = Embedder()
        texts = ["Force equals mass times acceleration.", "Energy is conserved."]
        vecs = embedder.embed_passages(texts)
        assert len(vecs) == 2
        assert len(vecs[0]) == len(vecs[1])  # same dimension


@pytest.mark.integration
class TestRetrieverIntegration:
    """
    Requires:
        - NIM API key in .env
        - At least one PDF ingested (python -m app.rag.ingest --dir rag/corpus/)
    """

    def test_search_returns_chunks(self):
        from app.rag.retriever import ChromaRetriever

        retriever = ChromaRetriever()
        if retriever.count() == 0:
            pytest.skip("Chroma collection is empty — ingest PDFs first")

        chunks = retriever.search("Newton second law of motion", top_k=3)
        assert len(chunks) <= 3
        assert all("text" in c for c in chunks)
        assert all("score" in c for c in chunks)
        assert all(0.0 <= c["score"] <= 1.0 for c in chunks)

    def test_search_bengali_query(self):
        from app.rag.retriever import ChromaRetriever

        retriever = ChromaRetriever()
        if retriever.count() == 0:
            pytest.skip("Chroma collection is empty — ingest PDFs first")

        chunks = retriever.search("নিউটনের দ্বিতীয় সূত্র", top_k=5)
        # Bengali query should still return results (multilingual embedding model)
        assert isinstance(chunks, list)

    def test_search_score_ordering(self):
        from app.rag.retriever import ChromaRetriever

        retriever = ChromaRetriever()
        if retriever.count() == 0:
            pytest.skip("Chroma collection is empty — ingest PDFs first")

        chunks = retriever.search("kinetic energy formula", top_k=5)
        scores = [c["score"] for c in chunks]
        # Scores should be in descending order
        assert scores == sorted(scores, reverse=True)
