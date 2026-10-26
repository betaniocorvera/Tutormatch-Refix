# TutorMatch A.I. backend

FastAPI backend for the TutorMatch A.I. Flutter app.

Phase 1 provides the auth foundation: registration, login, JWT access and
rotating refresh tokens, logout, and a private `/auth/me` view. Phase 2 adds the
real profile: structured areas, subjects, availability, privacy-safe public
profiles, server-derived age/location/distance/completeness, and validated photo
uploads.

Data lives in memory. Set `PERSIST_TO_FILE=true` to keep a debounced, atomic JSON
snapshot at `data/store.json`; that snapshot includes users, profiles, and refresh
sessions. Without persistence, all data resets on restart.

## Setup (Windows PowerShell)

```powershell
cd backend
py -3.14 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
Copy-Item .env.example .env
# Edit .env and replace JWT_SECRET with a long random value.
```

Python 3.11 or newer is required. The app can start without `JWT_SECRET` in
development: it generates an ephemeral secret and logs a warning, but all tokens
become invalid on restart. Production (`APP_ENV=production`) refuses to start
without a real secret.

## Run

```powershell
.\.venv\Scripts\python.exe -m uvicorn app.main:app --reload --port 8000
```

Open http://127.0.0.1:8000/docs for the generated API docs.

## Test

```powershell
.\.venv\Scripts\python.exe -m pytest
```

## Auth endpoints

- `POST /auth/register` — `{email, password, role, display_name?}`
- `POST /auth/login` — `{email, password}`
- `POST /auth/refresh` — `{refresh_token}`
- `POST /auth/logout` — optional `{refresh_token}`, requires a bearer access token
- `GET /auth/me` — requires a bearer access token

Passwords are hashed with Argon2id through passlib. Access tokens last 15
minutes by default; refresh tokens last 7 days and rotate on use. Login failures
are rate-limited in memory per client IP and email.

## Profile endpoints

All profile endpoints require a bearer access token.

- `GET /profile` — the signed-in user's full editable profile
- `PUT /profile` — update profile answers; omitted fields stay unchanged
- `PUT /profile/subjects` — `{subjects: [string, ...]}`
- `PUT /profile/availability` — `{availability: [bool, ...]}` with exactly 21 slots
- `POST /profile/photo` — multipart `file`; accepts JPEG, PNG, or WebP
- `DELETE /profile/photo` — removes the photo

`PUT /profile` uses partial-update semantics even though it is a PUT. Sending an
explicit `null` for `birthdate`, `area_id`, or `years` clears that nullable field.
Subjects are canonical names from the subject catalogue, and a profile may choose
up to four. Availability is a flat 21-cell grid in day-major order (Monday
morning through Sunday evening), matching the existing Flutter week grid.

The profile response includes the stored answers plus server-derived readings:

- `age` from `birthdate`
- `lives_in` from the structured `area_id`
- `public_location` after applying `location_privacy`
- `completeness` with filled/total/missing fields
- `onboarding_complete` once subjects, style, availability, goal, and budget are present
- `photo_url` when a photo is stored

`location_privacy` is one of `area`, `city_only`, or `hidden`.

## Public user endpoints

These require a bearer access token.

- `GET /users/{id}` — privacy-safe public profile
- `GET /users/{id}/photo` — the stored JPEG photo, if one exists

Public profiles never include email, password hash, birthdate, raw `area_id`,
a separate raw `lives_in` field, the onboarding flag, or completeness. Age is
returned instead of birthdate. Location is exposed only through the filtered
`public_location`: a `city_only` profile exposes the city centre, an `area`
profile exposes the neighbourhood centre, and `hidden` exposes no location.
Distance is computed only when both the viewer and target have a visible public
location; otherwise `distance_km` is `null`.

## Static catalogues

Areas, subjects, and profile answer sets are loaded from backend data files, not
from sample users:

- `app/data/areas.json` — regions, cities, and 22 neighbourhoods with coordinates
- `app/data/subjects.json` — the 14 canonical subjects
- `app/data/profile_options.json` — role-specific styles/goals, languages, and genders

The lookup endpoints are public because they contain no personal data:

- `GET /areas` — `regions`, `cities`, and labelled `areas` for the picker
- `GET /subjects` — canonical subject ids and names

## Photo storage

Uploads are decoded with Pillow, checked for size, dimensions, format, and
animation, EXIF-oriented, stripped of metadata, and re-encoded as JPEG before
storage. The upload limit is 5 MB; the output is capped at 1024 px on its longest
side.

Photo bytes live behind a `PhotoStorage` interface. With
`PERSIST_TO_FILE=false` they are held in memory and reset on restart. With
`PERSIST_TO_FILE=true` they are written to `UPLOAD_DIR` (default
`data/uploads`) and survive a restart. Files are named from a hash of the user id,
and the directory is gitignored.

`data/store.json` contains password hashes and refresh sessions, so it is also
gitignored. Never commit either data directory.

## Other

- `GET /health`
