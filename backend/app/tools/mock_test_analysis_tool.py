"""
Mock Test Analysis Tool — analyse a student's completed mock test attempt.

Used by:
    Mock Test Analyst Agent — extract per-subject accuracy, topic weaknesses,
    time management data, and skipped question count from a submitted attempt.

Returns a JSON dict with:
    student_id, attempt_id, paper_id, exam_type, submitted_at,
    total_score, max_score, accuracy_pct, time_taken_seconds,
    subject_breakdown  — per-subject {score, max, accuracy_pct, attempts, correct},
    topic_accuracy_map — per-topic {correct, total, accuracy_pct},
    avg_time_per_question_s,
    skipped_count
"""

from __future__ import annotations

import json
import logging
import uuid
from collections import defaultdict

from crewai.tools import BaseTool
from pydantic import BaseModel, Field
from sqlalchemy import select

from app.database import new_tool_session
from app.models.mock_test import MockTestAttempt, MockTestQuestion
from app.tools.db_sync import run_async

log = logging.getLogger(__name__)


class MockTestAnalysisInput(BaseModel):
    student_id: str = Field(..., description="UUID of the student.")
    attempt_id: str = Field(..., description="UUID of the completed MockTestAttempt.")


class MockTestAnalysisTool(BaseTool):
    """Analyse a submitted mock test attempt and return performance metrics."""

    name: str = "Mock Test Analysis Tool"
    description: str = (
        "Analyse a student's completed mock test attempt. "
        "Returns subject-level accuracy, topic-level accuracy, skipped question count, "
        "and average time per question. "
        "Use this tool to identify which exam subjects and topics need targeted revision."
    )
    args_schema: type[BaseModel] = MockTestAnalysisInput

    def _run(self, student_id: str, attempt_id: str) -> str:
        log.info(
            "mock_test_analysis_tool  student_id=%s  attempt_id=%s",
            student_id,
            attempt_id,
        )
        return run_async(self._analyse(student_id, attempt_id))

    async def _analyse(self, student_id: str, attempt_id: str) -> str:
        try:
            student_uuid = uuid.UUID(student_id)
            attempt_uuid = uuid.UUID(attempt_id)
        except ValueError as exc:
            raise ValueError(f"Invalid UUID: {exc}") from exc

        async with new_tool_session() as session:
            # Load the attempt
            attempt = await session.get(MockTestAttempt, attempt_uuid)
            if attempt is None or attempt.student_id != student_uuid:
                return json.dumps({"error": f"Attempt {attempt_id} not found for student {student_id}"})
            if attempt.submitted_at is None:
                return json.dumps({"error": "Attempt has not been submitted yet"})

            # Load the questions for this paper
            result = await session.execute(
                select(MockTestQuestion).where(
                    MockTestQuestion.paper_id == attempt.paper_id
                )
            )
            questions = result.scalars().all()

        answers: dict[str, str] = attempt.answers or {}

        # ── Per-subject and per-topic accumulators ────────────────────
        subject_stats: dict[str, dict] = defaultdict(lambda: {"correct": 0, "total": 0, "score": 0, "max": 0})
        topic_stats: dict[str, dict] = defaultdict(lambda: {"correct": 0, "total": 0})
        skipped_count = 0

        for q in questions:
            subj = q.subject or "unknown"
            topic = q.topic or "General"
            given = answers.get(str(q.id), "").strip()
            correct = (q.correct_answer or "").strip()

            subject_stats[subj]["total"] += 1
            subject_stats[subj]["max"] += 4
            topic_stats[topic]["total"] += 1

            if not given:
                skipped_count += 1
                continue

            if given == correct:
                subject_stats[subj]["correct"] += 1
                subject_stats[subj]["score"] += 4
                topic_stats[topic]["correct"] += 1
            else:
                if q.question_type != "integer":
                    subject_stats[subj]["score"] -= 1

        # ── Build output dicts ─────────────────────────────────────────
        subject_breakdown: dict[str, dict] = {}
        for subj, s in subject_stats.items():
            subject_breakdown[subj] = {
                "score": s["score"],
                "max": s["max"],
                "attempts": s["total"] - skipped_count,
                "correct": s["correct"],
                "accuracy_pct": round(
                    (s["correct"] / s["total"] * 100) if s["total"] else 0.0, 1
                ),
            }

        topic_accuracy: dict[str, dict] = {}
        for topic, t in topic_stats.items():
            topic_accuracy[topic] = {
                "correct": t["correct"],
                "total": t["total"],
                "accuracy_pct": round(
                    (t["correct"] / t["total"] * 100) if t["total"] else 0.0, 1
                ),
            }

        # Sort topics by accuracy ascending (weakest first)
        topic_accuracy = dict(
            sorted(topic_accuracy.items(), key=lambda kv: kv[1]["accuracy_pct"])
        )

        total_attempts = len(questions) - skipped_count
        avg_time = (
            round(attempt.time_taken_seconds / max(total_attempts, 1), 1)
            if attempt.time_taken_seconds
            else None
        )

        output = {
            "student_id": student_id,
            "attempt_id": attempt_id,
            "paper_id": attempt.paper_id,
            "submitted_at": attempt.submitted_at.isoformat(),
            "total_score": attempt.score or 0,
            "max_score": attempt.max_score or 0,
            "accuracy_pct": float(attempt.accuracy_pct or 0),
            "time_taken_seconds": attempt.time_taken_seconds,
            "avg_time_per_question_s": avg_time,
            "skipped_count": skipped_count,
            "subject_breakdown": subject_breakdown,
            "topic_accuracy_map": topic_accuracy,
        }

        # ── Detailed debug logging for analysis results ────────────────
        total_questions = len(questions)
        total_attempted = total_questions - skipped_count
        overall_accuracy = (
            sum(s["correct"] for s in subject_stats.values()) / max(total_attempted, 1) * 100
        )
        weakest_subject = (
            min(subject_breakdown, key=lambda k: subject_breakdown[k]["accuracy_pct"])
            if subject_breakdown else "n/a"
        )
        log.info(
            "mock_test_analysis.result  student_id=%s  attempt_id=%s"
            "  total_questions=%d  attempted=%d  skipped=%d"
            "  score=%d/%d  overall_accuracy=%.1f%%"
            "  weakest_subject=%s  topic_count=%d"
            "  avg_time_per_q=%s",
            student_id, attempt_id,
            total_questions, total_attempted, skipped_count,
            attempt.score or 0, attempt.max_score or 0, overall_accuracy,
            weakest_subject, len(topic_accuracy),
            f"{avg_time}s" if avg_time else "n/a",
        )
        for subj, stats in subject_breakdown.items():
            log.debug(
                "mock_test_analysis.subject  student_id=%s  subject=%s"
                "  correct=%d  total=%d  accuracy=%.1f%%  score=%d/%d",
                student_id, subj,
                stats["correct"], stats["attempts"],
                stats["accuracy_pct"], stats["score"], stats["max"],
            )

        return json.dumps(output)


# Instantiated tool — imported by agents.py
mock_test_analysis_tool = MockTestAnalysisTool()
