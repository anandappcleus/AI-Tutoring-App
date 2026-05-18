import uuid
from datetime import datetime
from decimal import Decimal

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class MockTestQuestion(Base):
    """
    A single question extracted from a past-paper PDF.

    paper_id links to a specific exam session (e.g. "jee-2019-0110-am" =
    JEE Mains 2019 Jan 10 Morning shift).  Multiple questions share the
    same paper_id, forming the complete paper.
    """

    __tablename__ = "mock_test_questions"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    # ── Paper identity ────────────────────────────────────────────────
    paper_id: Mapped[str] = mapped_column(
        sa.String(50), nullable=False, index=True
    )
    exam_type: Mapped[str] = mapped_column(
        sa.String(10), nullable=False, index=True
    )  # JEE | NEET
    year: Mapped[int] = mapped_column(sa.Integer, nullable=False)

    # ── Question content ──────────────────────────────────────────────
    subject: Mapped[str] = mapped_column(
        sa.String(20), nullable=False
    )  # physics | chemistry | mathematics | biology
    topic: Mapped[str | None] = mapped_column(
        sa.String(200), nullable=True
    )  # chapter name inferred from filename
    question_number: Mapped[int] = mapped_column(
        sa.Integer, nullable=False
    )  # position within the paper_id
    question_text: Mapped[str] = mapped_column(sa.Text, nullable=False)
    # MCQ: ["opt1", "opt2", "opt3", "opt4"], null for integer-type questions
    options: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    question_type: Mapped[str] = mapped_column(
        sa.String(20), nullable=False, default="MCQ"
    )  # MCQ | integer | multi_correct

    # ── Answer ────────────────────────────────────────────────────────
    # MCQ: "1" | "2" | "3" | "4" (1-indexed option number)
    # integer: the numeric value as a string, e.g. "42"
    # multi_correct: comma-separated, e.g. "1,3"
    correct_answer: Mapped[str] = mapped_column(sa.String(50), nullable=False)
    solution_text: Mapped[str | None] = mapped_column(sa.Text, nullable=True)

    # ── Metadata ──────────────────────────────────────────────────────
    has_image: Mapped[bool] = mapped_column(sa.Boolean, nullable=False, default=False)
    source_file: Mapped[str | None] = mapped_column(sa.String(500), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        sa.DateTime(timezone=True), nullable=False, default=datetime.utcnow
    )

    __table_args__ = (
        # Prevent duplicate insertion of the same question for a paper
        sa.UniqueConstraint(
            "paper_id", "subject", "question_number",
            name="uq_mock_question_paper_subject_num",
        ),
    )

    # Relationship back to attempts (via paper_id — not a FK, just a soft link)
    attempt_answers: Mapped[list["MockTestAttempt"]] = relationship(
        "MockTestAttempt",
        primaryjoin="MockTestQuestion.paper_id == foreign(MockTestAttempt.paper_id)",
        viewonly=True,
        uselist=True,
    )


class MockTestAttempt(Base):
    """
    A student's attempt at a full mock-test paper.

    answers stores the student's response per question:
        { "<question_uuid>": "2" }   # MCQ — option number
        { "<question_uuid>": "42" }  # integer type
    """

    __tablename__ = "mock_test_attempts"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    student_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        sa.ForeignKey("students.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    paper_id: Mapped[str] = mapped_column(
        sa.String(50), nullable=False, index=True
    )
    started_at: Mapped[datetime] = mapped_column(
        sa.DateTime(timezone=True), nullable=False, default=datetime.utcnow
    )
    submitted_at: Mapped[datetime | None] = mapped_column(
        sa.DateTime(timezone=True), nullable=True
    )
    time_taken_seconds: Mapped[int | None] = mapped_column(sa.Integer, nullable=True)

    # {"<question_uuid>": "<answer_string>"}
    answers: Mapped[dict] = mapped_column(JSONB, nullable=False, default=dict)

    # Populated on submit
    score: Mapped[int | None] = mapped_column(sa.Integer, nullable=True)
    max_score: Mapped[int | None] = mapped_column(sa.Integer, nullable=True)
    accuracy_pct: Mapped[Decimal | None] = mapped_column(
        sa.Numeric(5, 2), nullable=True
    )

    # Per-subject breakdown: {"physics": {"score":48,"max":120}, ...}
    subject_breakdown: Mapped[dict | None] = mapped_column(JSONB, nullable=True)

    student: Mapped["MockTestAttempt"] = relationship(
        "Student",
        foreign_keys=[student_id],
        primaryjoin="MockTestAttempt.student_id == Student.id",
        viewonly=True,
    )
