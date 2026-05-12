import uuid
from datetime import datetime, date

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class ProgressSnapshot(Base):
    """Weekly aggregate — accuracy per topic for a student."""

    __tablename__ = "progress_snapshots"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    student_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        sa.ForeignKey("students.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    week_start: Mapped[date] = mapped_column(sa.Date, nullable=False)
    # {"Kinematics": 72.5, "Thermodynamics": 45.0, ...}
    topic_accuracies: Mapped[dict] = mapped_column(JSONB, nullable=False, default=dict)
    total_questions: Mapped[int] = mapped_column(sa.Integer, nullable=False, default=0)
    snapshot_at: Mapped[datetime] = mapped_column(
        sa.DateTime(timezone=True), nullable=False, default=datetime.utcnow
    )

    __table_args__ = (
        sa.UniqueConstraint(
            "student_id", "week_start", name="uq_progress_snapshot_student_week"
        ),
    )


class PlateauFlag(Base):
    """Raised when a student is stuck on a topic for 3+ consecutive weak sessions."""

    __tablename__ = "plateau_flags"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    student_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        sa.ForeignKey("students.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    topic: Mapped[str] = mapped_column(sa.String(200), nullable=False)
    consecutive_weak_days: Mapped[int] = mapped_column(sa.Integer, nullable=False, default=3)
    flagged_at: Mapped[datetime] = mapped_column(
        sa.DateTime(timezone=True), nullable=False, default=datetime.utcnow
    )
    alert_sent: Mapped[bool] = mapped_column(sa.Boolean, nullable=False, default=False)
