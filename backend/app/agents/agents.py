"""
CrewAI agent definitions for the AI Tutoring platform.

Agents:
    diagnostic_agent          — reads quiz history + maps topics via RAG
    curriculum_planner_agent  — builds 7-day study plans using SM-2
    question_generator_agent  — answers student questions in their language
    progress_monitor_agent    — detects plateaus + sends WhatsApp alerts
    verifier_agent            — NEW: cross-checks tutor answers with SymPy
    manager_agent             — NEW: hierarchical crew orchestrator (no tools)
    mock_test_analyst_agent   — NEW: analyses completed mock test attempts

LLM routing (via .env):
    LLM_AGENT_MODEL  → Qwen3-235B on NIM (dev) / GPT-4o mini (prod)
    LLM_CHAT_MODEL   → Sarvam-M on NIM (dev)  / GPT-4o mini (prod)

Factory functions create fresh Agent instances per crew run so that
agent memory state doesn't bleed between students in nightly batches.
"""

from __future__ import annotations

import logging

from crewai import Agent, LLM

from app.agents.prompts import (
    get_diagnostic_prompt,
    get_manager_prompt,
    get_mock_test_analyst_prompt,
    get_monitor_prompt,
    get_planner_prompt,
    get_tutor_prompt,
    get_verifier_prompt,
)
from app.config import get_settings
from app.tools.mock_test_analysis_tool import mock_test_analysis_tool
from app.tools.progress_read_tool import progress_read_tool
from app.tools.quiz_history_tool import quiz_history_tool
from app.tools.rag_search_tool import rag_search_tool
from app.tools.sympy_verifier import sympy_verifier_tool
from app.tools.whatsapp_tool import whatsapp_tool
from app.tools.write_plan_tool import write_plan_tool

log = logging.getLogger(__name__)


def _make_llms() -> tuple[LLM, LLM]:
    """Return (agent_llm, indic_llm) configured from settings."""
    s = get_settings()
    agent_llm = LLM(
        model=f"openai/{s.LLM_AGENT_MODEL}",
        api_key=s.LLM_API_KEY,
        base_url=s.LLM_BASE_URL,
    )
    indic_llm = LLM(
        model=f"openai/{s.LLM_CHAT_MODEL}",
        api_key=s.LLM_API_KEY,
        base_url=s.LLM_BASE_URL,
    )
    return agent_llm, indic_llm


def make_diagnostic_agent() -> Agent:
    """Analyse quiz history to identify weak topics and map them to the syllabus."""
    agent_llm, _ = _make_llms()
    log.debug("agents.make_diagnostic_agent  model=%s", agent_llm.model)
    return Agent(
        role="Diagnostic Analyst",
        goal=(
            "Analyse a student's quiz history to accurately identify weak topics "
            "and map them to the JEE/NEET/WBCHSE syllabus."
        ),
        backstory=(
            "You are an expert educational diagnostician with 10 years of experience "
            "analysing student performance data. You are precise and data-driven — "
            "you only flag a topic as weak when the evidence clearly supports it."
        ),
        llm=agent_llm,
        tools=[quiz_history_tool, rag_search_tool],
        system_prompt=get_diagnostic_prompt(),
        verbose=False,
    )


def make_planner_agent() -> Agent:
    """Build spaced-repetition study plans targeting the student's weakest topics."""
    agent_llm, _ = _make_llms()
    log.debug("agents.make_planner_agent  model=%s", agent_llm.model)
    return Agent(
        role="Curriculum Planner",
        goal=(
            "Create an optimal 7-day study schedule that targets weak topics first, "
            "using spaced repetition (SM-2) to maximise long-term retention."
        ),
        backstory=(
            "You are an expert curriculum planner who designs personalised study plans "
            "for competitive exam aspirants. You prioritise weak topics while maintaining "
            "regular revision of stronger topics to prevent forgetting."
        ),
        llm=agent_llm,
        tools=[write_plan_tool],
        system_prompt=get_planner_prompt(),
        verbose=False,
    )


def make_question_generator_agent(lang_code: str = "en") -> Agent:
    """Answer student questions in their native language using RAG context.

    Model routing:
      English → agent_llm (llama-3.3-70b) — reliable structured JSON output.
      Indic   → indic_llm (sarvam-m)       — native Indic language support.
    """
    agent_llm, indic_llm = _make_llms()
    # llama-3.3-70b follows JSON formatting instructions reliably; sarvam-m (thinking
    # model) sometimes outputs pure reasoning without a JSON Final Answer.
    llm = indic_llm if lang_code != "en" else agent_llm
    log.debug(
        "agents.make_question_generator_agent  model=%s  lang=%s",
        llm.model,
        lang_code,
    )
    return Agent(
        role="Expert JEE/NEET Tutor",
        goal=(
            "Answer student questions clearly and accurately, "
            "using the JEE/NEET knowledge base to provide curriculum-aligned explanations."
        ),
        backstory=(
            "You are a brilliant, patient tutor specialising in JEE, NEET, and WBCHSE "
            "exam preparation. You explain complex concepts in the student's native language "
            "using simple analogies and step-by-step reasoning."
        ),
        llm=llm,
        tools=[rag_search_tool],
        system_prompt=get_tutor_prompt(lang_code),
        verbose=False,
    )


