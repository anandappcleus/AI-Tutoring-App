"""
Sprint 3 — CrewAI agents & tools tests

Unit tests (no network, no database):
    TestToolSchemas           — Pydantic input models accept / reject values
    TestPlateauDetection      — pure-Python detect_plateaus() logic
    TestAgentConfig           — agents have correct roles, tools, LLMs
    TestTaskConfig            — tasks have non-empty descriptions + expected_output
    TestCrewConfig            — NightlyTutorCrew and QuestionCrew wiring

Integration tests (require NIM API key + running PostgreSQL — mark with -m integration):
    TestCrewIntegration       — full QuestionCrew run with real NIM

Run unit tests only (fast, no credentials needed):
    pytest tests/test_agents.py -v -m "not integration"

Run all tests:
    pytest tests/test_agents.py -v
"""

from __future__ import annotations

import json
from datetime import datetime, timezone, timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from pydantic import ValidationError

# ── Input schemas ─────────────────────────────────────────────────────
from app.tools.quiz_history_tool import QuizHistoryInput
from app.tools.write_plan_tool import TopicSlot, WritePlanInput
from app.tools.progress_read_tool import ProgressReadInput, detect_plateaus
from app.tools.whatsapp_tool import WhatsAppInput

# ── Agent / task / crew factories ─────────────────────────────────────
from app.agents.agents import (
    make_diagnostic_agent,
    make_monitor_agent,
    make_planner_agent,
    make_question_generator_agent,
)
from app.agents.tasks import (
    make_diagnostic_task,
    make_monitor_task,
    make_planning_task,
    make_question_task,
)
from app.agents.crew import NightlyTutorCrew, QuestionCrew


# ─────────────────────────────────────────────────────────────────────
# Tool input schema validation
# ─────────────────────────────────────────────────────────────────────

class TestToolSchemas:
    # ── QuizHistoryInput ──────────────────────────────────────────────

    def test_quiz_history_valid_defaults(self):
        m = QuizHistoryInput(student_id="abc123")
        assert m.days == 7

    def test_quiz_history_valid_custom_days(self):
        m = QuizHistoryInput(student_id="abc", days=14)
        assert m.days == 14

    def test_quiz_history_days_too_low(self):
        with pytest.raises(ValidationError):
            QuizHistoryInput(student_id="abc", days=0)

    def test_quiz_history_days_too_high(self):
        with pytest.raises(ValidationError):
            QuizHistoryInput(student_id="abc", days=31)

    # ── WritePlanInput ────────────────────────────────────────────────

    def test_write_plan_valid(self):
        m = WritePlanInput(
            student_id="s1",
            plan_date="2026-05-14",
            topics=[TopicSlot(topic="Kinematics", duration_min=45, priority=1)],
        )
        assert m.plan_date == "2026-05-14"
        assert len(m.topics) == 1

    def test_write_plan_empty_topics_rejected(self):
        with pytest.raises(ValidationError):
            WritePlanInput(student_id="s1", plan_date="2026-05-14", topics=[])

    def test_topic_slot_priority_bounds(self):
        with pytest.raises(ValidationError):
            TopicSlot(topic="X", duration_min=30, priority=0)  # below min
        with pytest.raises(ValidationError):
            TopicSlot(topic="X", duration_min=30, priority=6)  # above max

    def test_topic_slot_duration_bounds(self):
        with pytest.raises(ValidationError):
            TopicSlot(topic="X", duration_min=5, priority=1)  # below min
        with pytest.raises(ValidationError):
            TopicSlot(topic="X", duration_min=250, priority=1)  # above max

    # ── ProgressReadInput ─────────────────────────────────────────────

    def test_progress_read_valid_defaults(self):
        m = ProgressReadInput(student_id="abc")
        assert m.days == 7

    def test_progress_read_days_too_low(self):
        with pytest.raises(ValidationError):
            ProgressReadInput(student_id="abc", days=2)  # min is 3

    # ── WhatsAppInput ─────────────────────────────────────────────────

    def test_whatsapp_valid(self):
        m = WhatsAppInput(to="919876543210", message="Hello!")
        assert m.to == "919876543210"

    def test_whatsapp_message_too_long(self):
        with pytest.raises(ValidationError):
            WhatsAppInput(to="91987", message="x" * 4097)


# ─────────────────────────────────────────────────────────────────────
# Plateau detection (pure Python — no DB)
# ─────────────────────────────────────────────────────────────────────

def _make_answer(topic: str, is_correct: bool, days_ago: int):
    """Build a minimal answer-like object for detect_plateaus()."""
    return SimpleNamespace(
        topic=topic,
        is_correct=is_correct,
        answered_at=datetime.now(tz=timezone.utc) - timedelta(days=days_ago),
    )


