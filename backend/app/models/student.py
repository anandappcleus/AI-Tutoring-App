import uuid
from datetime import datetime, date

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class Student(Base):
    __tablename__ = "students"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    name: Mapped[str] = mapped_column(sa.String(200), nullable=False)
    email: Mapped[str] = mapped_column(sa.String(320), unique=True, nullable=False, index=True)
    hashed_password: Mapped[str] = mapped_column(sa.String(128), nullable=False)

    # Localisation
    preferred_language: Mapped[str] = mapped_column(sa.String(5), nullable=False, default="bn")
    exam_target: Mapped[str] = mapped_column(sa.String(10), nullable=False, default="JEE")

    # Subscription
    is_premium: Mapped[bool] = mapped_column(sa.Boolean, nullable=False, default=False)

    # Account
    is_active: Mapped[bool] = mapped_column(sa.Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(
        sa.DateTime(timezone=True), nullable=False, default=datetime.utcnow
    )

    # Relationships
    quiz_answers: Mapped[list["QuizAnswer"]] = relationship(
        "QuizAnswer", back_populates="student", cascade="all, delete-orphan"
    )
    study_plans: Mapped[list["StudyPlan"]] = relationship(
        "StudyPlan", back_populates="student", cascade="all, delete-orphan"
    )
    subscription: Mapped["Subscription | None"] = relationship(
        "Subscription", back_populates="student", uselist=False, cascade="all, delete-orphan"
    )


class QuizAnswer(Base):
    __tablename__ = "quiz_answers"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    student_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        sa.ForeignKey("students.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    question: Mapped[str] = mapped_column(sa.Text, nullable=False)
    topic: Mapped[str | None] = mapped_column(sa.String(200), nullable=True)
    subject: Mapped[str | None] = mapped_column(sa.String(100), nullable=True)
    is_correct: Mapped[bool] = mapped_column(sa.Boolean, nullable=False)
    answered_at: Mapped[datetime] = mapped_column(
        sa.DateTime(timezone=True), nullable=False, default=datetime.utcnow, index=True
    )
    # synced=True means the record is on the server (backend always writes synced=True)
    synced: Mapped[bool] = mapped_column(sa.Boolean, nullable=False, default=True)

    student: Mapped["Student"] = relationship("Student", back_populates="quiz_answers")


class StudyPlan(Base):
    __tablename__ = "study_plans"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    student_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        sa.ForeignKey("students.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    plan_date: Mapped[date] = mapped_column(sa.Date, nullable=False)
    # JSON list: [{topic, duration_min, priority}]
    plan_json: Mapped[list] = mapped_column(JSONB, nullable=False, default=list)
    created_at: Mapped[datetime] = mapped_column(
        sa.DateTime(timezone=True), nullable=False, default=datetime.utcnow
    )

    __table_args__ = (
        sa.UniqueConstraint("student_id", "plan_date", name="uq_study_plan_student_date"),
    )

    student: Mapped["Student"] = relationship("Student", back_populates="study_plans")


class Subscription(Base):
    __tablename__ = "subscriptions"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    student_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        sa.ForeignKey("students.id", ondelete="CASCADE"),
        unique=True,  # one active subscription per student
        nullable=False,
    )
    plan_type: Mapped[str] = mapped_column(sa.String(20), nullable=False)  # "monthly" | "annual"
    valid_until: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), nullable=False)
    store_transaction_id: Mapped[str] = mapped_column(
        sa.String(256), unique=True, nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(
        sa.DateTime(timezone=True), nullable=False, default=datetime.utcnow
    )

    student: Mapped["Student"] = relationship("Student", back_populates="subscription")
