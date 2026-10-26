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
