# TutorMatch A.I. backend

FastAPI backend for the TutorMatch A.I. Flutter app.

Phase 1 provides the auth foundation: registration, login, JWT access and
rotating refresh tokens, logout, and a private `/auth/me` view. Phase 2 adds the
real profile: structured areas, subjects, availability, privacy-safe public
profiles, server-derived age/location/distance/completeness, and validated photo
uploads. Phase 3 adds the real match list: hard eligibility filters, the five
weighted groups from the Flutter prototype, KNN ranking, tiers, three reasons,
cold-start handling, and a labelled precision@5 evaluation. Phase 4 adds lesson
requests and accepted-only conversations: paginated messages, validated image and
voice uploads, read receipts and unread counts, session proposals, simulated call
events, WebSocket push, and a polling fallback. Phase 5 connects the Flutter
client to this API: repository-backed state, real auth restore and 401 logout,
profile and photo flows, server-side match filters, requests, polling chat, and
the Flutter web development CORS origin. Phase 6 adds the confirmed,
development-only demo seed and the final setup/reset documentation. Phase 7
adds optional PostgreSQL persistence through SQLAlchemy, psycopg 3, and Alembic
while keeping the in-memory repositories as the default for local work and
tests.

Data lives in memory by default. Set `PERSIST_TO_FILE=true` to keep a debounced,
atomic JSON snapshot at `data/store.json`; that snapshot includes users,
profiles, refresh sessions, requests, conversations, messages, events, and read
cursors. For a real deployment, set `STORAGE_BACKEND=postgres` and provide a
`DATABASE_URL`; the same repositories then read and write PostgreSQL. Without
either option, all data resets on restart.

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

## PostgreSQL storage

The default `STORAGE_BACKEND=memory` keeps the existing zero-dependency demo
setup and the fast unit tests. To use PostgreSQL:

1. Create a database and a role that can create tables.
2. Put a psycopg 3 URL in `backend/.env`:

   ```dotenv
   STORAGE_BACKEND=postgres
   DATABASE_URL=postgresql+psycopg://tutormatch:change-me@localhost:5432/tutormatch
   ```

   A plain `postgresql://` URL is also accepted and rewritten to the installed
   psycopg 3 driver.

3. Apply the schema from `backend`:

   ```powershell
   .\.venv\Scripts\python.exe -m alembic upgrade head
   ```

4. Start the API normally. The app checks the database connection during
   startup. `PERSIST_TO_FILE` is only for the in-memory backend; enabling both it
   and `STORAGE_BACKEND=postgres` is rejected. Profile photos and chat attachments
   are written under `UPLOAD_DIR` in PostgreSQL mode so they survive a restart.

Matching still runs in Python with scikit-learn; PostgreSQL stores the source
data but the KNN ranking is not moved into the database and `pgvector` is not
required.

The integration tests use `TEST_DATABASE_URL` and are skipped when it is not
set. Point it at a dedicated test database because the tests create and drop
the TutorMatch tables:

```powershell
$env:TEST_DATABASE_URL="postgresql+psycopg://tutormatch:change-me@localhost:5432/tutormatch_test"
.\.venv\Scripts\python.exe -m pytest tests\test_sql_repositories.py -q
```

## Run

```powershell
.\.venv\Scripts\python.exe -m uvicorn app.main:app --reload --port 8000
```

Open http://127.0.0.1:8000/docs for the generated API docs.

## Development seed

The Flutter login screen's demo buttons use two real accounts. With the backend
running, seed them from another terminal:

```powershell
.\.venv\Scripts\python.exe -m scripts.seed_dev
```

The script prints the target URL and asks you to type `seed`. Use `--yes` for
an unattended run:

```powershell
.\.venv\Scripts\python.exe -m scripts.seed_dev --yes
```

| Account | Role | Password |
| --- | --- | --- |
| `maya@tutormatch.dev` | student | `TutorMatch123!` |
| `amara@tutormatch.dev` | tutor | `TutorMatch123!` |

The seed is HTTP-based so it works with both the in-memory and PostgreSQL
backends: it checks `/health`, logs in existing demo accounts, registers missing
ones, and PUTs complete profiles. It is idempotent and safe to rerun.

Safety rules:

- It refuses `APP_ENV=production`.
- It only targets `localhost`, `127.0.0.1`, or `::1` unless `--allow-remote` is
  explicitly passed.
- It requires interactive confirmation unless `--yes` is passed.
- If an email already exists with a different password or role, it stops with a
  clear message instead of overwriting the account.

The default in-memory store disappears on restart; rerun the seed after starting
the backend again. With `PERSIST_TO_FILE=true` the seeded data is part of the
JSON snapshot, and with `STORAGE_BACKEND=postgres` it is stored in PostgreSQL;
both survive a restart.

## Flutter web client

From the repository root:

```powershell
flutter run -d chrome --web-hostname=localhost --web-port=8080 `
  --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

The client stores the token pair in `shared_preferences`, restores a session on
reload, refreshes once on a 401, and signs out when refresh fails. Chat uses
authenticated REST sends and five-second polling; it does not require a
WebSocket dependency.

CORS is allow-list based. The default `CORS_ORIGINS` is
`http://localhost:8080`; configure a comma-separated list of `http`/`https`
origins to allow another development host. Trailing slashes and non-HTTP origins
are rejected. The Flutter origin and API origin are different in development, so
the browser must be opened at the exact allowed origin.

## Test

```powershell
.\.venv\Scripts\python.exe -m pytest
```

PostgreSQL integration tests are skipped unless `TEST_DATABASE_URL` is set; see
the PostgreSQL storage section above for the dedicated test database command.

