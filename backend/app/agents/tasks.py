"""
CrewAI task definitions for the AI Tutoring platform.

All tasks use {placeholder} syntax in their descriptions so values can be
injected at runtime via crew.kickoff(inputs={...}).

Factory functions accept the pre-built Agent and optional context tasks
(whose output is forwarded as context to the next task in a pipeline).

Nightly batch pipeline:
    diagnostic_task → planning_task → monitor_task
    (optional) → mock_test_task

On-demand pipeline:
    question_task → verification_task
"""

from __future__ import annotations

from crewai import Agent, Task


# ── Nightly batch tasks ───────────────────────────────────────────────

def make_diagnostic_task(agent: Agent) -> Task:
    """
    Analyse quiz history for one student and produce a weak-topic report.

    Placeholders: {student_id}
    """
    return Task(
        description=(
            "Analyse the quiz history for student {student_id} over the last 7 days.\n"
            "Steps:\n"
            "1. Use quiz_history_tool(student_id='{student_id}', days=7) to fetch answers.\n"
            "2. Use rag_search_tool to map each weak topic to its JEE/NEET syllabus chapter.\n"
            "3. A topic is 'weak' if accuracy < 50% across at least 3 attempts.\n"
            "Return ONLY valid JSON — no prose outside the JSON object."
        ),
        expected_output=(
            "A JSON object with this exact schema:\n"
            "{\n"
            '  "student_id": "<uuid>",\n'
            '  "weak_topics": [\n'
            '    {"topic": "Newton\'s Laws", "accuracy_pct": 33.3, "attempts": 6, '
            '"syllabus_chapter": "Laws of Motion"}\n'
            "  ],\n"
            '  "strong_topics": [\n'
            '    {"topic": "Kinematics", "accuracy_pct": 85.0, "attempts": 12}\n'
            "  ]\n"
            "}"
        ),
        agent=agent,
    )


def make_planning_task(agent: Agent, context_tasks: list[Task]) -> Task:
    """
    Build a 7-day study plan from the diagnostic output.

    Placeholders: {student_id}, {plan_date}
    Requires: diagnostic_task output in context.
    """
    return Task(
        description=(
            "Based on the diagnostic analysis in context, create a 7-day study plan "
            "for student {student_id} starting {plan_date}.\n"
            "Rules:\n"
            "- Prioritise weak topics (accuracy < 50%) with higher daily duration.\n"
            "- Apply SM-2 spaced repetition: revisit each weak topic every 2–3 days.\n"
            "- Each day should have 2–3 topic slots totalling 90–120 minutes.\n"
            "- Use write_plan_tool to persist each day's plan.\n"
            "CRITICAL: Always use specific, real topic names (e.g. 'Newton\\'s Laws', "
            "'Geometric Progression', 'Chemical Bonding'). "
            "NEVER use generic placeholder names like 'Weak Topic 1', 'Topic 2', "
            "'Weak Area 3', or any numbered placeholder. "
            "If no weak topics are identified from quiz history, assign high-yield "
            "JEE/NEET chapters appropriate for the student's exam target.\n"
            "Return ONLY valid JSON — no prose outside the JSON object."
        ),
        expected_output=(
            "A JSON object with this exact schema:\n"
            "{\n"
            '  "student_id": "<uuid>",\n'
            '  "plan_start_date": "YYYY-MM-DD",\n'
            '  "days": [\n'
            "    {\n"
            '      "date": "YYYY-MM-DD",\n'
            '      "topics": [\n'
            '        {"topic": "Newton\'s Laws", "duration_min": 45, "priority": 1}\n'
            "      ]\n"
            "    }\n"
            "  ]\n"
            "}"
        ),
        agent=agent,
        context=context_tasks,
    )


