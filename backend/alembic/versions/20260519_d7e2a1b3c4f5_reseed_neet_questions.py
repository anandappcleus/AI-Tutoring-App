"""reseed NEET questions with correct options and answers

Revision ID: d7e2a1b3c4f5
Revises: a1f3e9d02b7c
Create Date: 2026-05-19

Replaces all mock_test_questions with the corrected seed data:
  - Removes bad JEE 2019 header-only questions (mathongo.com image PDFs)
  - Replaces NEET questions that had options=NULL and correct_answer='0'
    with properly extracted data (lowercase option/answer parsing fixed)
"""
from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "d7e2a1b3c4f5"
down_revision: Union[str, None] = "a1f3e9d02b7c"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# Seed file is in alembic/data/ relative to this migration's directory
_SEED_FILE = Path(__file__).parent.parent / "data" / "questions_seed_v2.json"


def upgrade() -> None:
    # Load seed data
    with open(_SEED_FILE, "r", encoding="utf-8") as f:
        questions = json.load(f)

    conn = op.get_bind()

    # 1. Clear all existing questions (old bad JEE + old NEET)
    conn.execute(sa.text("DELETE FROM mock_test_questions"))

    # 2. Re-insert corrected questions in batches
    if not questions:
        return

    insert_sql = sa.text("""
        INSERT INTO mock_test_questions
            (id, paper_id, exam_type, year, subject, topic,
             question_number, question_text, options, question_type,
             correct_answer, solution_text, has_image, source_file, created_at)
        VALUES
            (CAST(:id AS uuid), :paper_id, :exam_type, :year, :subject, :topic,
             :question_number, :question_text,
             CAST(:options_raw AS jsonb),
             :question_type, :correct_answer, :solution_text,
             :has_image, :source_file, NOW())
    """)

    batch_size = 100
    for i in range(0, len(questions), batch_size):
        batch = []
        for q in questions[i : i + batch_size]:
            row = dict(q)
            # JSONB must be passed as a JSON string
            opts = row.pop("options", None)
            row["options_raw"] = json.dumps(opts, ensure_ascii=False) if opts is not None else None
            batch.append(row)
        conn.execute(insert_sql, batch)


def downgrade() -> None:
    # Downgrade simply clears the seeded data; original data is not recoverable
    op.execute("DELETE FROM mock_test_questions")
