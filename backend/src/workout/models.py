from datetime import UTC, datetime

from sqlalchemy import (
    BigInteger,
    Boolean,
    Column,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    Sequence,
    Text,
    Uuid,
    func,
)

from .database import Base

# Global, monotonically increasing change counter. Every synced row and
# tombstone gets a fresh value when written; clients pull `version > cursor`.
sync_version = Sequence("sync_version", metadata=Base.metadata)


def _aware(value: datetime | None) -> datetime | None:
    if value is not None and value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value


class User(Base):
    __tablename__ = "users"

    # Cognito `sub`
    id = Column(Text, primary_key=True)
    email = Column(Text, nullable=True)
    bodyweight = Column(Float, nullable=True)
    bodyweight_updated_at = Column(DateTime(timezone=True), nullable=True)

    # Stripe (web)
    stripe_customer_id = Column(Text, unique=True, nullable=True)
    subscription_status = Column(Text, nullable=True)
    subscription_current_period_end = Column(DateTime(timezone=True), nullable=True)

    # Apple App Store (iOS)
    apple_original_transaction_id = Column(Text, unique=True, nullable=True)
    apple_expires_at = Column(DateTime(timezone=True), nullable=True)

    @property
    def is_stripe_subscribed(self) -> bool:
        if self.subscription_status not in ("active", "trialing"):
            return False
        end = _aware(self.subscription_current_period_end)
        return end is None or end > datetime.now(UTC)

    @property
    def is_apple_subscribed(self) -> bool:
        end = _aware(self.apple_expires_at)
        return end is not None and end > datetime.now(UTC)

    @property
    def is_subscribed(self) -> bool:
        return self.is_stripe_subscribed or self.is_apple_subscribed


def _user_fk(nullable: bool = False) -> Column:
    return Column(Text, ForeignKey("users.id", ondelete="CASCADE"), nullable=nullable)


def _updated_at() -> Column:
    return Column(DateTime(timezone=True), nullable=False)


def _version() -> Column:
    return Column(BigInteger, nullable=False, server_default=sync_version.next_value())


class Exercise(Base):
    __tablename__ = "exercises"
    __table_args__ = (Index("ix_exercises_user_version", "user_id", "version"),)

    id = Column(Uuid, primary_key=True)
    # NULL user_id means a default exercise shared by every user (read-only)
    user_id = _user_fk(nullable=True)
    name = Column(Text, nullable=False)
    description = Column(Text, nullable=True)
    type = Column(Text, nullable=False)
    equipment = Column(Text, nullable=False)
    updated_at = _updated_at()
    version = _version()


class Workout(Base):
    __tablename__ = "workouts"
    __table_args__ = (Index("ix_workouts_user_version", "user_id", "version"),)

    id = Column(Uuid, primary_key=True)
    user_id = _user_fk()
    name = Column(Text, nullable=False)
    planned = Column(Boolean, nullable=False)
    description = Column(Text, nullable=True)
    note = Column(Text, nullable=True)
    rpe = Column(Float, nullable=True)
    created_at = Column(DateTime(timezone=True), nullable=False)
    # Lineage only (the workout this one was started from), not a foreign key
    source_workout_id = Column(Uuid, nullable=True)
    updated_at = _updated_at()
    version = _version()


class WorkoutExercise(Base):
    __tablename__ = "workout_exercises"
    __table_args__ = (Index("ix_workout_exercises_user_version", "user_id", "version"),)

    id = Column(Uuid, primary_key=True)
    user_id = _user_fk()
    workout_id = Column(
        Uuid, ForeignKey("workouts.id", ondelete="CASCADE"), nullable=False, index=True
    )
    exercise_id = Column(
        Uuid, ForeignKey("exercises.id", ondelete="CASCADE"), nullable=False, index=True
    )
    position = Column(Integer, nullable=False)
    note = Column(Text, nullable=True)
    updated_at = _updated_at()
    version = _version()


class Set(Base):
    __tablename__ = "sets"
    __table_args__ = (Index("ix_sets_user_version", "user_id", "version"),)

    id = Column(Uuid, primary_key=True)
    user_id = _user_fk()
    workout_id = Column(
        Uuid, ForeignKey("workouts.id", ondelete="CASCADE"), nullable=False, index=True
    )
    exercise_id = Column(
        Uuid, ForeignKey("exercises.id", ondelete="CASCADE"), nullable=False, index=True
    )
    position = Column(Integer, nullable=False)
    type = Column(Text, nullable=False)
    weight = Column(Float, nullable=True)
    rpe = Column(Float, nullable=True)
    rest = Column(Integer, nullable=False)
    reps = Column(Integer, nullable=True)
    duration = Column(Integer, nullable=True)
    updated_at = _updated_at()
    version = _version()


class Tombstone(Base):
    __tablename__ = "tombstones"
    __table_args__ = (Index("ix_tombstones_user_version", "user_id", "version"),)

    entity = Column(Text, primary_key=True)
    id = Column(Uuid, primary_key=True)
    user_id = _user_fk()
    version = _version()
    deleted_at = Column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
