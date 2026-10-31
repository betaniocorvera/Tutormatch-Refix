"""Import a JSON snapshot into PostgreSQL.

This is the cutover helper for moving an existing in-memory/JSON deployment to
the SQL backend. It validates the snapshot first, refuses to overwrite a
non-empty database unless ``--replace`` is supplied, and imports every
repository inside one transaction.

Typical use from ``backend``:

    python -m scripts.import_snapshot --snapshot data/store.json --dry-run
    python -m scripts.import_snapshot --snapshot data/store.json --replace

Run ``alembic upgrade head`` before the first import.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Any, Sequence

from sqlalchemy.exc import SQLAlchemyError

# Allow both `python -m scripts.import_snapshot` and
# `python scripts/import_snapshot.py`.
if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.config import BACKEND_ROOT, Settings  # noqa: E402
from app.database import Database  # noqa: E402
from app.repositories.sql import (  # noqa: E402
    SqlConversationRepository,
    SqlProfileRepository,
    SqlRefreshTokenRepository,
    SqlUserRepository,
)

SNAPSHOT_KEYS = (
    "users",
    "profiles",
    "refresh_tokens",
    "conversations",
)


class SnapshotImportError(RuntimeError):
    """A safe, user-facing import failure."""


@dataclass(frozen=True, slots=True)
class ImportSummary:
    users: int
    profiles: int
    refresh_tokens: int
    conversations: int


def load_snapshot(path: Path) -> dict[str, list[dict[str, Any]]]:
    """Read and validate the shape of a JSON snapshot."""

    try:
        payload = json.loads(Path(path).read_text(encoding="utf-8-sig"))
    except OSError as exc:
        raise SnapshotImportError(
            f"Could not read the snapshot at {path}."
        ) from exc
    except json.JSONDecodeError as exc:
        raise SnapshotImportError(
            f"The snapshot at {path} is not valid JSON."
        ) from exc

    if not isinstance(payload, dict):
        raise SnapshotImportError("The snapshot root must be a JSON object.")

    result: dict[str, list[dict[str, Any]]] = {}
    for key in SNAPSHOT_KEYS:
        state = payload.get(key)
        if not isinstance(state, list):
            raise SnapshotImportError(
                f"The snapshot is missing a '{key}' list."
            )
        if any(not isinstance(item, dict) for item in state):
            raise SnapshotImportError(
                f"Every '{key}' entry must be a JSON object."
            )
        result[key] = state
    return result


def summarize_snapshot(
    payload: dict[str, list[dict[str, Any]]],
) -> ImportSummary:
    return ImportSummary(
        users=len(payload["users"]),
        profiles=len(payload["profiles"]),
        refresh_tokens=len(payload["refresh_tokens"]),
        conversations=len(payload["conversations"]),
    )


def import_snapshot(
    database: Database,
    payload: dict[str, list[dict[str, Any]]],
    *,
    replace_existing: bool = False,
) -> ImportSummary:
    """Import a validated snapshot in one transaction.

    The SQL repositories join ``database.transaction()``, so a validation or
    constraint failure leaves the previous database state intact.
    """

    users = SqlUserRepository(database)
    profiles = SqlProfileRepository(database)
    refresh_tokens = SqlRefreshTokenRepository(database)
    conversations = SqlConversationRepository(database)

    existing = ImportSummary(
        users=len(users.list_all()),
        profiles=len(profiles.list_all()),
        refresh_tokens=len(refresh_tokens.list_all()),
        conversations=len(conversations.list_all()),
    )
    if any(
        (
            existing.users,
            existing.profiles,
            existing.refresh_tokens,
            existing.conversations,
        )
    ) and not replace_existing:
        raise SnapshotImportError(
            "The target database already contains data. "
            "Pass --replace only after taking a backup."
        )

    expected = summarize_snapshot(payload)
    try:
        with database.transaction():
            users.import_state(payload["users"])
            profiles.import_state(payload["profiles"])
            refresh_tokens.import_state(payload["refresh_tokens"])
            conversations.import_state(payload["conversations"])

            # Verify before commit so a count mismatch rolls back the import
            # instead of leaving a partially surprising result behind.
            imported = ImportSummary(
                users=len(users.list_all()),
                profiles=len(profiles.list_all()),
                refresh_tokens=len(refresh_tokens.list_all()),
                conversations=len(conversations.list_all()),
            )
            if imported != expected:
                raise SnapshotImportError(
                    "The imported row counts do not match the snapshot "
                    f"(expected {expected}, found {imported})."
                )
    except ValueError as exc:
        raise SnapshotImportError(
            f"Snapshot data could not be imported: {exc}"
        ) from exc
    return imported


def confirm_import(*, assume_yes: bool) -> None:
    """Require an explicit confirmation before replacing database data."""

    if assume_yes:
        return
    if not sys.stdin.isatty():
        raise SnapshotImportError(
            "No terminal is available for confirmation. Re-run with --yes."
        )
    print(
        "This will import the snapshot into the configured PostgreSQL "
        "database and replace its current rows."
    )
    try:
        answer = input("Type 'import' to continue: ").strip().lower()
    except EOFError as exc:
        raise SnapshotImportError(
            "No terminal is available for confirmation. Re-run with --yes."
        ) from exc
    if answer != "import":
        raise SnapshotImportError("Import cancelled.")


def _settings_for_import(database_url: str) -> Settings:
    base = Settings.from_env()
    return replace(
        base,
        storage_backend="postgres",
        database_url=database_url,
        persist_to_file=False,
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Import a TutorMatch JSON snapshot into PostgreSQL. "
            "Apply migrations before the first import."
        )
    )
    parser.add_argument(
        "--snapshot",
        type=Path,
        default=BACKEND_ROOT / "data" / "store.json",
        help="Path to the JSON snapshot (default: data/store.json).",
    )
    parser.add_argument(
        "--database-url",
        default="",
        help=(
            "PostgreSQL SQLAlchemy URL. Defaults to DATABASE_URL from the "
            "environment or backend/.env."
        ),
    )
    parser.add_argument(
        "--replace",
        action="store_true",
        help="Replace existing rows. Refused by default for safety.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate and print counts without writing anything.",
    )
    parser.add_argument(
        "--yes",
        action="store_true",
        help="Skip the interactive confirmation prompt.",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        payload = load_snapshot(args.snapshot)
        summary = summarize_snapshot(payload)
        print(
            "Snapshot: "
            f"{summary.users} users, "
            f"{summary.profiles} profiles, "
            f"{summary.refresh_tokens} refresh tokens, "
            f"{summary.conversations} conversations."
        )
        if args.dry_run:
            print("Dry run: no database writes performed.")
            return 0

        database_url = (
            args.database_url.strip()
            or Settings.from_env().database_url
        )
        if not database_url:
            raise SnapshotImportError(
                "No database URL. Set DATABASE_URL or pass --database-url."
            )

        confirm_import(assume_yes=args.yes)
        settings = _settings_for_import(database_url)
        database = Database(settings)
        try:
            database.check()
            imported = import_snapshot(
                database,
                payload,
                replace_existing=args.replace,
            )
        finally:
            database.dispose()

        print(
            "Imported: "
            f"{imported.users} users, "
            f"{imported.profiles} profiles, "
            f"{imported.refresh_tokens} refresh tokens, "
            f"{imported.conversations} conversations."
        )
        return 0
    except SnapshotImportError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    except SQLAlchemyError:
        print(
            "error: the database operation failed. Apply migrations with "
            "`alembic upgrade head`, then check DATABASE_URL and permissions.",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
