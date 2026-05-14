"""
CrewAI crew definitions for the AI Tutoring platform.

Two crews:

NightlyTutorCrew
    Sequential: diagnostic → planning → monitor
    Run once per student during the nightly APScheduler job.
    inputs: student_id, phone_number, plan_date, language

QuestionCrew
    Single-agent: question_generator
    Run per-request from POST /ask.
    inputs: question, student_id, language
"""

from __future__ import annotations

import logging

from crewai import Crew, Process

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

log = logging.getLogger(__name__)


class NightlyTutorCrew:
    """
    Runs the full 4-agent diagnostic / planning / monitoring cycle for one student.

    Usage::

        crew = NightlyTutorCrew()
        result = crew.run(
            student_id="...",
            phone_number="919876543210",
            plan_date="2026-05-14",
            language="bn",
        )
    """

    def run(
        self,
        student_id: str,
        phone_number: str,
        plan_date: str,
        language: str = "en",
    ) -> str:
        log.info(
            "NightlyTutorCrew.run  student_id=%s  plan_date=%s  lang=%s",
            student_id,
            plan_date,
            language,
        )

        # Build fresh agents and tasks for each student run
        diagnostic_agent = make_diagnostic_agent()
        planner_agent = make_planner_agent()
        monitor_agent = make_monitor_agent()

        diagnostic_task = make_diagnostic_task(diagnostic_agent)
        planning_task = make_planning_task(planner_agent, context_tasks=[diagnostic_task])
        monitor_task = make_monitor_task(
            monitor_agent, context_tasks=[diagnostic_task]
        )

        crew = Crew(
            agents=[diagnostic_agent, planner_agent, monitor_agent],
            tasks=[diagnostic_task, planning_task, monitor_task],
            process=Process.sequential,
            verbose=False,
        )

        result = crew.kickoff(
            inputs={
                "student_id": student_id,
                "phone_number": phone_number,
                "plan_date": plan_date,
                "language": language,
            }
        )
        log.info("NightlyTutorCrew.run  complete  student_id=%s", student_id)
        return str(result)


class QuestionCrew:
    """
    On-demand single-agent crew for answering a student question.

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

        crew = Crew(
            agents=[generator_agent],
            tasks=[question_task],
            process=Process.sequential,
            verbose=False,
        )

        weak_topics_str = ", ".join(weak_topics) if weak_topics else "none identified yet"
        exam_context = self._EXAM_CONTEXTS.get(
            exam_type or "",
            "General academic style. Use appropriate question_type (MCQ, Short Answer, etc.) "
            "and marks (2-4) for the topic.",
        )
        result = crew.kickoff(
            inputs={
                "question": question,
                "student_id": student_id,
                "language": language,
                "weak_topics": weak_topics_str,
                "exam_context": exam_context,
            }
        )
        log.info("QuestionCrew.run  complete  student_id=%s", student_id)
        return str(result)