def make_monitor_task(
    agent: Agent,
    context_tasks: list[Task],
) -> Task:
    """
    Detect plateaus and send WhatsApp alerts where needed.

    Placeholders: {student_id}, {phone_number}, {language}
    Requires: diagnostic_task output in context.
    """
    return Task(
        description=(
            "Monitor progress for student {student_id}.\n"
            "Steps:\n"
            "1. Use progress_read_tool(student_id='{student_id}', days=7) to detect plateaus.\n"
            "2. If plateaus are found, use whatsapp_tool to send an alert to {phone_number} "
            "in the student's language ({language}).\n"
            "3. The alert must be warm, encouraging, and under 160 characters.\n"
            "Return ONLY valid JSON — no prose outside the JSON object."
        ),
        expected_output=(
            "A JSON object with this exact schema:\n"
            "{\n"
            '  "student_id": "<uuid>",\n'
            '  "plateaus_detected": [\n'
            '    {"topic": "Newton\'s Laws", "consecutive_weak_days": 4}\n'
            "  ],\n"
            '  "alerts_sent": [\n'
            '    {"to": "919876543210", "topic": "Newton\'s Laws", "status": "sent"}\n'
            "  ]\n"
            "}"
        ),
        agent=agent,
        context=context_tasks,
    )


# ── On-demand task ────────────────────────────────────────────────────

def make_question_task(agent: Agent) -> Task:
    """
    Answer a student's question with RAG context.

    Placeholders: {question}, {student_id}, {language}, {weak_topics}, {exam_context}
    """
    return Task(
        description=(
            "A student (ID: {student_id}) has asked: {question}\n"
            "Exam context: {exam_context}\n"
            "Student's weak topics (supplementary context only): {weak_topics}\n"
            "\n"
            "CRITICAL RULE: Your response MUST address the student's EXACT question — '{question}'.\n"
            "Do NOT silently pivot to a different topic just because it appears in the weak topics list.\n"
            "\n"
            "Steps:\n"
            "1. Classify the question into exactly ONE of three types:\n"
            "   - MCQ PROBLEM: the question already contains numbered or lettered answer options\n"
            "     (e.g., '1) ... 2) ... 3) ... 4) ...' or 'A) ... B) ...'). This is the type\n"
            "     when the student has photographed a textbook MCQ and wants to know the answer.\n"
            "   - ACADEMIC TOPIC: a specific concept, chapter, formula, or problem type WITHOUT\n"
            "     pre-supplied options (e.g., 'explain Newton's second law', 'solve this integral').\n"
            "   - META QUERY: a question about an exam, course, or syllabus overview\n"
            "     (e.g., 'NEET course', 'JEE syllabus', 'what subjects are in WBCHSE').\n"
            "2. Use rag_search_tool to retrieve the top 5 chunks most relevant to '{question}'.\n"
            "   Use those chunks to support your explanation.\n"
            "3a. If MCQ PROBLEM:\n"
            "    - Solve the problem from first principles, step by step.\n"
            "    - CRITICAL — OCR text from images often drops fraction bars. Re-read every\n"
            "      option with this lens before matching: 'H N' → H/N, 'H 2√2' → H/(2√2),\n"
            "      'H √2' → H/√2, '2 √2' → 2√2, etc.\n"
            "    - Evaluate EACH option explicitly against your derived answer and identify\n"
            "      which one matches.\n"
            "    - Start your explanation with 'Correct Answer: Option <N> — <corrected option>'\n"
            "      (e.g., 'Correct Answer: Option 3 — h = H/2').\n"
            "    - Then give a concise step-by-step solution explaining WHY that option is correct\n"
            "      and briefly state why each other option is wrong.\n"
            "    - In practice_problems, echo the original question as problem 1 with\n"
            "      answer set to the correct option string.\n"
            "3b. If ACADEMIC TOPIC: write a clear explanation of that topic, a worked example,\n"
            "    and two practice problems. If the topic also appears in the student's weak topics\n"
            "    ({weak_topics}), add extra depth and highlight common mistakes.\n"
            "3c. If META QUERY: give a concise, accurate overview of the exam/course the student\n"
            "    asked about (subjects covered, question format, duration, marking scheme).\n"
            "    Then include one warm practice problem from the student's most relevant weak topic\n"
            "    to keep them engaged.\n"
            "4. Respond in {language} — simple language for a Class 11-12 student.\n"
            "5. Format practice problems per the exam context (question_type, marks, marking_scheme).\n"
            "Return ONLY valid JSON — no prose outside the JSON object."
        ),
        expected_output=(
            "A JSON object with this exact schema:\n"
            "{\n"
            '  "explanation": "...",\n'
            '  "worked_example": "...",\n'
            '  "practice_problems": [\n'
            '    {\n'
            '      "question": "...",\n'
            '      "answer": "...",\n'
            '      "question_type": "MCQ",\n'
            '      "marks": 4,\n'
            '      "marking_scheme": "+4/-1"\n'
            '    }\n'
            "  ],\n"
            '  "topic": "topic name",\n'
            '  "subject": "subject name",\n'
            '  "question_type": "MCQ",\n'
            '  "marks": 4,\n'
            '  "marking_scheme": "+4/-1"\n'
            "}"
        ),
        agent=agent,
    )


