# TutorMatch A.I.

A Flutter client with a real FastAPI backend. The interface, routes, and visual
design are the original TutorMatch A.I. prototype; the people, scores, requests,
and messages now come from the API instead of sample data.

- **Client:** Flutter 3.47 / Dart 3.13, `http` for REST, `shared_preferences`
  for token restore. No fake data remains in `lib/`.
- **Server:** Python 3.11+, FastAPI, pydantic, scikit-learn `NearestNeighbors`,
  Argon2id password hashing, and JWT access/refresh tokens.
- **Storage:** in memory behind repository interfaces. Optional atomic JSON
  snapshots can be enabled for development. There is no database requirement.

The backend documentation is in [`backend/README.md`](backend/README.md), with
the matching model in [`backend/MATCHING.md`](backend/MATCHING.md) and the chat
contract in [`backend/CHAT.md`](backend/CHAT.md).

## Run on Windows

### 1. Backend

```powershell
cd backend
py -3.11 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
Copy-Item .env.example .env
# Edit .env and replace JWT_SECRET with a long random value.
.\.venv\Scripts\python.exe -m uvicorn app.main:app --reload --port 8000
```

The API is at <http://127.0.0.1:8000>, with generated docs at
<http://127.0.0.1:8000/docs>. The default `.env.example` allows the Flutter web
development origin `http://localhost:8080` through CORS. Change
`CORS_ORIGINS` (comma-separated) if the client runs on another origin.

### 2. Flutter web

From the repository root, in a second terminal:

```powershell
flutter pub get
flutter run -d chrome --web-hostname=localhost --web-port=8080 `
  --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

The base URL is read at build time and defaults to
`http://127.0.0.1:8000`. The web origin must be exactly
`http://localhost:8080` for the default CORS setting, so keep
`--web-port=8080` and open the `localhost` URL rather than `127.0.0.1` in the
browser.

If Windows reports that plugin symlink support is disabled, enable Developer
Mode in Windows Settings and run `flutter pub get` again. The project has
already been built and tested with the current Windows setup.

### 3. First account

The login screen's two demo buttons expect the development seed accounts added
in Phase 6. Until that seed script is run, use **Create an account** and complete
the five onboarding answers. A new account is stored in memory and disappears
when the backend restarts unless persistence is enabled.

## Tests

Backend, from `backend`:

```powershell
.\.venv\Scripts\python.exe -m pytest
```

Flutter, from the repository root:

```powershell
flutter analyze --no-pub
flutter test --no-pub
flutter build web --no-pub `
  --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

The Flutter tests use `package:http/testing.dart` to answer the real
`ApiClient` and repositories with API-shaped JSON, so token refresh, 401
handling, profile rollback, debounced match filters, requests, read receipts,
chat sends, route guards, and screen layouts are exercised without a server.

## Data and reset

By default `PERSIST_TO_FILE=false`: all accounts, profiles, requests,
conversations, messages, and uploads reset when the backend stops. To keep them,
set the following in `backend/.env`:

```dotenv
PERSIST_TO_FILE=true
STORE_PATH=data/store.json
UPLOAD_DIR=data/uploads
```

The snapshot is written atomically after a short debounce. Chat media is stored
under `UPLOAD_DIR/chat`; profile photos under `UPLOAD_DIR`. `data/store.json`
contains password hashes and private messages, so it and the upload directory
are gitignored.

To reset a persistent development store, stop the backend and delete
`backend/data/store.json` and `backend/data/uploads` (or the configured
`STORE_PATH` and `UPLOAD_DIR`), then start it again. Never commit those paths.

## Security notes

- Passwords are hashed with Argon2id; plaintext passwords are never stored.
- Access tokens last 15 minutes. Refresh tokens last 7 days, rotate on use, and
  are revoked on logout.
- `APP_ENV=production` requires a real `JWT_SECRET`; development may generate an
  ephemeral secret, which invalidates tokens on restart.
- Every profile, match, request, conversation, message, session, call, and
  private media endpoint checks the bearer token and participant access.
- Uploads are decoded, validated, metadata-stripped, and re-encoded. Images are
  size/dimension checked; voice notes check container signature, size, and
  duration.
- API errors are generic where they could reveal account existence, and
  `.env` is gitignored. Use `.env.example` as the template.
