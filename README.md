# Toa

Workout tracker: native iOS app (SwiftUI), FastAPI backend, Next.js web app (paused).

```
backend/   FastAPI + Postgres (AWS RDS), Cognito auth, sync API — see backend/SYNC.md
ios/       SwiftUI app (iOS 17+), built by Codemagic and shipped to TestFlight
web/       Next.js web app (work paused)
```

## iOS app

- **Offline-first**: every operation (workouts, sets, exercises, records) runs
  on the device with SwiftData. Signed-in users' changes are queued and pushed
  to the backend by `POST /sync` whenever the phone is online (on change, on
  app foreground, when the network comes back, pull-to-refresh). The same call
  pulls changes from the user's other devices (iOS today, Android later).
- **Guest mode**: the app works without an account; data stays on the
  device. Creating an account (or logging in) from guest mode uploads it.
  A subscription requires an account.
- **Accounts**: native email/password screens talking directly to Amazon
  Cognito (no SDK). The refresh token in the Keychain keeps users signed in
  while offline.
- **Subscription**: "Remove ads" auto-renewable subscription with StoreKit 2.
  Purchases are verified by the backend so they also count on other platforms.
- **No third-party dependencies.** The Xcode project is generated from
  `ios/project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen).

### Build & TestFlight

Builds run on Codemagic (`codemagic.yaml`, workflow **iOS → TestFlight**), and
only start manually to save free-tier minutes. Before starting one, check that
the free **iOS Build** GitHub Action (compile only) is green for the commit.

Without the `TOA_*` variables the build is guest-only (accounts disabled).

## Backend

```bash
cd backend
docker compose up -d db
docker compose exec db psql -U user -d workout -c "CREATE DATABASE workout_test;"
uv run pytest
uv run fastapi dev src/workout/main.py
```

Environment variables are listed in `backend/.env.example`.
