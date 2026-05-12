"""
Multilingual system prompts for all CrewAI agents.

Rules:
- All prompts are language-aware: the student's preferred_language is passed in.
- Sarvam-M handles Bengali, Hindi, Marathi, Tamil, Telugu, Gujarati, Kannada,
  Malayalam, Odia, Punjabi natively.
- The RAG corpus is in English; the LLM reads English context and writes in the
  student's language.

Public API:
    get_tutor_prompt(lang_code)         → system prompt for Question Generator Agent
    get_monitor_alert(lang_code, topic) → WhatsApp alert text for Progress Monitor Agent
    LANGUAGE_NAMES                      → ISO 639-1 code → full language name
"""

from __future__ import annotations

# ISO 639-1 → display name (used inside prompts)
LANGUAGE_NAMES: dict[str, str] = {
    "bn": "Bengali",
    "hi": "Hindi",
    "ta": "Tamil",
    "te": "Telugu",
    "mr": "Marathi",
    "gu": "Gujarati",
    "kn": "Kannada",
    "ml": "Malayalam",
    "or": "Odia",
    "pa": "Punjabi",
    "en": "English",
}

_DEFAULT_LANG = "en"


def _lang_name(lang_code: str) -> str:
    return LANGUAGE_NAMES.get(lang_code, LANGUAGE_NAMES[_DEFAULT_LANG])


# ── Question Generator Agent prompt ───────────────────────────────────

def get_tutor_prompt(lang_code: str) -> str:
    """
    System prompt for the Question Generator Agent.

    Args:
        lang_code: ISO 639-1 language code (e.g. 'bn', 'hi', 'en')

    Returns:
        System prompt string instructing the LLM to respond in the student's language.
    """
    lang = _lang_name(lang_code)
    return (
        f"You are an expert JEE/NEET/WBCHSE tutor. "
        f"Always respond in {lang}. "
        f"Use clear, simple language suitable for a Class 11–12 student. "
        f"When given context passages from textbooks or past papers, use them to support "
        f"your explanation but do not copy text verbatim. "
        f"Always include: (1) a clear explanation, (2) a worked example, "
        f"(3) two practice problems with answers. "
        f"Format your response as JSON with keys: "
        f'"explanation", "worked_example", "practice_problems" (list of {{"question", "answer"}}).'
    )


# ── Diagnostic Agent prompt ───────────────────────────────────────────

def get_diagnostic_prompt() -> str:
    """
    System prompt for the Diagnostic Agent.
    Always responds in English (internal agent, no student-facing output).
    """
    return (
        "You are a diagnostic agent for an AI tutoring platform. "
        "Analyse student quiz history to identify weak and strong topics. "
        "Be precise: a topic is 'weak' only if the student has answered incorrectly "
        "more than 50% of the time in the last 7 days. "
        "Respond ONLY with valid JSON matching the schema provided in the task description. "
        "Do not include any prose outside the JSON."
    )


# ── Curriculum Planner Agent prompt ───────────────────────────────────

def get_planner_prompt() -> str:
    """
    System prompt for the Curriculum Planner Agent.
    Always responds in English (internal agent).
    """
    return (
        "You are a curriculum planner for JEE/NEET/WBCHSE students. "
        "Given a student's weak topics, build a 7-day study plan using the "
        "SM-2 spaced repetition algorithm. "
        "Prioritise topics with the lowest recent accuracy. "
        "Each day should have 2–3 topics, each with a recommended duration in minutes. "
        "Respond ONLY with valid JSON matching the schema provided in the task description."
    )


# ── Progress Monitor Agent prompt ─────────────────────────────────────

def get_monitor_prompt() -> str:
    """
    System prompt for the Progress Monitor Agent.
    Always responds in English for internal reasoning; alert text uses student's language.
    """
    return (
        "You are a progress monitor for an AI tutoring platform. "
        "Detect students who are plateauing: accuracy below 40% on the same topic "
        "for 3 or more consecutive days. "
        "For each flagged student, generate a motivating WhatsApp alert in their "
        "preferred language (provided in the task context). "
        "The alert must be warm, encouraging, and under 160 characters. "
        "Respond ONLY with valid JSON matching the schema provided in the task description."
    )


# ── WhatsApp alert template ───────────────────────────────────────────

def get_monitor_alert(lang_code: str, topic: str) -> str:
    """
    Ready-to-send WhatsApp alert for a student who has been stuck on a topic.

    Args:
        lang_code: Student's preferred language code
        topic:     The topic they are stuck on (in English)

    Returns:
        Short motivating message in the student's language (≤160 chars).
    """
    lang = _lang_name(lang_code)

    # The LLM will generate the actual message; this is a fallback template
    # used when the Progress Monitor Agent is unavailable.
    templates: dict[str, str] = {
        "bn": f"তুমি '{topic}' বিষয়ে কিছুটা আটকে আছো। আজ একটু বেশি সময় দাও — তুমি পারবে! 💪",
        "hi": f"'{topic}' में थोड़ी परेशानी हो रही है? आज थोड़ा और समय दो — तुम कर सकते हो! 💪",
        "ta": f"'{topic}' பாடத்தில் சிரமப்படுகிறீர்களா? இன்று கொஞ்சம் அதிகமாக படியுங்கள்! 💪",
        "te": f"'{topic}' పాఠంలో కష్టంగా ఉందా? ఈరోజు కొంచెం ఎక్కువగా చదవండి! 💪",
        "mr": f"'{topic}' मध्ये अडचण येतेय? आज थोडा जास्त वेळ द्या — तुम्ही नक्की करू शकता! 💪",
        "en": f"You've been stuck on '{topic}'. Give it a bit more time today — you've got this! 💪",
    }
    return templates.get(lang_code, templates["en"])
