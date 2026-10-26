from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest
from jose import jwt

from app.config import Settings
from app.errors import InvalidToken
from app.models.user import Role, User
from app.security import (
    ACCESS_TOKEN_TYPE,
    REFRESH_TOKEN_TYPE,
    PasswordHasher,
    TokenService,
)


def _user() -> User:
    now = datetime.now(timezone.utc)
    return User(
        id="user-1",
        email="user@example.com",
        password_hash="not-used-here",
        role=Role.student,
        display_name="User",
        created_at=now,
        updated_at=now,
    )


def test_password_hash_round_trip() -> None:
    hasher = PasswordHasher()
    hashed = hasher.hash("correct horse battery")

    assert hashed != "correct horse battery"
    assert hashed.startswith("$argon2")
    assert hasher.verify("correct horse battery", hashed)
    assert not hasher.verify("wrong password", hashed)


def test_password_verifier_rejects_malformed_hash() -> None:
    hasher = PasswordHasher()
    assert not hasher.verify("anything", "not-a-hash")


def test_token_service_round_trip() -> None:
    settings = Settings(
        app_env="test",
        jwt_secret="s" * 64,
    )
    service = TokenService(settings)
    user = _user()

    issued = service.create_access_token(user)
    payload = service.decode(issued.token, ACCESS_TOKEN_TYPE)

    assert payload["sub"] == user.id
    assert payload["role"] == "student"
    assert payload["type"] == "access"
    assert payload["jti"] == issued.jti


def test_token_service_rejects_wrong_token_type() -> None:
    settings = Settings(
        app_env="test",
        jwt_secret="s" * 64,
    )
    service = TokenService(settings)
    user = _user()

    refresh = service.create_refresh_token(user)

    with pytest.raises(InvalidToken):
        service.decode(refresh.token, ACCESS_TOKEN_TYPE)


def test_token_service_rejects_expired_token() -> None:
    settings = Settings(
        app_env="test",
        jwt_secret="s" * 64,
    )
    service = TokenService(settings)
    user = _user()
    now = datetime.now(timezone.utc)
    expired = jwt.encode(
        {
            "sub": user.id,
            "role": "student",
            "type": "access",
            "jti": "expired",
            "iat": now - timedelta(hours=2),
            "exp": now - timedelta(hours=1),
            "iss": "tutormatch",
        },
        settings.jwt_secret,
        algorithm=settings.jwt_algorithm,
    )

    with pytest.raises(InvalidToken):
        service.decode(expired, ACCESS_TOKEN_TYPE)


def test_refresh_token_includes_a_jti() -> None:
    settings = Settings(
        app_env="test",
        jwt_secret="s" * 64,
    )
    service = TokenService(settings)
    user = _user()

    issued = service.create_refresh_token(user)
    payload = service.decode(issued.token, REFRESH_TOKEN_TYPE)

    assert payload["type"] == "refresh"
    assert payload["jti"] == issued.jti


def test_production_requires_a_real_jwt_secret() -> None:
    with pytest.raises(ValueError):
        Settings(app_env="production", jwt_secret="")


def test_short_jwt_secret_is_rejected() -> None:
    with pytest.raises(ValueError):
        Settings(app_env="test", jwt_secret="too-short")


def test_development_generates_an_ephemeral_secret() -> None:
    settings = Settings(app_env="development", jwt_secret="")

    assert settings.secret_is_ephemeral is True
    assert len(settings.jwt_secret) >= 32


def test_unsupported_jwt_algorithm_is_rejected() -> None:
    with pytest.raises(ValueError):
        Settings(
            app_env="test",
            jwt_secret="s" * 64,
            jwt_algorithm="none",
        )


def test_relative_store_path_is_resolved_against_backend_root() -> None:
    settings = Settings(
        app_env="test",
        jwt_secret="s" * 64,
        store_path="data/store.json",
    )

    assert settings.store_path.is_absolute()
    assert settings.store_path.name == "store.json"
    assert settings.store_path.parent.name == "data"
