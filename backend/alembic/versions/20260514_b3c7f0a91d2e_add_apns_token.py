"""add apns_token to students

Revision ID: b3c7f0a91d2e
Revises: c0fc4ea40392
Create Date: 2026-05-14 10:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = 'b3c7f0a91d2e'
down_revision: Union[str, None] = 'c0fc4ea40392'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'students',
        sa.Column('apns_token', sa.String(length=64), nullable=True)
    )


def downgrade() -> None:
    op.drop_column('students', 'apns_token')
