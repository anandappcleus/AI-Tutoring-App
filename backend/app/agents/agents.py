"""
CrewAI agent definitions for the AI Tutoring platform.

Four agents:
    diagnostic_agent          — reads quiz history + maps topics via RAG
    curriculum_planner_agent  — builds 7-day study plans using SM-2
    question_generator_agent  — answers student questions in their language
    progress_monitor_agent    — detects plateaus + sends WhatsApp alerts

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
    get_monitor_prompt,
    get_planner_prompt,
    get_tutor_prompt,
)
from app.config import get_settings
from app.tools.progress_read_tool import progress_read_tool
from app.tools.quiz_history_tool import quiz_history_tool
from app.tools.rag_search_tool import rag_search_tool
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
    """Answer student questions in their native language using RAG context."""
    _, indic_llm = _make_llms()
    log.debug(
        "agents.make_question_generator_agent  model=%s  lang=%s",
        indic_llm.model,
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
        llm=indic_llm,
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
