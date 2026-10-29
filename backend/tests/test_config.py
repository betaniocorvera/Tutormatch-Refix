from __future__ import annotations

import pytest

from app.config import DEFAULT_STORE_PATH, DEFAULT_UPLOAD_PATH, Settings


def test_from_env_rejects_invalid_boolean(monkeypatch) -> None:
    monkeypatch.setenv("PERSIST_TO_FILE", "maybe")

    with pytest.raises(ValueError, match="PERSIST_TO_FILE"):
        Settings.from_env()


def test_from_env_blank_store_path_uses_default(monkeypatch) -> None:
    monkeypatch.setenv("STORE_PATH", "")
    monkeypatch.setenv("JWT_SECRET", "s" * 64)

    settings = Settings.from_env()

    assert settings.store_path == DEFAULT_STORE_PATH


def test_from_env_blank_upload_path_uses_default(monkeypatch) -> None:
    monkeypatch.setenv("UPLOAD_DIR", "")
    monkeypatch.setenv("JWT_SECRET", "s" * 64)

    settings = Settings.from_env()

    assert settings.upload_path == DEFAULT_UPLOAD_PATH


def test_production_rejects_the_example_jwt_secret() -> None:
    with pytest.raises(ValueError, match="example value"):
        Settings(
            app_env="production",
            jwt_secret=(
                "replace-with-a-long-random-string-at-least-32-characters"
            ),
        )


def test_from_env_reads_database_settings(monkeypatch) -> None:
    monkeypatch.setenv("JWT_SECRET", "s" * 64)
    monkeypatch.setenv(
        "DATABASE_URL",
        "postgresql://user:pass@localhost:5432/tutormatch",
    )
    monkeypatch.setenv(
        "TEST_DATABASE_URL",
        "postgresql+psycopg://user:pass@localhost:5432/tutormatch_test",
    )
    monkeypatch.setenv("DATABASE_POOL_SIZE", "7")
    monkeypatch.setenv("DATABASE_MAX_OVERFLOW", "3")
    monkeypatch.setenv("DATABASE_POOL_TIMEOUT_SECONDS", "12.5")
    monkeypatch.setenv("DATABASE_ECHO", "true")
    monkeypatch.setenv("DATABASE_SSL_MODE", "require")

    settings = Settings.from_env()

    assert settings.database_url == (
        "postgresql+psycopg://user:pass@localhost:5432/tutormatch"
    )
    assert settings.test_database_url == (
        "postgresql+psycopg://user:pass@localhost:5432/tutormatch_test"
    )
    assert settings.database_pool_size == 7
    assert settings.database_max_overflow == 3
    assert settings.database_pool_timeout_seconds == 12.5
    assert settings.database_echo is True
    assert settings.database_ssl_mode == "require"


def test_database_url_must_use_postgresql() -> None:
    with pytest.raises(ValueError, match="DATABASE_URL"):
        Settings(
            jwt_secret="s" * 64,
            database_url="sqlite:///tutormatch.db",
        )


def test_database_pool_size_must_be_positive() -> None:
    with pytest.raises(ValueError, match="DATABASE_POOL_SIZE"):
        Settings(jwt_secret="s" * 64, database_pool_size=0)


def test_database_ssl_mode_must_be_known() -> None:
    with pytest.raises(ValueError, match="DATABASE_SSL_MODE"):
        Settings(jwt_secret="s" * 64, database_ssl_mode="sometimes")
