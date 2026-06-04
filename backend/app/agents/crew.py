"""
CrewAI crew definitions for the AI Tutoring platform.

Two crews:

NightlyTutorCrew
    Hierarchical: Manager orchestrates diagnostic → planning → monitor
    (+ optional Mock Test Analyst when recent attempt available)
    Run once per student during the nightly APScheduler job.
    inputs: student_id, phone_number, plan_date, language,
            recent_attempt_id (optional)

QuestionCrew
    Sequential: question_generator → verifier
    Run per-request from POST /ask.
    inputs: question, student_id, language
"""

from __future__ import annotations

import logging
import time

from crewai import Crew, Process

from app.agents.agents import (
    make_diagnostic_agent,
    make_manager_agent,
    make_mock_test_analyst_agent,
    make_monitor_agent,
    make_planner_agent,
    make_question_generator_agent,
    make_verifier_agent,
)
from app.agents.tasks import (
    make_diagnostic_task,
    make_mock_test_task,
    make_monitor_task,
    make_planning_task,
    make_question_task,
    make_verification_task,
)
from app.config import get_settings


log = logging.getLogger(__name__)


class NightlyTutorCrew:
    """
    Runs the full diagnostic / planning / monitoring cycle for one student.

    The crew uses hierarchical process with a Manager Agent that orchestrates
    when to run (or skip) each sub-agent.

    Usage::

        crew = NightlyTutorCrew()
        result = crew.run(
            student_id="...",
            phone_number="919876543210",
            plan_date="2026-05-14",
            language="bn",
            recent_attempt_id="...",   # optional
        )
    """

    def run(
        self,
        student_id: str,
        phone_number: str,
        plan_date: str,
        language: str = "en",
        recent_attempt_id: str | None = None,
    ) -> str:
        log.info(
            "NightlyTutorCrew.run  student_id=%s  plan_date=%s  lang=%s  attempt=%s",
            student_id,
            plan_date,
            language,
            recent_attempt_id or "none",
        )
        s = get_settings()

        # ── Build agents ───────────────────────────────────────────────
        manager_agent = make_manager_agent()
        diagnostic_agent = make_diagnostic_agent()
        planner_agent = make_planner_agent()
        monitor_agent = make_monitor_agent()

        # ── Build tasks ────────────────────────────────────────────────
        diagnostic_task = make_diagnostic_task(diagnostic_agent)
        planning_task = make_planning_task(planner_agent, context_tasks=[diagnostic_task])
        monitor_task = make_monitor_task(monitor_agent, context_tasks=[diagnostic_task])

        agents = [manager_agent, diagnostic_agent, planner_agent, monitor_agent]
        tasks = [diagnostic_task, planning_task, monitor_task]

        # Conditionally include Mock Test Analyst
        if recent_attempt_id:
            analyst_agent = make_mock_test_analyst_agent()
            mock_task = make_mock_test_task(analyst_agent, context_tasks=[diagnostic_task])
            agents.append(analyst_agent)
            tasks.append(mock_task)

        # ── Build crew ─────────────────────────────────────────────────
        crew = Crew(
            agents=agents,
            tasks=tasks,
            process=Process.hierarchical,
            manager_agent=manager_agent,
            memory=True,
            embedder={
                "provider": "openai",
                "config": {
                    "model": s.EMBED_MODEL,
                    "api_key": s.LLM_API_KEY,
                    "base_url": s.LLM_BASE_URL,
                },
            },
            verbose=False,
        )

        result = crew.kickoff(
            inputs={
                "student_id": student_id,
                "phone_number": phone_number,
                "plan_date": plan_date,
                "language": language,
                "attempt_id": recent_attempt_id or "",
            }
        )
        log.info("NightlyTutorCrew.run  complete  student_id=%s", student_id)
        return str(result)


class QuestionCrew:
    """
    On-demand crew for answering a student question with optional SymPy verification.

    Pipeline: question_generator → verifier (if SYMPY_VERIFY_ENABLED)

    Usage::

        crew = QuestionCrew()
        answer_json = crew.run(
            question="নিউটনের দ্বিতীয় সূত্র কী?",
            student_id="...",
            language="bn",
        )
    """

    # Exam-type → context string injected into the task prompt
    _EXAM_CONTEXTS: dict[str, str] = {
        "JEE": (
            "JEE Mains/Advanced style. Choose MCQ (4 marks, -1 wrong) or "
            "Integer-type (4 marks, 0 for wrong). Set question_type to 'MCQ' or "
            "'Integer', marks to 4, marking_scheme to '+4/-1' or '+4/0'."
        ),
        "NEET": (
            "NEET UG style. Use MCQ only (4 marks, -1 for wrong answer). "
            "Set question_type='MCQ', marks=4, marking_scheme='+4/-1'."
        ),
        "WBCHSE": (
            "WBCHSE Board style. Use Short Answer (2-3 marks) or Long Answer (5 marks), "
            "no negative marking. Set question_type to 'Short Answer' or 'Long Answer', "
            "marks accordingly, marking_scheme='no negative marking'."
        ),
    }

    def run(
        self,
        question: str,
        student_id: str,
        language: str = "en",
        weak_topics: list[str] | None = None,
        exam_type: str | None = None,
    ) -> str:
        log.info(
            "QuestionCrew.run  student_id=%s  lang=%s  exam=%s  q=%r",
            student_id,
            language,
            exam_type or "general",
            question[:80],
        )

        generator_agent = make_question_generator_agent(lang_code=language)
        question_task = make_question_task(generator_agent)

        verifier_agent = make_verifier_agent()
        verification_task = make_verification_task(
            verifier_agent, context_tasks=[question_task]
        )

        s = get_settings()
        crew = Crew(
            agents=[generator_agent, verifier_agent],
            tasks=[question_task, verification_task],
            process=Process.sequential,
            memory=True,
            embedder={
                "provider": "openai",
                "config": {
                    "model": s.EMBED_MODEL,
                    "api_key": s.LLM_API_KEY,
                    "base_url": s.LLM_BASE_URL,
                },
            },
            verbose=False,
        )

        weak_topics_str = ", ".join(weak_topics) if weak_topics else "none identified yet"
        exam_context = self._EXAM_CONTEXTS.get(
            exam_type or "",
            "General academic style. Use appropriate question_type (MCQ, Short Answer, etc.) "
            "and marks (2-4) for the topic.",
        )

        log.info(
            "QuestionCrew.kickoff  student_id=%s  agents=%d  tasks=%d"
            "  process=sequential  exam=%s",
            student_id, 2, 2, exam_type or "general",
        )

        t0 = time.perf_counter()
        result = crew.kickoff(
            inputs={
                "question": question,
                "student_id": student_id,
                "language": language,
                "weak_topics": weak_topics_str,
                "exam_context": exam_context,
            }
        )
        elapsed_ms = (time.perf_counter() - t0) * 1_000
        result_str = str(result)

        # Determine verifier verdict from result string
        if "APPROVED" in result_str.upper():
            verdict = "APPROVED"
        elif "CORRECTION" in result_str.upper() or "REVISED" in result_str.upper():
            verdict = "CORRECTION"
        else:
            verdict = "UNKNOWN"

        log.info(
            "QuestionCrew.done  student_id=%s  exam=%s  elapsed_ms=%.0f"
            "  verdict=%s  result_chars=%d",
            student_id, exam_type or "general", elapsed_ms,
            verdict, len(result_str),
        )
        return result_str