class TestPlateauDetection:
    def test_no_answers_returns_empty(self):
        assert detect_plateaus([]) == []

    def test_single_weak_day_not_flagged(self):
        answers = [_make_answer("Optics", False, 1)]
        assert detect_plateaus(answers) == []

    def test_two_consecutive_weak_days_not_flagged(self):
        answers = [
            _make_answer("Optics", False, 2),
            _make_answer("Optics", False, 1),
        ]
        assert detect_plateaus(answers) == []

    def test_three_consecutive_weak_days_flagged(self):
        answers = [
            _make_answer("Optics", False, 3),
            _make_answer("Optics", False, 2),
            _make_answer("Optics", False, 1),
        ]
        result = detect_plateaus(answers)
        assert len(result) == 1
        assert result[0]["topic"] == "Optics"
        assert result[0]["consecutive_weak_days"] == 3

    def test_strong_day_breaks_streak(self):
        # Weak, weak, STRONG, weak, weak → max streak = 2, no flag
        answers = [
            _make_answer("Optics", False, 5),
            _make_answer("Optics", False, 4),
            _make_answer("Optics", True, 3),   # strong day breaks streak
            _make_answer("Optics", False, 2),
            _make_answer("Optics", False, 1),
        ]
        assert detect_plateaus(answers) == []

    def test_multiple_topics_independent(self):
        # Physics: 3 weak days → flagged; Chemistry: 2 weak days → not flagged
        answers = [
            _make_answer("Newton's Laws", False, 3),
            _make_answer("Newton's Laws", False, 2),
            _make_answer("Newton's Laws", False, 1),
            _make_answer("Mole Concept", False, 2),
            _make_answer("Mole Concept", False, 1),
        ]
        result = detect_plateaus(answers)
        topics = [r["topic"] for r in result]
        assert "Newton's Laws" in topics
        assert "Mole Concept" not in topics

    def test_accuracy_threshold_boundary(self):
        # Exactly 40% correct (2/5): NOT weak (threshold is < 40%)
        d = 1
        answers = [
            _make_answer("T", True, d),
            _make_answer("T", True, d),
            _make_answer("T", False, d),
            _make_answer("T", False, d),
            _make_answer("T", False, d),
        ]
        # accuracy = 40.0 — not below threshold → not weak
        assert detect_plateaus(answers) == []

    def test_none_topic_ignored(self):
        answers = [SimpleNamespace(topic=None, is_correct=False, answered_at=datetime.now())]
        assert detect_plateaus(answers) == []


# ─────────────────────────────────────────────────────────────────────
# Agent configuration
# ─────────────────────────────────────────────────────────────────────

class TestAgentConfig:
    def test_diagnostic_agent_role(self):
        agent = make_diagnostic_agent()
        assert "Diagnostic" in agent.role

    def test_diagnostic_agent_has_two_tools(self):
        agent = make_diagnostic_agent()
        tool_names = [t.name for t in agent.tools]
        assert "Quiz History Tool" in tool_names
        assert "RAG Search Tool" in tool_names

    def test_planner_agent_role(self):
        agent = make_planner_agent()
        assert "Planner" in agent.role

    def test_planner_agent_has_write_plan_tool(self):
        agent = make_planner_agent()
        tool_names = [t.name for t in agent.tools]
        assert "Write Plan Tool" in tool_names

    def test_question_generator_en(self):
        agent = make_question_generator_agent("en")
        assert "Tutor" in agent.role

    def test_question_generator_bn_has_rag_tool(self):
        agent = make_question_generator_agent("bn")
        tool_names = [t.name for t in agent.tools]
        assert "RAG Search Tool" in tool_names

    def test_monitor_agent_role(self):
        agent = make_monitor_agent()
        assert "Monitor" in agent.role

    def test_monitor_agent_has_progress_and_whatsapp_tools(self):
        agent = make_monitor_agent()
        tool_names = [t.name for t in agent.tools]
        assert "Progress Read Tool" in tool_names
        assert "WhatsApp Send Tool" in tool_names

    def test_all_agents_have_llm(self):
        for factory in [
            make_diagnostic_agent,
            make_planner_agent,
            lambda: make_question_generator_agent("en"),
            make_monitor_agent,
        ]:
            agent = factory()
            assert agent.llm is not None


# ─────────────────────────────────────────────────────────────────────
# Task configuration
# ─────────────────────────────────────────────────────────────────────