def make_monitor_agent() -> Agent:
    """Detect plateauing students and send WhatsApp alerts."""
    agent_llm, _ = _make_llms()
    log.debug("agents.make_monitor_agent  model=%s", agent_llm.model)
    return Agent(
        role="Progress Monitor",
        goal=(
            "Detect students who are plateauing on specific topics and "
            "send timely, encouraging alerts to help them break through."
        ),
        backstory=(
            "You are a caring progress coach who watches over every student's learning journey. "
            "When you detect a student has been stuck on the same topic for 3 or more days, "
            "you reach out proactively with encouragement and targeted advice."
        ),
        llm=agent_llm,
        tools=[progress_read_tool, whatsapp_tool],
        system_prompt=get_monitor_prompt(),
        verbose=False,
    )


# ── New agents ────────────────────────────────────────────────────────


def make_verifier_agent() -> Agent:
    """
    Verify tutor answers mathematically using SymPy.

    The Verifier Agent receives the Tutor Agent's output and the original
    question, then runs SymPy to confirm numeric answers or flag corrections.
    Returns APPROVED or CORRECTION: <diff>.
    """
    agent_llm, _ = _make_llms()
    log.debug("agents.make_verifier_agent  model=%s", agent_llm.model)
    return Agent(
        role="Answer Verifier",
        goal=(
            "Verify that the tutor's answer is mathematically correct by "
            "running SymPy on the original question. Return APPROVED or "
            "CORRECTION: <what is wrong and what the correct answer is>."
        ),
        backstory=(
            "You are a meticulous math checker who catches calculation errors before "
            "they reach students. You trust SymPy's symbolic computation over intuition "
            "and always double-check numeric answers."
        ),
        llm=agent_llm,
        tools=[sympy_verifier_tool],
        system_prompt=get_verifier_prompt(),
        verbose=False,
    )


def make_manager_agent() -> Agent:
    """
    Hierarchical crew manager — orchestrates nightly batch tasks.

    The Manager Agent has NO tools. It reads the output of each sub-agent
    and decides the next step: skip tasks when data is absent, re-run when
    output is malformed, or escalate when a student's situation is urgent.
    """
    agent_llm, _ = _make_llms()
    log.debug("agents.make_manager_agent  model=%s", agent_llm.model)
    return Agent(
        role="Crew Manager",
        goal=(
            "Orchestrate the nightly tutoring crew for maximum impact. "
            "Decide which tasks to execute, skip, or re-run based on available data. "
            "Ensure every student gets a personalised plan and only receives WhatsApp "
            "alerts when a genuine plateau is detected."
        ),
        backstory=(
            "You are an experienced educational programme manager who coordinates a team of "
            "AI tutors, planners, and monitors. You make efficient decisions — you skip the "
            "monitor task when there are no quiz answers yet, and you skip planning when the "
            "diagnostic found no weak topics. You validate JSON outputs before passing them "
            "downstream and request a retry when they are malformed."
        ),
        llm=agent_llm,
        tools=[],  # Manager uses no tools — only coordinates sub-agents
        system_prompt=get_manager_prompt(),
        verbose=False,
        allow_delegation=True,
    )


def make_mock_test_analyst_agent() -> Agent:
    """
    Analyse a student's completed mock test attempt.

    Extracts subject-level accuracy, topic weaknesses, time management stats,
    and skipped question count. Updates the study plan via WritePlanTool.
    """
    agent_llm, _ = _make_llms()
    log.debug("agents.make_mock_test_analyst_agent  model=%s", agent_llm.model)
    return Agent(
        role="Mock Test Analyst",
        goal=(
            "Analyse the student's most recent mock test attempt, identify the weakest "
            "subjects and topics, and update their study plan to address these gaps."
        ),
        backstory=(
            "You are a competitive exam coach who specialises in mock test analysis. "
            "You extract actionable insights from score data — not just what went wrong, "
            "but why (time pressure, weak topics, careless errors) — and translate those "
            "insights into a targeted revision plan."
        ),
        llm=agent_llm,
        tools=[mock_test_analysis_tool, write_plan_tool],
        system_prompt=get_mock_test_analyst_prompt(),
        verbose=False,
    )
