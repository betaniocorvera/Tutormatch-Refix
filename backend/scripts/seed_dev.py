"""Development-only demo seed.

The backend keeps its data in memory, so a seed script cannot write into a
running server's process directly. This script talks to the running API instead:
start the backend, run the seed, and the two demo accounts are ready in the
Flutter sign-in screen.

It is deliberately boring and idempotent: login with the demo password, register
only when the account is missing, then PUT the complete profile. Re-running it
updates the same two accounts and never creates duplicates.
"""

from __future__ import annotations

import argparse
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

import httpx
from dotenv import load_dotenv

# Allow both `python -m scripts.seed_dev` and `python scripts/seed_dev.py`.
if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.config import BACKEND_ROOT  # noqa: E402
from app.privacy import PRIVACY_POLICY_VERSION  # noqa: E402

DEMO_PASSWORD = "TutorMatch123!"
DEMO_API_URL = "http://127.0.0.1:8000"
LOCAL_HOSTS = {"127.0.0.1", "localhost", "::1"}
DEMO_SECURITY_QUESTIONS = (
    {"question_id": "first-pet", "answer": "Biscuit"},
    {"question_id": "first-school", "answer": "St Mary's"},
    {"question_id": "favourite-teacher", "answer": "Mrs Santos"},
)


@dataclass(frozen=True, slots=True)
class DemoAccount:
    email: str
    role: str
    display_name: str
    profile: dict[str, Any]


@dataclass(frozen=True, slots=True)
class SeedResult:
    email: str
    role: str
    display_name: str
    created: bool


class SeedError(RuntimeError):
    """A safe, user-facing seed failure."""


def availability(*slots: str) -> list[bool]:
    """A 21-cell grid in the backend's Monday-to-Sunday day-major order."""

    days = {
        "Mon": 0,
        "Tue": 1,
        "Wed": 2,
        "Thu": 3,
        "Fri": 4,
        "Sat": 5,
        "Sun": 6,
    }
    parts = {"Morn": 0, "Aft": 1, "Eve": 2}
    grid = [False] * 21
    for slot in slots:
        day, part = slot.split("-", 1)
        grid[days[day] * 3 + parts[part]] = True
    return grid


_COMMON_AVAILABILITY = availability(
    "Mon-Eve",
    "Tue-Eve",
    "Wed-Eve",
    "Thu-Eve",
    "Sat-Morn",
)

DEMO_ACCOUNTS: tuple[DemoAccount, ...] = (
    DemoAccount(
        email="maya@tutormatch.dev",
        role="student",
        display_name="Maya Chen",
        profile={
            "name": "Maya Chen",
            "subjects": ["Calculus", "Physics"],
            "style": "Watch one worked example, then do the next one myself",
            "mode": "both",
            "budget": 40,
            "availability": _COMMON_AVAILABILITY,
            "goal": "Move up a grade or two this year",
            "birthdate": "2008-01-14",
            "area_id": "london-highbury",
            "location_privacy": "area",
            "status_text": "Year 12 · calculus and physics",
            "presence": "available",
            "bio": (
                "I do better with one worked example and then a question "
                "of my own. Calculus and physics are the two I care about."
            ),
            "gender": "Prefer not to say",
            "languages": ["English"],
            "education": "",
            "grade": "Year 12",
        },
    ),
    DemoAccount(
        email="amara@tutormatch.dev",
        role="tutor",
        display_name="Amara Okonkwo",
        profile={
            "name": "Amara Okonkwo",
            "subjects": ["Calculus", "Statistics", "Physics"],
            "style": "I work through examples slowly and let the student steer",
            "mode": "both",
            "budget": 38,
            "availability": _COMMON_AVAILABILITY,
            "goal": "Fill a few steady evenings a week",
            "birthdate": "1997-03-02",
            "area_id": "london-highbury",
            "location_privacy": "area",
            "status_text": "Calculus and statistics, weekday evenings",
            "presence": "available",
            "bio": (
                "Six years of tutoring, mostly A-level maths. We start with "
                "what you already know and make the next step small enough."
            ),
            "gender": "Prefer not to say",
            "languages": ["English"],
            "years": 6,
            "education": "MSc Mathematics, UCL",
            "grade": "",
        },
    ),
)


def assert_development(app_env: str) -> None:
    """Refuse to write demo data outside a development/test environment."""

    if app_env.strip().lower() == "production":
        raise SeedError(
            "Refusing to seed demo accounts with APP_ENV=production. "
            "This script is for local development only."
        )


def normalize_api_url(raw: str, *, allow_remote: bool = False) -> str:
    """Validate the target and keep the default local-only guard."""

    url = raw.strip().rstrip("/")
    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise SeedError("--api-url must be an http:// or https:// URL.")
    if not allow_remote and parsed.hostname not in LOCAL_HOSTS:
        raise SeedError(
            "Refusing to seed a non-local API. Pass --allow-remote only when "
            "you are certain the target is a development server."
        )
    return url