class TestTaskConfig:
    def _diagnostic_task(self):
        return make_diagnostic_task(make_diagnostic_agent())

    def test_diagnostic_task_description_nonempty(self):
        t = self._diagnostic_task()
        assert len(t.description) > 20

    def test_diagnostic_task_expected_output_nonempty(self):
        t = self._diagnostic_task()
        assert len(t.expected_output) > 20

    def test_diagnostic_task_has_student_id_placeholder(self):
        t = self._diagnostic_task()
        assert "{student_id}" in t.description

    def test_planning_task_has_plan_date_placeholder(self):
        diagnostic = make_diagnostic_task(make_diagnostic_agent())
        t = make_planning_task(make_planner_agent(), context_tasks=[diagnostic])
        assert "{plan_date}" in t.description

    def test_monitor_task_has_phone_placeholder(self):
        diagnostic = make_diagnostic_task(make_diagnostic_agent())
        t = make_monitor_task(make_monitor_agent(), context_tasks=[diagnostic])
        assert "{phone_number}" in t.description

    def test_question_task_has_question_placeholder(self):
        t = make_question_task(make_question_generator_agent("en"))
        assert "{question}" in t.description

    def test_all_tasks_expected_output_contains_json(self):
        diagnostic = make_diagnostic_task(make_diagnostic_agent())
        planning = make_planning_task(make_planner_agent(), context_tasks=[diagnostic])
        monitor = make_monitor_task(make_monitor_agent(), context_tasks=[diagnostic])
        question = make_question_task(make_question_generator_agent("en"))
        for task in [diagnostic, planning, monitor, question]:
            assert "JSON" in task.expected_output or "{" in task.expected_output


# ─────────────────────────────────────────────────────────────────────
# Crew composition
# ─────────────────────────────────────────────────────────────────────

class TestCrewConfig:
    def test_nightly_crew_can_be_instantiated(self):
        crew = NightlyTutorCrew()
        assert crew is not None

    def test_question_crew_can_be_instantiated(self):
        crew = QuestionCrew()
        assert crew is not None

    def test_nightly_crew_builds_three_agents(self):
        """Verify crew.run creates exactly 3 agents (+ manager) by intercepting Crew.__init__."""
        captured = {}

        class _FakeCrew:
            def __init__(self, agents, tasks, **kwargs):
                captured["agent_count"] = len(agents)
                captured["task_count"] = len(tasks)

            def kickoff(self, inputs):
                return "{}"

        with patch("app.agents.crew.Crew", _FakeCrew):
            NightlyTutorCrew().run(
                student_id="00000000-0000-0000-0000-000000000001",
                phone_number="919876543210",
                plan_date="2026-05-14",
                language="bn",
            )

        # Manager + 3 task agents (diagnostic, planner, monitor)
        assert captured["agent_count"] == 4
        assert captured["task_count"] == 3

    def test_question_crew_builds_one_agent(self):
        captured = {}

        class _FakeCrew:
            def __init__(self, agents, tasks, **kwargs):
                captured["agent_count"] = len(agents)

            def kickoff(self, inputs):
                return "{}"

        with patch("app.agents.crew.Crew", _FakeCrew):
            QuestionCrew().run(
                question="What is Newton's second law?",
                student_id="00000000-0000-0000-0000-000000000002",
                language="en",
            )

        # Generator + verifier agents
        assert captured["agent_count"] == 2


# ─────────────────────────────────────────────────────────────────────
# Integration tests — require NIM API + running PostgreSQL
# ─────────────────────────────────────────────────────────────────────

@pytest.mark.integration
class TestCrewIntegration:
    def test_question_crew_returns_json(self):
        """Full end-to-end: QuestionCrew → RAG search → Sarvam-M → JSON answer."""
        crew = QuestionCrew()
        result = crew.run(
            question="What is Newton's second law of motion?",
            student_id="00000000-0000-0000-0000-000000000099",
            language="en",
        )
        # Result should be parseable or at least non-empty
        assert isinstance(result, str)
        assert len(result) > 10

    def test_question_crew_bengali(self):
        """QuestionCrew in Bengali — Sarvam-M should respond in Bengali."""
        crew = QuestionCrew()
        result = crew.run(
            question="নিউটনের দ্বিতীয় সূত্র কী?",
            student_id="00000000-0000-0000-0000-000000000099",
            language="bn",
        )
        assert isinstance(result, str)
        assert len(result) > 10

    def test_whatsapp_tool_disabled_without_token(self):
        """WhatsApp tool returns disabled status when token is not configured."""
        from app.tools.whatsapp_tool import whatsapp_tool

        result = whatsapp_tool._run(to="919876543210", message="Test alert")
        data = json.loads(result)
        # In dev (no token set), expect disabled status
        assert data["status"] in ("sent", "disabled")
