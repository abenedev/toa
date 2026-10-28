import uuid

import pytest
from conftest import auth_headers

from workout.models import Exercise, Set, Tombstone, User, Workout, WorkoutExercise
from workout.seed import DEFAULT_EXERCISES

ALICE = "11111111-1111-4111-8111-111111111111"
BOB = "22222222-2222-4222-8222-222222222222"
SQUAT = DEFAULT_EXERCISES[0][0]


def ts(second: float) -> str:
    return f"2026-10-26T12:00:{second:06.3f}Z"


T1 = ts(1)


def new_id() -> str:
    return str(uuid.uuid4())


def exercise_row(id_=None, updated_at=T1, **fields):
    return {
        "id": id_ or new_id(),
        "name": "Zercher Squat",
        "description": None,
        "type": "REPS",
        "equipment": "BARBELL",
        "updated_at": updated_at,
        **fields,
    }


def workout_row(id_=None, updated_at=T1, **fields):
    return {
        "id": id_ or new_id(),
        "name": "Push day",
        "planned": True,
        "description": None,
        "note": None,
        "rpe": None,
        "created_at": ts(0),
        "source_workout_id": None,
        "updated_at": updated_at,
        **fields,
    }


def workout_exercise_row(workout_id, exercise_id, id_=None, updated_at=T1):
    return {
        "id": id_ or new_id(),
        "workout_id": workout_id,
        "exercise_id": exercise_id,
        "position": 0,
        "note": None,
        "updated_at": updated_at,
    }


def set_row(workout_id, exercise_id, id_=None, updated_at=T1, **fields):
    return {
        "id": id_ or new_id(),
        "workout_id": workout_id,
        "exercise_id": exercise_id,
        "position": 0,
        "type": "WORKSET",
        "weight": 100.0,
        "rpe": 8.0,
        "rest": 120,
        "reps": 5,
        "duration": None,
        "updated_at": updated_at,
        **fields,
    }


def sync(client, user=ALICE, cursor=0, **body):
    resp = client.post(
        "/sync", json={"cursor": cursor, **body}, headers=auth_headers(user)
    )
    assert resp.status_code == 200, resp.text
    return resp.json()


def ids(rows):
    return {row["id"] for row in rows}


def test_first_sync_roundtrip(client):
    ex = exercise_row(description="Bar in the elbows " * 200)
    w = workout_row(rpe=7.5)
    we = workout_exercise_row(w["id"], ex["id"])
    s1 = set_row(w["id"], ex["id"])
    s2 = set_row(w["id"], SQUAT, reps=None, duration=60, weight=None, rpe=None)

    data = sync(
        client,
        profile={"bodyweight": 80.5, "updated_at": ts(1)},
        exercises=[ex],
        workouts=[w],
        workout_exercises=[we],
        sets=[s1, s2],
    )

    assert data["exercises"] == [ex]
    assert data["workouts"] == [w]
    assert data["workout_exercises"] == [we]
    assert sorted(data["sets"], key=lambda s: s["id"]) == sorted(
        [s1, s2], key=lambda s: s["id"]
    )
    assert data["deleted"] == []
    assert data["cursor"] > 0
    assert data["profile"] == {
        "email": f"{ALICE}@example.com",
        "bodyweight": 80.5,
        "updated_at": ts(1),
        "is_subscribed": False,
    }

    # Another device of the same user pulls everything, default exercises aside
    other = sync(client)
    assert other["cursor"] == data["cursor"]
    assert ids(other["exercises"]) == {ex["id"]}
    assert ids(other["sets"]) == {s1["id"], s2["id"]}


def test_timestamps_are_utc_milliseconds(client):
    w = workout_row(
        updated_at="2026-10-26T14:00:00+02:00", created_at="2026-10-26T11:59:59.123456Z"
    )
    data = sync(client, workouts=[w])
    assert data["workouts"][0]["updated_at"] == "2026-10-26T12:00:00.000Z"
    assert data["workouts"][0]["created_at"] == "2026-10-26T11:59:59.123Z"


def test_cursor_only_returns_newer_changes(client):
    w1 = workout_row()
    first = sync(client, workouts=[w1])

    empty = sync(client, cursor=first["cursor"])
    assert empty["workouts"] == []
    assert empty["cursor"] == first["cursor"]

    w2 = workout_row(name="Pull day")
    second = sync(client, cursor=first["cursor"], workouts=[w2])
    assert ids(second["workouts"]) == {w2["id"]}
    assert second["cursor"] > first["cursor"]

    # A cursor ahead of the server is kept
    ahead = sync(client, cursor=second["cursor"] + 1000)
    assert ahead["cursor"] == second["cursor"] + 1000


