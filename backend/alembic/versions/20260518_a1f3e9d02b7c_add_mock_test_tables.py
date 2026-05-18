"""add mock test tables

Revision ID: a1f3e9d02b7c
Revises: b3c7f0a91d2e
Create Date: 2026-05-18

Adds:
    mock_test_questions  — structured questions extracted from past-paper PDFs
    mock_test_attempts   — student exam attempts (full-paper mode)
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = "a1f3e9d02b7c"
down_revision: Union[str, None] = "b3c7f0a91d2e"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "mock_test_questions",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("paper_id", sa.String(length=50), nullable=False),
        sa.Column("exam_type", sa.String(length=10), nullable=False),
        sa.Column("year", sa.Integer(), nullable=False),
        sa.Column("subject", sa.String(length=20), nullable=False),
        sa.Column("topic", sa.String(length=200), nullable=True),
        sa.Column("question_number", sa.Integer(), nullable=False),
        sa.Column("question_text", sa.Text(), nullable=False),
        sa.Column("options", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("question_type", sa.String(length=20), nullable=False),
        sa.Column("correct_answer", sa.String(length=50), nullable=False),
        sa.Column("solution_text", sa.Text(), nullable=True),
        sa.Column("has_image", sa.Boolean(), nullable=False),
        sa.Column("source_file", sa.String(length=500), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "paper_id", "subject", "question_number",
            name="uq_mock_question_paper_subject_num",
        ),
    )
    op.create_index(
        op.f("ix_mock_test_questions_paper_id"),
        "mock_test_questions", ["paper_id"], unique=False,
    )
    op.create_index(
        op.f("ix_mock_test_questions_exam_type"),
        "mock_test_questions", ["exam_type"], unique=False,
    )

    op.create_table(
        "mock_test_attempts",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("student_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("paper_id", sa.String(length=50), nullable=False),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("submitted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("time_taken_seconds", sa.Integer(), nullable=True),
        sa.Column("answers", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("score", sa.Integer(), nullable=True),
        sa.Column("max_score", sa.Integer(), nullable=True),
        sa.Column("accuracy_pct", sa.Numeric(precision=5, scale=2), nullable=True),
        sa.Column(
            "subject_breakdown",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=True,
        ),
        sa.ForeignKeyConstraint(
            ["student_id"], ["students.id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        op.f("ix_mock_test_attempts_student_id"),
        "mock_test_attempts", ["student_id"], unique=False,
    )
    op.create_index(
        op.f("ix_mock_test_attempts_paper_id"),
        "mock_test_attempts", ["paper_id"], unique=False,
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_mock_test_attempts_paper_id"), table_name="mock_test_attempts")
    op.drop_index(op.f("ix_mock_test_attempts_student_id"), table_name="mock_test_attempts")
    op.drop_table("mock_test_attempts")

    op.drop_index(op.f("ix_mock_test_questions_exam_type"), table_name="mock_test_questions")
    op.drop_index(op.f("ix_mock_test_questions_paper_id"), table_name="mock_test_questions")
    op.drop_table("mock_test_questions")
