"""`POST /sync`: push local changes and pull remote ones (see SYNC.md)."""

import uuid
from collections.abc import Callable, Iterable
from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy import delete, or_, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from . import auth
from .database import get_db
from .models import (
    Exercise,
    Set,
    Tombstone,
    User,
    Workout,
    WorkoutExercise,
    sync_version,
)
from .schemas import (
    DeletedRow,
    ExerciseRow,
    Row,
    SetRow,
    SyncRequest,
    SyncResponse,
    WorkoutExerciseRow,
    WorkoutRow,
    profile_of,
)

router = APIRouter(tags=["sync"])

DbSession = Annotated[Session, Depends(get_db)]

# Push order (parents first); deletes run in reverse order.
ENTITIES: dict[str, tuple[type, type[Row]]] = {
    "exercises": (Exercise, ExerciseRow),
    "workouts": (Workout, WorkoutRow),
    "workout_exercises": (WorkoutExercise, WorkoutExerciseRow),
    "sets": (Set, SetRow),
}


def _visible_ids(
    db: Session, model, ids: Iterable[uuid.UUID], user_id: str
) -> set[uuid.UUID]:
    ids = set(ids)
    if not ids:
        return set()
    owner = model.user_id == user_id
    if model is Exercise:
        owner = or_(owner, model.user_id.is_(None))
    return set(db.scalars(select(model.id).where(model.id.in_(ids), owner)))


def _upsert(
    db: Session,
    user_id: str,
    entity: str,
    rows: list[Row],
    references_ok: Callable[[Row], bool] = lambda row: True,
) -> None:
    if not rows:
        return
    model = ENTITIES[entity][0]
    ids = {row.id for row in rows}
    stored = {obj.id: obj for obj in db.scalars(select(model).where(model.id.in_(ids)))}
    tombstoned = set(
        db.scalars(
            select(Tombstone.id).where(
                Tombstone.entity == entity, Tombstone.id.in_(ids)
            )
        )
    )
    for row in rows:
        if row.id in tombstoned or not references_ok(row):
            continue
        obj = stored.get(row.id)
        if obj is None:
            obj = model(id=row.id, user_id=user_id)
            db.add(obj)
            stored[row.id] = obj
        elif obj.user_id != user_id or obj.updated_at > row.updated_at:
            # Another user's row, a default exercise, or last-write-wins
            continue
        for field, value in row.model_dump(exclude={"id"}).items():
            setattr(obj, field, value)
        obj.version = sync_version.next_value()
    db.flush()


def _delete(db: Session, user_id: str, deleted: list[DeletedRow]) -> None:
    for entity in reversed(ENTITIES):
        ids = {d.id for d in deleted if d.entity == entity}
        if not ids:
            continue
        table = ENTITIES[entity][0].__table__
        # The database cascades to dependent workout exercises and sets
        removed = db.scalars(
            delete(table)
            .where(table.c.id.in_(ids), table.c.user_id == user_id)
            .returning(table.c.id)
        ).all()
        if removed:
            db.execute(
                insert(Tombstone)
                .values(
                    [
                        {"entity": entity, "id": row_id, "user_id": user_id}
                        for row_id in removed
                    ]
                )
                .on_conflict_do_nothing()
            )


@router.post("/sync", response_model=SyncResponse)
def sync(request: SyncRequest, current_user: auth.CurrentUser, db: DbSession):
    user_id = current_user.id
    # Serialize the syncs of one user: this is what makes the cursor safe
    user = db.scalars(
        select(User)
        .where(User.id == user_id)
        .with_for_update()
        .execution_options(populate_existing=True)
    ).one()

    profile = request.profile
    if profile is not None and (
        user.bodyweight_updated_at is None
        or profile.updated_at > user.bodyweight_updated_at
    ):
        user.bodyweight = profile.bodyweight
        user.bodyweight_updated_at = profile.updated_at

    _upsert(db, user_id, "exercises", request.exercises)
    _upsert(db, user_id, "workouts", request.workouts)

    rows = request.workout_exercises + request.sets
    workouts = _visible_ids(db, Workout, (r.workout_id for r in rows), user_id)
    exercises = _visible_ids(db, Exercise, (r.exercise_id for r in rows), user_id)

    def references_ok(row) -> bool:
        return row.workout_id in workouts and row.exercise_id in exercises

    _upsert(db, user_id, "workout_exercises", request.workout_exercises, references_ok)
    _upsert(db, user_id, "sets", request.sets, references_ok)
    _delete(db, user_id, request.deleted)
    db.flush()
    db.expire_all()

    cursor = request.cursor
    changes: dict[str, list] = {}
    for entity, (model, schema) in ENTITIES.items():
        objs = db.scalars(
            select(model)
            .where(model.user_id == user_id, model.version > request.cursor)
            .order_by(model.version)
        ).all()
        changes[entity] = [schema.model_validate(obj) for obj in objs]
        cursor = max([cursor, *(obj.version for obj in objs)])
    tombstones = db.scalars(
        select(Tombstone)
        .where(Tombstone.user_id == user_id, Tombstone.version > request.cursor)
        .order_by(Tombstone.version)
    ).all()
    cursor = max([cursor, *(t.version for t in tombstones)])

    response = SyncResponse(
        cursor=cursor,
        profile=profile_of(user),
        deleted=[DeletedRow.model_validate(t) for t in tombstones],
        **changes,
    )
    db.commit()
    return response
