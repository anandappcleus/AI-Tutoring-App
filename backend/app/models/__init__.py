# Re-export all models so Alembic autogenerate can discover them
# by importing this module.

from app.models.base import Base
from app.models.student import Student, QuizAnswer, StudyPlan, Subscription
from app.models.progress import ProgressSnapshot, PlateauFlag

__all__ = [
    "Base",
    "Student",
    "QuizAnswer",
    "StudyPlan",
    "Subscription",
    "ProgressSnapshot",
    "PlateauFlag",
]
