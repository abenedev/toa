import uuid
from datetime import UTC, datetime
from typing import Annotated, Literal

from pydantic import AfterValidator, BaseModel, ConfigDict, Field, PlainSerializer


def _to_utc_ms(value: datetime) -> datetime:
    if value.tzinfo is None:
        value = value.replace(tzinfo=UTC)
    value = value.astimezone(UTC)
    return value.replace(microsecond=value.microsecond // 1000 * 1000)


def _format_utc_ms(value: datetime) -> str:
    return _to_utc_ms(value).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


# ISO-8601 UTC, millisecond precision, `Z` suffix (e.g. 2026-10-26T12:00:00.123Z).
# Accepts any ISO-8601 input (with or without fractional seconds / offset).
UtcDatetime = Annotated[
    datetime,
    AfterValidator(_to_utc_ms),
    PlainSerializer(_format_utc_ms, return_type=str, when_used="json"),
]

Int32 = Annotated[int, Field(ge=-(2**31), le=2**31 - 1)]

ExerciseType = Literal["REPS", "DURATION"]
Equipment = Literal[
    "BARBELL", "DUMBBELL", "MACHINE", "BODYWEIGHT", "ASSISTED_BODYWEIGHT"
]
SetType = Literal["WORKSET", "WARMUP", "DROPSET", "SUPERSET", "FAILURE"]
EntityName = Literal["exercises", "workouts", "workout_exercises", "sets"]


class Row(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    updated_at: UtcDatetime


class ExerciseRow(Row):
    name: str
    description: str | None = None
    type: ExerciseType
    equipment: Equipment


class WorkoutRow(Row):
    name: str
    planned: bool
    description: str | None = None
    note: str | None = None
    rpe: float | None = None
    created_at: UtcDatetime
    source_workout_id: uuid.UUID | None = None


class WorkoutExerciseRow(Row):
    workout_id: uuid.UUID
    exercise_id: uuid.UUID
    position: Int32
    note: str | None = None


class SetRow(Row):
    workout_id: uuid.UUID
    exercise_id: uuid.UUID
    position: Int32
    type: SetType
    weight: float | None = None
    rpe: float | None = None
    rest: Int32
    reps: Int32 | None = None
    duration: Int32 | None = None


class DeletedRow(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    entity: EntityName
    id: uuid.UUID


class ProfileIn(BaseModel):
    bodyweight: float | None = None
    updated_at: UtcDatetime


class Profile(BaseModel):
    email: str | None
    bodyweight: float | None
    updated_at: UtcDatetime | None
    is_subscribed: bool


class SyncRequest(BaseModel):
    cursor: int = Field(0, ge=0)
    profile: ProfileIn | None = None
    exercises: list[ExerciseRow] = []
    workouts: list[WorkoutRow] = []
    workout_exercises: list[WorkoutExerciseRow] = []
    sets: list[SetRow] = []
    deleted: list[DeletedRow] = []


class SyncResponse(BaseModel):
    cursor: int
    profile: Profile
    exercises: list[ExerciseRow]
    workouts: list[WorkoutRow]
    workout_exercises: list[WorkoutExerciseRow]
    sets: list[SetRow]
    deleted: list[DeletedRow]


def profile_of(user) -> Profile:
    return Profile(
        email=user.email,
        bodyweight=user.bodyweight,
        updated_at=user.bodyweight_updated_at,
        is_subscribed=user.is_subscribed,
    )
