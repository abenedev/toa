import uuid
from datetime import UTC, datetime

from sqlalchemy import Engine
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from .models import Exercise

# Shared, read-only exercises (user_id NULL). The ids are fixed and identical
# in every client: never change or reuse them.
# (id, name, type, equipment)
DEFAULT_EXERCISES: list[tuple[str, str, str, str]] = [
    ("d9e34672-cb30-563a-99ef-bfd3033bfe13", "Barbell Squat", "REPS", "BARBELL"),
    ("763fe2b4-d7ff-5606-9492-fd94732e22a9", "Front Squat", "REPS", "BARBELL"),
    ("76cac9bd-d213-560d-b9b7-3064896976fd", "Barbell Bench Press", "REPS", "BARBELL"),
    (
        "8ce7f702-ffc0-5380-80f6-981ec81259f7",
        "Incline Barbell Bench Press",
        "REPS",
        "BARBELL",
    ),
    ("42c7760c-20dc-53e8-85e9-d252db4521b4", "Deadlift", "REPS", "BARBELL"),
    ("f246d132-cb59-5599-9f39-088c6767cdfd", "Romanian Deadlift", "REPS", "BARBELL"),
    ("ac5d0039-b229-5796-91c9-9a2ae0953269", "Overhead Press", "REPS", "BARBELL"),
    ("1cd97993-dadb-5b10-9e93-d429646b96a8", "Barbell Row", "REPS", "BARBELL"),
    ("954bbbb8-8e27-534a-87aa-4a8f1198997e", "Hip Thrust", "REPS", "BARBELL"),
    (
        "b451789d-b19b-5394-94cb-9d2ba6f8880d",
        "Dumbbell Bench Press",
        "REPS",
        "DUMBBELL",
    ),
    (
        "c42aefe2-ff42-5721-8887-c96f671c02b3",
        "Dumbbell Shoulder Press",
        "REPS",
        "DUMBBELL",
    ),
    ("5b62bf0e-b53d-5aa7-af35-3b6390f460a4", "Dumbbell Row", "REPS", "DUMBBELL"),
    ("f13a073d-2eb8-52ad-831a-134e4507b710", "Dumbbell Curl", "REPS", "DUMBBELL"),
    ("fac22fe6-2c7f-5939-9a9f-ec32ab5c731c", "Lateral Raise", "REPS", "DUMBBELL"),
    ("3dd04f9e-88a8-5621-a3fd-b071edd2a5d7", "Dumbbell Lunge", "REPS", "DUMBBELL"),
    ("7b3e0354-90f5-5b97-ab36-d2e37da3449c", "Leg Press", "REPS", "MACHINE"),
    ("13525c6a-4c72-5980-8856-09f39e975efa", "Leg Extension", "REPS", "MACHINE"),
    ("78e4819c-b4a2-5fd3-a3ac-1cee95dee134", "Leg Curl", "REPS", "MACHINE"),
    ("f79b36a5-6ec4-57e9-af2f-a14e1cc63457", "Lat Pulldown", "REPS", "MACHINE"),
    ("3aeec4c8-d738-50d8-a172-977cc106da5c", "Seated Cable Row", "REPS", "MACHINE"),
    ("28364cdb-83cd-5694-abc4-bb08342fb4e1", "Chest Fly Machine", "REPS", "MACHINE"),
    ("92864045-f23d-5ea8-9f1a-c4756243b912", "Triceps Pushdown", "REPS", "MACHINE"),
    ("3975018d-9a1c-544a-b43e-7599905b7daa", "Calf Raise", "REPS", "MACHINE"),
    ("f35f7437-6112-5b92-a413-24caa694b4d6", "Push-up", "REPS", "BODYWEIGHT"),
    ("43556fe3-2709-533e-bc79-f6cd4bf4f3d6", "Pull-up", "REPS", "BODYWEIGHT"),
    ("4f530491-5631-5665-b7f5-147e2bba990e", "Chin-up", "REPS", "BODYWEIGHT"),
    ("0695844c-4e56-585b-8458-6e87de72019a", "Dip", "REPS", "BODYWEIGHT"),
    ("620a9bfc-ee20-50ca-9d89-6a46dd9b3ee4", "Bodyweight Squat", "REPS", "BODYWEIGHT"),
    ("ed920064-3670-51e8-b2c5-d210d2fe3a0a", "Sit-up", "REPS", "BODYWEIGHT"),
    (
        "83ff2eb2-20ef-53fc-b8bc-dff26de73d29",
        "Assisted Pull-up",
        "REPS",
        "ASSISTED_BODYWEIGHT",
    ),
    (
        "18ed8013-e5b8-530a-840f-1705ea75413f",
        "Assisted Dip",
        "REPS",
        "ASSISTED_BODYWEIGHT",
    ),
    ("410cca39-f6a7-5015-bf67-225580e2ba7d", "Plank", "DURATION", "BODYWEIGHT"),
    ("941010a0-f1d2-59de-a1fd-4331e1d28d87", "Side Plank", "DURATION", "BODYWEIGHT"),
    ("b2e74349-533a-551f-b97c-d3ae3fdb0a33", "Dead Hang", "DURATION", "BODYWEIGHT"),
    ("29a05a10-5769-546b-b631-3b46c46f57f9", "Wall Sit", "DURATION", "BODYWEIGHT"),
]

DEFAULTS_UPDATED_AT = datetime(2026, 1, 1, tzinfo=UTC)


def seed_default_exercises(db: Session) -> None:
    """Insert the default exercises that are missing (by id)."""
    db.execute(
        insert(Exercise)
        .values(
            [
                {
                    "id": uuid.UUID(id_),
                    "user_id": None,
                    "name": name,
                    "type": type_,
                    "equipment": equipment,
                    "updated_at": DEFAULTS_UPDATED_AT,
                }
                for id_, name, type_, equipment in DEFAULT_EXERCISES
            ]
        )
        .on_conflict_do_nothing(index_elements=["id"])
    )
    db.commit()


def init_db(engine: Engine) -> None:
    with Session(engine) as db:
        seed_default_exercises(db)