def test_last_write_wins(client):
    w = workout_row(updated_at=ts(10), name="v1")
    cursor = sync(client, workouts=[w])["cursor"]

    older = sync(
        client, cursor=cursor, workouts=[{**w, "name": "old", "updated_at": ts(5)}]
    )
    assert older["workouts"] == []
    assert older["cursor"] == cursor

    # Only a strictly newer stored row wins
    same = sync(client, cursor=cursor, workouts=[{**w, "name": "same ts"}])
    assert [row["name"] for row in same["workouts"]] == ["same ts"]

    newer = sync(
        client, cursor=cursor, workouts=[{**w, "name": "v2", "updated_at": ts(20)}]
    )
    assert [row["name"] for row in newer["workouts"]] == ["v2"]
    assert newer["workouts"][0]["updated_at"] == ts(20)


def test_duplicate_ids_in_one_push_keep_the_newest(client):
    w = workout_row(updated_at=T1, name="old")
    data = sync(
        client,
        workouts=[{**w, "name": "new", "updated_at": ts(2)}, w],
    )
    assert [row["name"] for row in data["workouts"]] == ["new"]


def test_delete_tombstone_reaches_other_device_and_wins(client):
    w = workout_row()
    cursor_b = sync(client, workouts=[w])["cursor"]  # device B is up to date

    deleted = sync(client, deleted=[{"entity": "workouts", "id": w["id"]}])
    assert deleted["workouts"] == []
    assert deleted["deleted"] == [{"entity": "workouts", "id": w["id"]}]

    # Device B edited the workout offline, after the delete: deletes still win
    b = sync(
        client,
        cursor=cursor_b,
        workouts=[{**w, "name": "edited", "updated_at": ts(59)}],
    )
    assert b["workouts"] == []
    assert b["deleted"] == [{"entity": "workouts", "id": w["id"]}]

    # Re-creating with the same id is not possible either
    assert sync(client, workouts=[{**w, "updated_at": ts(59.5)}])["workouts"] == []


def test_workout_delete_cascades(client, db_session):
    w = workout_row()
    ex = exercise_row()
    we = workout_exercise_row(w["id"], ex["id"])
    s = set_row(w["id"], ex["id"])
    cursor = sync(
        client, exercises=[ex], workouts=[w], workout_exercises=[we], sets=[s]
    )["cursor"]

    data = sync(client, cursor=cursor, deleted=[{"entity": "workouts", "id": w["id"]}])
    assert data["deleted"] == [{"entity": "workouts", "id": w["id"]}]
    assert db_session.query(WorkoutExercise).count() == 0
    assert db_session.query(Set).count() == 0
    assert db_session.get(Exercise, uuid.UUID(ex["id"])) is not None

    full = sync(client)
    assert full["workouts"] == full["sets"] == full["workout_exercises"] == []
    assert ids(full["exercises"]) == {ex["id"]}


def test_exercise_delete_cascades(client, db_session):
    w = workout_row()
    ex = exercise_row()
    sync(
        client,
        exercises=[ex],
        workouts=[w],
        workout_exercises=[workout_exercise_row(w["id"], ex["id"])],
        sets=[set_row(w["id"], ex["id"]), set_row(w["id"], SQUAT)],
    )
    sync(client, deleted=[{"entity": "exercises", "id": ex["id"]}])
    assert db_session.query(WorkoutExercise).count() == 0
    assert [s.exercise_id for s in db_session.query(Set)] == [uuid.UUID(SQUAT)]


def test_children_and_parent_deleted_together(client, db_session):
    w = workout_row()
    s = set_row(w["id"], SQUAT)
    sync(client, workouts=[w], sets=[s])
    data = sync(
        client,
        deleted=[
            {"entity": "workouts", "id": w["id"]},
            {"entity": "sets", "id": s["id"]},
            {"entity": "sets", "id": new_id()},  # unknown: ignored
        ],
    )
    assert sorted(data["deleted"], key=lambda d: d["entity"]) == [
        {"entity": "sets", "id": s["id"]},
        {"entity": "workouts", "id": w["id"]},
    ]
    assert db_session.query(Tombstone).count() == 2


def test_skipped_rows(client, db_session):
    bob_workout = workout_row(name="Bob's")
    bob_exercise = exercise_row(name="Bob's")
    sync(client, user=BOB, workouts=[bob_workout], exercises=[bob_exercise])

    data = sync(
        client,
        # Another user's rows
        workouts=[{**bob_workout, "name": "hijacked", "updated_at": ts(30)}],
        exercises=[
            {**bob_exercise, "name": "hijacked", "updated_at": ts(30)},
            # A default exercise
            exercise_row(SQUAT, name="My squat", updated_at=ts(30)),
        ],
        sets=[
            # Unknown workout
            set_row(new_id(), SQUAT),
            # Another user's workout / exercise
            set_row(bob_workout["id"], SQUAT),
            set_row(workout_row()["id"], bob_exercise["id"]),
        ],
        workout_exercises=[workout_exercise_row(bob_workout["id"], SQUAT)],
        deleted=[
            {"entity": "workouts", "id": bob_workout["id"]},
            {"entity": "exercises", "id": SQUAT},
        ],
    )
    assert data["workouts"] == data["exercises"] == data["sets"] == []
    assert data["workout_exercises"] == data["deleted"] == []

    db_session.expire_all()
    assert db_session.get(Workout, uuid.UUID(bob_workout["id"])).name == "Bob's"
    assert db_session.get(Exercise, uuid.UUID(bob_exercise["id"])).name == "Bob's"
    squat = db_session.get(Exercise, uuid.UUID(SQUAT))
    assert squat.name == "Barbell Squat" and squat.user_id is None
    assert db_session.query(Set).count() == 0

    # Bob still sees his rows unchanged
    bob = sync(client, user=BOB)
    assert [w["name"] for w in bob["workouts"]] == ["Bob's"]
    assert bob["deleted"] == []


