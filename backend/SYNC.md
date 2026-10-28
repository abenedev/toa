# Toa API & sync protocol

Clients (iOS today, Android later) are **offline-first**: every operation is
applied to the on-device database first, then pushed to this API by
`POST /sync` whenever the device is online. The same call pulls changes made
on the user's other devices.

## Authentication

Every endpoint except `/health` and the store webhooks requires
`Authorization: Bearer <Cognito ID token>`.

The backend verifies the token against the user pool JWKS (RS256, `iss`,
`aud` = app client id, `token_use` = `id`, `exp`). The token's `sub` is the
user id (`users.id`), and its `email` claim is copied to `users.email`. The
user row is created on first authenticated request.

Guest users never call the API.

## Conventions

- JSON keys are `snake_case`.
- Ids are client-generated UUIDs (string form, case-insensitive; the server answers in lowercase).
- Timestamps are ISO-8601 UTC with millisecond precision, e.g.
  `2026-10-26T12:00:00.123Z`. Clients truncate `updated_at` to milliseconds
  when they write it locally.
- Enums:
  - exercise `type`: `REPS` | `DURATION`
  - exercise `equipment`: `BARBELL` | `DUMBBELL` | `MACHINE` | `BODYWEIGHT` | `ASSISTED_BODYWEIGHT`
  - set `type`: `WORKSET` | `WARMUP` | `DROPSET` | `SUPERSET` | `FAILURE`

## Entities

| Entity (`entity` key) | Fields |
|---|---|
| `exercises` | `id`, `name`, `description?`, `type`, `equipment`, `updated_at` |
| `workouts` | `id`, `name`, `planned`, `description?`, `note?`, `rpe?` (number), `created_at`, `source_workout_id?`, `updated_at` |
| `workout_exercises` | `id`, `workout_id`, `exercise_id`, `position`, `note?`, `updated_at` |
| `sets` | `id`, `workout_id`, `exercise_id`, `position`, `type`, `weight?`, `rpe?`, `rest` (s), `reps?`, `duration?` (s), `updated_at` |

`?` = nullable. `planned = true` is a workout template; a performed workout
has `planned = false` and `source_workout_id` pointing to the workout it was
started from (lineage, not a foreign key).

**Default exercises** are shared by every user, have fixed UUIDs (identical
in `backend/src/workout/seed.py` and every client), are never synced and are
read-only. Sets and workout exercises may reference them.

## `POST /sync`

Request:

```json
{
  "cursor": 0,
  "profile": { "bodyweight": 80.5, "updated_at": "2026-10-26T12:00:00.000Z" },
  "exercises": [], "workouts": [], "workout_exercises": [], "sets": [],
  "deleted": [ { "entity": "workouts", "id": "…uuid…" } ]
}
```

- `cursor`: the value returned by the previous successful sync, `0` the
  first time.
- `profile`: `null` when the bodyweight has not changed locally.
- Entity arrays: rows created or modified locally since the last sync (full
  rows, not patches).
- `deleted`: rows deleted locally since the last sync.

Response `200`:

```json
{
  "cursor": 123,
  "profile": { "email": "a@b.c", "bodyweight": 80.5, "updated_at": "…", "is_subscribed": false },
  "exercises": [], "workouts": [], "workout_exercises": [], "sets": [],
  "deleted": [ { "entity": "sets", "id": "…" } ]
}
```

The arrays hold every row of the user changed since the request's `cursor`,
**including the rows just pushed**. Clients upsert them idempotently.
In `profile`, `bodyweight` and `updated_at` are `null` until a bodyweight has
been synced (`email` is `null` if the token has no `email` claim).

A malformed request (missing field, unknown enum value, invalid UUID, integer
outside the 32-bit range) is rejected with `422` and nothing is applied;
rows that are merely not applicable are skipped silently (see below).

### Server rules (one transaction, serialized per user)

1. Lock the user row (`SELECT … FOR UPDATE`) so syncs of one user never
   interleave; this makes the cursor safe.
2. Profile: applied if `updated_at` is newer than the stored one.
3. Upserts, in order exercises → workouts → workout_exercises → sets. A row
   is **skipped** (silently) when:
   - its id has a tombstone (deletes win), or
   - it exists but belongs to another user, or is a default exercise, or
   - the stored `updated_at` is newer (last-write-wins), or
   - it references a workout or exercise that doesn't exist or isn't visible
     to the user.
   Each written row gets a new `version` from the global `sync_version`
   sequence.
4. Deletes: an owned row is deleted (the database cascades: deleting a
   workout deletes its workout exercises and sets; deleting an exercise
   deletes the sets and workout exercises that use it) and a tombstone
   `(entity, id, user_id, version)` is recorded. Unknown ids are ignored.
5. Pull: user rows and tombstones with `version > cursor`. The new cursor is
   the max version of all the user's rows and tombstones (or the request
   cursor if higher).

### Client rules

- After a `200`: rows whose `updated_at` didn't change during the request
  are marked clean; the pushed tombstones are dropped.
- Applying pulled rows: a local row that is still dirty and has a newer
  `updated_at` wins (it will be pushed next time); otherwise the server row
  overwrites it.
- Applying `deleted`: delete the local row and cascade exactly like the
  server (workout → its workout exercises and sets; exercise → sets and
  workout exercises referencing it).
- Store the new `cursor` and `profile`.

## Other endpoints

| Method & path | Body | Response |
|---|---|---|
| `GET /health` | | `{"status": "ok"}` |
| `GET /me` | | profile (as in the sync response) |
| `DELETE /me` | | `204`, user and all their data deleted |
| `POST /billing/apple/transactions` | `{"signed_transaction": "<StoreKit 2 JWS>"}` | profile |
| `POST /billing/apple/notifications` | App Store Server Notifications V2 (`{"signedPayload": …}`) | `200` |
| `POST /billing/checkout-session` | | `{"url"}` (Stripe, web) |
| `POST /billing/portal-session` | | `{"url"}` (Stripe, web) |
| `POST /billing/webhook` | Stripe event | `{"received": true}` |

`is_subscribed` is true when either the Stripe subscription (web) or the
Apple subscription (iOS) is active, so a subscription bought on one platform
removes ads on all of them. iOS purchases set `appAccountToken` to the user
id so Apple's server notifications can be mapped back to the user.