The matching evaluation is included in the suite. Run just that check with:

```powershell
.\.venv\Scripts\python.exe -m pytest tests/test_matching_evaluation.py -q
```

## Auth endpoints

- `POST /auth/register` — `{email, display_name, role, password, phone?, area_id, subjects, security_questions, privacy_consent, privacy_policy_version}`
- `POST /auth/login` — `{email, password}`
- `POST /auth/refresh` — `{refresh_token}`
- `POST /auth/logout` — optional `{refresh_token}`, requires a bearer access token
- `GET /auth/me` — requires a bearer access token
- `GET /security-questions` — public catalogue of `{id, text}` entries

Registration requires a role of `student` or `tutor`, one to four subjects from
the catalogue, a catalogue area, exactly three distinct security questions, and
`privacy_consent: true` with `privacy_policy_version: "2026-10-v1"`. The server
stores the consent flag, consent timestamp, and policy version on the user.

Passwords are hashed with Argon2id through passlib. New passwords need at least
10 characters, upper and lower case, a digit, a symbol, and must not be a common
password or contain the account's email local part or name. Security answers are
normalized (trimmed, lower-cased, whitespace-collapsed), hashed with the same
hasher, and stored only as hashes; they are never returned by an endpoint or
logged. Validation errors are stripped of the submitted `input` and `ctx`, so a
password or answer cannot be echoed back in a 422 response.

Access tokens last 15 minutes by default; refresh tokens last 7 days and rotate
on use. Login failures are rate-limited in memory per client IP and email.

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

## Match endpoint

`GET /matches` requires a bearer access token. It returns the ranked,
privacy-safe match list for the signed-in user, with the same five weighted
dimensions as the Flutter prototype:

- subjects 40
- available time 25
- style 15
- format 10
- budget 10

Hard eligibility (opposite role, not yourself, completed matching answers) is
applied before KNN. Query filters narrow the list without reordering it:

- `subjects` (repeated canonical subject name or id)
- `mode` (`online`, `in_person`, or `both`)
- `max_rate`
- `required_parts` (repeated 0, 1, or 2 for mornings, afternoons, evenings)
- `must_be_free_when_i_am`
- `max_distance_km`
- `min_score`
- `limit` (default 20, maximum 100)

The response includes `pool_size`, `ranked_count`, `returned`, and a
`cold_start` object when the viewer has not completed the matching answers or
there are no eligible counterparts. Each match carries a nested `PublicProfile`,
integer score, tier label, dimension breakdown, 21-cell overlap grid, and three
reasons. A hidden location never produces a distance or a nearby reason.

See [MATCHING.md](MATCHING.md) for the formulas, KNN embedding, tier thresholds,
reason selection, privacy rules, cold-start contract, and the labelled
precision@5 evaluation.

## Requests and chat

All request and conversation endpoints require a bearer access token.

- `POST /requests` — `{counterpart_id, subject, note}`
- `GET /requests` — your requests; optional `direction` and `status`
- `GET /requests/{id}` — one request
- `POST /requests/{id}/accept` — receiver accepts; optional `{note}`
- `POST /requests/{id}/decline` — receiver declines; required `{reason}`
- `GET /conversations` — your inbox
- `GET /conversations/{id}` — detail and read cursor
- `GET /conversations/{id}/messages` — `limit`, `before`, or `after`
- `POST /conversations/{id}/messages` — `{text}`
- `POST /conversations/{id}/messages/image` — multipart `file`
- `POST /conversations/{id}/messages/voice` — multipart `file` + `duration_seconds`
- `POST /conversations/{id}/messages/voice-note` — simulated `{duration_seconds}`
- `GET /conversations/{id}/messages/{message_id}/media` — private attachment bytes
- `POST /conversations/{id}/sessions` — `{proposed_for}`
- `POST /conversations/{id}/sessions/{message_id}/respond` — `{state}`
- `POST /conversations/{id}/calls` — `{kind, connected, duration_seconds}`
- `POST /conversations/{id}/read` — optional `{through_sequence}`
- `GET /conversations/{id}/events` — polling and catch-up
- `WS /ws/conversations/{id}?token=...&after=...` — push channel

A request is also its conversation: the initial note is the first message, and
there is exactly one conversation per pair. Both profiles must have completed
matching answers, the subject must be shared, and only the receiver can answer.
The chat is read-only until the request is accepted. Declining stores a reason;
a declined request can be re-requested and keeps its thread.

Messages use per-conversation sequences. `before` pages backwards through
history; `after` polls forwards. Text is trimmed and limited to 2000 characters.
Images are re-encoded through the same metadata-stripping pipeline as profile
photos. Voice notes are limited to 10 MB and 1–300 seconds and require a known
audio container. Read receipts are stored as a per-person cursor, and each
conversation summary reports its unread count.

See [CHAT.md](CHAT.md) for the full lifecycle, access-control rules, event
contract, WebSocket close codes, media limits, pagination, session/call payloads,
and Phase 5 client notes.

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

Photo bytes live behind a `PhotoStorage` interface. With the default in-memory
store they are held in memory and reset on restart. With `PERSIST_TO_FILE=true`
or `STORAGE_BACKEND=postgres` they are written to `UPLOAD_DIR` (default
`data/uploads`) and survive a restart. Files are named from a hash of the user
id, and the directory is gitignored.

Chat images and uploaded voice notes use a separate `ChatMediaStorage` interface.
With local media enabled they live under `UPLOAD_DIR/chat`, also under hashed
filenames. Chat media is private to the two participants; there is no public URL.

`data/store.json` contains password hashes, refresh sessions, and conversation
history, so it is also gitignored. Never commit either data directory.

## Other

- `GET /health`