# ── Verification task (follows question_task in QuestionCrew) ─────────

def make_verification_task(agent: Agent, context_tasks: list[Task]) -> Task:
    """
    Verify the tutor's answer with SymPy.

    Placeholders: {question}
    Requires: question_task output in context.
    """
    return Task(
        description=(
            "Verify the tutor's draft answer for the following question:\n"
            "{question}\n\n"
            "The tutor's answer is available in the context from the previous task.\n"
            "Use SymPy Verifier Tool with the original question text to compute the "
            "ground-truth answer.\n"
            "Compare SymPy's result to the tutor's stated answer.\n"
            "Return exactly one of:\n"
            "  APPROVED\n"
            "  APPROVED (unverifiable, trust tutor)\n"
            "  CORRECTION: <brief explanation of what is wrong and the correct answer>\n"
            "Output ONLY the above — no other prose, no JSON wrapper."
        ),
        expected_output=(
            "Exactly one of:\n"
            "  APPROVED\n"
            "  APPROVED (unverifiable, trust tutor)\n"
            "  CORRECTION: <explanation>"
        ),
        agent=agent,
        context=context_tasks,
    )


# ── Mock test analyst task ─────────────────────────────────────────────

def make_mock_test_task(agent: Agent, context_tasks: list[Task] | None = None) -> Task:
    """
    Analyse a completed mock test attempt and update the study plan.

    Placeholders: {student_id}, {attempt_id}, {plan_date}
    """
    return Task(
        description=(
            "Analyse the mock test attempt for student {student_id}.\n"
            "Attempt ID: {attempt_id}\n"
            "Plan start date for updated schedule: {plan_date}\n\n"
            "Goal: identify weak subjects and topics from this attempt and update the "
            "student's study plan to prioritise revision of those areas.\n\n"
            "Steps:\n"
            "1. Call Mock Test Analysis Tool with student_id='{student_id}' "
            "and attempt_id='{attempt_id}'.\n"
            "2. Identify subjects where accuracy_pct < 60% and topics where "
            "accuracy_pct < 50% (with ≥ 2 questions attempted).\n"
            "3. Call Write Plan Tool to add extra revision sessions for weak areas.\n"
            "4. Return ONLY the JSON summary described in expected_output."
        ),
        expected_output=(
            "A JSON object with this exact schema:\n"
            "{\n"
            '  "student_id": "<uuid>",\n'
            '  "attempt_id": "<uuid>",\n'
            '  "weakest_subject": "Physics",\n'
            '  "weakest_topics": ["Newton\'s Laws", "Thermodynamics"],\n'
            '  "plan_updated": true,\n'
            '  "skipped_count": 5,\n'
            '  "avg_time_per_question_s": 72.4\n'
            "}"
        ),
        agent=agent,
        context=context_tasks or [],
    )