def test_other_users_exercise_not_usable_in_own_workout(client):
    bob_exercise = exercise_row()
    sync(client, user=BOB, exercises=[bob_exercise])
    w = workout_row()
    data = sync(
        client,
        workouts=[w],
        workout_exercises=[workout_exercise_row(w["id"], bob_exercise["id"])],
    )
    assert ids(data["workouts"]) == {w["id"]}
    assert data["workout_exercises"] == []


def test_default_exercises_usable_and_never_returned(client):
    w = workout_row()
    we = workout_exercise_row(w["id"], SQUAT)
    s = set_row(w["id"], SQUAT)
    data = sync(client, workouts=[w], workout_exercises=[we], sets=[s])
    assert data["workout_exercises"] == [we]
    assert data["sets"] == [s]
    assert data["exercises"] == []


def test_profile_last_write_wins(client, db_session):
    sync(client, profile={"bodyweight": 80.0, "updated_at": ts(10)})
    data = sync(client, profile={"bodyweight": 70.0, "updated_at": ts(5)})
    assert data["profile"]["bodyweight"] == 80.0
    assert data["profile"]["updated_at"] == ts(10)

    data = sync(client, profile={"bodyweight": 82.5, "updated_at": ts(15)})
    assert data["profile"]["bodyweight"] == 82.5

    data = sync(client, profile=None)
    assert data["profile"]["bodyweight"] == 82.5
    assert data["profile"]["updated_at"] == ts(15)

    data = sync(client, profile={"bodyweight": None, "updated_at": ts(20)})
    assert data["profile"]["bodyweight"] is None


def test_profile_of_new_user(client):
    data = sync(client)
    assert data["cursor"] == 0
    assert data["profile"] == {
        "email": f"{ALICE}@example.com",
        "bodyweight": None,
        "updated_at": None,
        "is_subscribed": False,
    }


def test_users_do_not_see_each_other(client):
    sync(client, user=BOB, workouts=[workout_row()])
    data = sync(client)
    assert data["workouts"] == []
    assert data["cursor"] == 0


@pytest.mark.parametrize(
    "bad",
    [
        {"exercises": [exercise_row(type="SPRINT")]},
        {"sets": [set_row(new_id(), SQUAT, type="NOPE")]},
        {"deleted": [{"entity": "users", "id": new_id()}]},
        {"workouts": [workout_row(id_="not-a-uuid")]},
    ],
)
def test_invalid_payload_rejected(client, bad):
    resp = client.post("/sync", json=bad, headers=auth_headers(ALICE))
    assert resp.status_code == 422


def test_sync_requires_auth(client):
    assert client.post("/sync", json={}).status_code == 401


def test_me_and_delete_me(client, db_session):
    w = workout_row()
    sync(
        client,
        exercises=[exercise_row()],
        workouts=[w],
        sets=[set_row(w["id"], SQUAT)],
        profile={"bodyweight": 75.0, "updated_at": ts(1)},
    )
    sync(client, deleted=[{"entity": "workouts", "id": w["id"]}])
    sync(client, user=BOB, workouts=[workout_row()])

    me = client.get("/me", headers=auth_headers(ALICE)).json()
    assert me == {
        "email": f"{ALICE}@example.com",
        "bodyweight": 75.0,
        "updated_at": ts(1),
        "is_subscribed": False,
    }

    resp = client.delete("/me", headers=auth_headers(ALICE))
    assert resp.status_code == 204
    db_session.expire_all()
    assert db_session.get(User, ALICE) is None
    for model in (Exercise, Workout, Set, Tombstone):
        assert db_session.query(model).filter(model.user_id == ALICE).count() == 0
    assert db_session.query(Workout).filter(Workout.user_id == BOB).count() == 1
    assert db_session.query(Exercise).filter(Exercise.user_id.is_(None)).count() == len(
        DEFAULT_EXERCISES
    )


def test_email_kept_in_sync_with_token(client, db_session):
    from workout import auth
    from workout.main import app

    client.get("/me", headers=auth_headers(ALICE))
    app.dependency_overrides[auth.get_claims] = lambda: {
        "sub": ALICE,
        "email": "new@example.com",
    }
    assert client.get("/me").json()["email"] == "new@example.com"
    db_session.expire_all()
    assert db_session.get(User, ALICE).email == "new@example.com"


def test_health(client):
    assert client.get("/health").json() == {"status": "ok"}
