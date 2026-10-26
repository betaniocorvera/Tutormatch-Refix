from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.errors import DuplicateEmailError
from app.main import create_app
from app.models.auth import RefreshToken
from app.models.profile import Profile
from app.models.user import Role, User
from app.repositories.in_memory import (
    InMemoryProfileRepository,
    InMemoryRefreshTokenRepository,
    InMemoryUserRepository,
)


def _user(
    *,
    user_id: str = "user-1",
    email: str = "user@example.com",
) -> User:
    now = datetime.now(timezone.utc)
    return User(
        id=user_id,
        email=email,
        password_hash="hash",
        role=Role.student,
        display_name="User",
        created_at=now,
        updated_at=now,
    )


def test_user_repository_indexes_email_case_insensitively() -> None:
    repo = InMemoryUserRepository()
    user = _user(email="User@Example.com")
    repo.add(user)

    assert repo.get_by_id(user.id) == user
    assert repo.get_by_email("USER@example.COM") == user


def test_user_repository_rejects_duplicate_email() -> None:
    repo = InMemoryUserRepository()
    repo.add(_user(user_id="one", email="same@example.com"))

    with pytest.raises(DuplicateEmailError):
        repo.add(_user(user_id="two", email="SAME@example.com"))


def test_user_repository_update_moves_email_index() -> None:
    repo = InMemoryUserRepository()
    user = _user(email="old@example.com")
    repo.add(user)

    updated = user.model_copy(update={"email": "new@example.com"})
    repo.update(updated)

    assert repo.get_by_email("old@example.com") is None
    assert repo.get_by_email("new@example.com") == updated


def test_user_repository_export_import_round_trip() -> None:
    repo = InMemoryUserRepository()
    user = _user()
    repo.add(user)

    state = repo.export_state()
    restored = InMemoryUserRepository()
    restored.import_state(state)

    assert restored.get_by_id(user.id) == user
    assert restored.get_by_email("user@example.com") == user


def test_profile_repository_export_import_round_trip() -> None:
    repo = InMemoryProfileRepository()
    profile = Profile(
        user_id="user-1",
        name="Maya Chen",
        subjects=["Calculus"],
        updated_at=datetime.now(timezone.utc),
    )
    repo.add(profile)

    assert repo.get_by_user_id("user-1") == profile
    assert repo.list_all() == [profile]

    restored = InMemoryProfileRepository()
    restored.import_state(repo.export_state())

    assert restored.get_by_user_id("user-1") == profile


def test_refresh_repository_revokes_and_exports() -> None:
    repo = InMemoryRefreshTokenRepository()
    now = datetime.now(timezone.utc)
    first = RefreshToken(
        jti="first",
        user_id="user-1",
        expires_at=now + timedelta(days=1),
        created_at=now,
    )
    second = RefreshToken(
        jti="second",
        user_id="user-1",
        expires_at=now + timedelta(days=1),
        created_at=now,
    )
    repo.add(first)
    repo.add(second)

    repo.revoke("first", replaced_by_jti="replacement")
    assert repo.get_by_jti("first").revoked_at is not None
    assert repo.get_by_jti("first").replaced_by_jti == "replacement"

    repo.revoke_all_for_user("user-1")
    assert repo.get_by_jti("second").revoked_at is not None

    restored = InMemoryRefreshTokenRepository()
    restored.import_state(repo.export_state())
    assert restored.get_by_jti("first").replaced_by_jti == "replacement"
    assert restored.get_by_jti("second").revoked_at is not None


def test_snapshot_round_trip_preserves_users_and_refresh_tokens(
    tmp_path,
) -> None:
    settings = Settings(
        app_env="test",
        jwt_secret="snapshot-secret-" + ("x" * 40),
        persist_to_file=True,
        store_path=tmp_path / "store.json",
        snapshot_debounce_seconds=0.0,
    )
    first_app = create_app(settings)

    with TestClient(first_app) as first_client:
        registered = first_client.post(
            "/auth/register",
            json={
                "email": "persisted@example.com",
                "password": "correct horse battery",
                "role": "student",
                "display_name": "Persisted User",
            },
        )
        assert registered.status_code == 201
        first_body = registered.json()

    assert settings.store_path.exists()

    second_app = create_app(settings)
    with TestClient(second_app) as second_client:
        login = second_client.post(
            "/auth/login",
            json={
                "email": "persisted@example.com",
                "password": "correct horse battery",
            },
        )
        assert login.status_code == 200

        refreshed = second_client.post(
            "/auth/refresh",
            json={"refresh_token": first_body["refresh_token"]},
        )
        assert refreshed.status_code == 200


def test_snapshot_round_trip_preserves_profiles(tmp_path) -> None:
    settings = Settings(
        app_env="test",
        jwt_secret="snapshot-secret-" + ("x" * 40),
        persist_to_file=True,
        store_path=tmp_path / "store.json",
        upload_path=tmp_path / "uploads",
        snapshot_debounce_seconds=0.0,
    )
    first_app = create_app(settings)

    with TestClient(first_app) as first_client:
        registered = first_client.post(
            "/auth/register",
            json={
                "email": "profile-persist@example.com",
                "password": "correct horse battery",
                "role": "student",
                "display_name": "Maya Chen",
            },
        )
        assert registered.status_code == 201
        access = registered.json()["access_token"]
        updated = first_client.put(
            "/profile",
            headers={"Authorization": f"Bearer {access}"},
            json={
                "subjects": ["Calculus"],
                "area_id": "london-highbury",
                "birthdate": "2009-03-14",
            },
        )
        assert updated.status_code == 200

    payload = json.loads(settings.store_path.read_text(encoding="utf-8"))
    assert "profiles" in payload

    second_app = create_app(settings)
    with TestClient(second_app) as second_client:
        login = second_client.post(
            "/auth/login",
            json={
                "email": "profile-persist@example.com",
                "password": "correct horse battery",
            },
        )
        assert login.status_code == 200
        access = login.json()["access_token"]

        profile = second_client.get(
            "/profile",
            headers={"Authorization": f"Bearer {access}"},
        )
        assert profile.status_code == 200
        assert profile.json()["subjects"] == ["Calculus"]
        assert profile.json()["lives_in"] == "Highbury, London"


def test_snapshot_is_valid_json_and_leaves_no_temp_file(
    settings: Settings,
) -> None:
    persistent_settings = Settings(
        app_env="test",
        jwt_secret="snapshot-secret-" + ("x" * 40),
        persist_to_file=True,
        store_path=settings.store_path,
        snapshot_debounce_seconds=0.0,
    )
    persistent_app = create_app(persistent_settings)
    with TestClient(persistent_app) as persistent_client:
        registered = persistent_client.post(
            "/auth/register",
            json={
                "email": "snapshot2@example.com",
                "password": "correct horse battery",
                "role": "student",
            },
        )
        assert registered.status_code == 201
        persistent_app.state.container.snapshot.flush()

    payload = json.loads(
        persistent_settings.store_path.read_text(encoding="utf-8")
    )
    assert "users" in payload
    assert "refresh_tokens" in payload
    assert not persistent_settings.store_path.with_name(
        persistent_settings.store_path.name + ".tmp"
    ).exists()


def test_snapshot_is_not_written_when_disabled(
    client: TestClient,
    settings: Settings,
) -> None:
    response = client.post(
        "/auth/register",
        json={
            "email": "memory@example.com",
            "password": "correct horse battery",
            "role": "student",
        },
    )
    assert response.status_code == 201
    assert not settings.store_path.exists()