def confirm_seed(*, assume_yes: bool, api_url: str) -> None:
    """Require an explicit confirmation before writing anything."""

    if assume_yes:
        return
    if not sys.stdin.isatty():
        raise SeedError(
            "No terminal is available for confirmation. Re-run with --yes."
        )
    print(
        "This will create or update the two demo accounts on the running "
        f"backend at {api_url}."
    )
    print("It is for local development only. Nothing is sent by email.")
    try:
        answer = input("Type 'seed' to continue: ").strip().lower()
    except EOFError as error:
        raise SeedError(
            "No terminal is available for confirmation. Re-run with --yes."
        ) from error
    if answer not in {"seed", "yes"}:
        raise SeedError("Seed cancelled.")


def seed_demo_accounts(
    client: httpx.Client,
    *,
    password: str = DEMO_PASSWORD,
) -> list[SeedResult]:
    """Create or update both demo accounts through the public API."""

    health = client.get("/health")
    if health.status_code != 200:
        raise SeedError(
            "The backend is not healthy. Start it first with "
            "`uvicorn app.main:app --port 8000`."
        )

    results: list[SeedResult] = []
    for account in DEMO_ACCOUNTS:
        session, created = _login_or_register(
            client,
            account,
            password=password,
        )
        user = session.get("user")
        if not isinstance(user, dict):
            raise SeedError(f"{account.email}: the login response has no user.")
        if user.get("role") != account.role:
            raise SeedError(
                f"{account.email} exists with role {user.get('role')!r}, "
                f"not {account.role!r}. Use a clean development store."
            )

        headers = {
            "Authorization": f"Bearer {session['access_token']}",
        }
        response = client.put(
            "/profile",
            headers=headers,
            json=account.profile,
        )
        if response.status_code != 200:
            raise SeedError(
                f"{account.email}: profile update failed "
                f"({response.status_code}): {_detail(response)}"
            )
        profile = response.json()
        if not profile.get("onboarding_complete"):
            raise SeedError(
                f"{account.email}: profile was saved but onboarding is "
                "still incomplete."
            )
        if profile.get("name") != account.display_name:
            raise SeedError(
                f"{account.email}: the server did not keep the display name."
            )
        results.append(
            SeedResult(
                email=account.email,
                role=account.role,
                display_name=account.display_name,
                created=created,
            )
        )
    return results


def _login_or_register(
    client: httpx.Client,
    account: DemoAccount,
    *,
    password: str,
) -> tuple[dict[str, Any], bool]:
    login = client.post(
        "/auth/login",
        json={"email": account.email, "password": password},
    )
    if login.status_code == 200:
        return login.json(), False
    if login.status_code != 401:
        raise SeedError(
            f"{account.email}: login failed ({login.status_code}): "
            f"{_detail(login)}"
        )

    register = client.post(
        "/auth/register",
        json={
            "email": account.email,
            "password": password,
            "role": account.role,
            "display_name": account.display_name,
            "phone": "",
            "area_id": account.profile["area_id"],
            "subjects": account.profile["subjects"],
            "security_questions": [
                dict(item) for item in DEMO_SECURITY_QUESTIONS
            ],
            "privacy_consent": True,
            "privacy_policy_version": PRIVACY_POLICY_VERSION,
        },
    )
    if register.status_code == 201:
        return register.json(), True
    if register.status_code == 409:
        raise SeedError(
            f"{account.email} already exists but the demo password did not "
            "work. Reset the development store, restart the backend, and "
            "run the seed again."
        )
    raise SeedError(
        f"{account.email}: registration failed ({register.status_code}): "
        f"{_detail(register)}"
    )


def _detail(response: httpx.Response) -> str:
    try:
        payload = response.json()
    except ValueError:
        return response.text[:300] or "no response body"
    if isinstance(payload, dict) and payload.get("detail") is not None:
        return str(payload["detail"])[:300]
    return str(payload)[:300]


def _load_app_env() -> str:
    load_dotenv(BACKEND_ROOT / ".env", override=False)
    return os.getenv("APP_ENV", "development")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Create or update the local TutorMatch demo accounts. "
            "Start the backend first; this script talks to the running API."
        )
    )
    parser.add_argument(
        "--api-url",
        default=DEMO_API_URL,
        help=f"Backend URL (default: {DEMO_API_URL})",
    )
    parser.add_argument(
        "--yes",
        action="store_true",
        help="Skip the interactive confirmation. For scripts and CI only.",
    )
    parser.add_argument(
        "--allow-remote",
        action="store_true",
        help="Allow a non-local API URL. Use only on a development server.",
    )
    args = parser.parse_args(argv)

    try:
        assert_development(_load_app_env())
        api_url = normalize_api_url(
            args.api_url,
            allow_remote=args.allow_remote,
        )
        confirm_seed(assume_yes=args.yes, api_url=api_url)
        with httpx.Client(
            base_url=api_url,
            timeout=15.0,
            follow_redirects=False,
        ) as client:
            results = seed_demo_accounts(client)
    except SeedError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    except httpx.HTTPError as error:
        print(
            "error: could not reach the backend. Is it running?\n"
            f"       {error}",
            file=sys.stderr,
        )
        return 2

    print(f"Seeded {len(results)} demo accounts at {api_url}:")
    for result in results:
        action = "created" if result.created else "updated"
        print(f"  {result.email:<28} {result.role:<8} {action}")
    print(f"Password: {DEMO_PASSWORD}")
    print(
        "Sign in with either account. If the backend uses the default "
        "PERSIST_TO_FILE=false, the accounts disappear when it stops; "
        "re-run this seed after restarting it."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
