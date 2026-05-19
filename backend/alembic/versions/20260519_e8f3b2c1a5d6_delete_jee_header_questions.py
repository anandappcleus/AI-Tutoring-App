"""delete JEE header-only questions (mathongo.com image PDFs)

Revision ID: e8f3b2c1a5d6
Revises: d7e2a1b3c4f5
Create Date: 2026-05-19

The JEE 2019 Mathongo PDFs are image-based; pypdf can only extract
page headers containing 'mathongo.com'. Deletes those 1440 rows from
production so only real extractable questions remain.

This migration is idempotent — running it twice is safe.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "e8f3b2c1a5d6"
down_revision: Union[str, None] = "d7e2a1b3c4f5"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    conn = op.get_bind()
    result = conn.execute(
        sa.text("DELETE FROM mock_test_questions WHERE question_text LIKE '%mathongo.com%'")
    )
    deleted = result.rowcount
    if deleted:
        print(f"\n[migration] Deleted {deleted} JEE header-only question(s).")
    else:
        print("\n[migration] No mathongo.com header rows found (already clean).")


def downgrade() -> None:
    # Cannot restore deleted rows without original data
    pass
