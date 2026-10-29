from __future__ import annotations

import os
from pathlib import Path

# The application module creates a module-level app for uvicorn. Give that
# import a test secret so test runs do not log an ephemeral-secret warning.
os.environ.setdefault("APP_ENV", "test")
os.environ.setdefault("JWT_SECRET", "test-global-secret-" + ("x" * 40))
os.environ.setdefault("PERSIST_TO_FILE", "false")

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from tests.registration import COMPLIANT_PASSWORD, registration_payload


@pytest.fixture()
def settings(tmp_path: Path) -> Settings:
    return Settings(
        app_env="test",
        jwt_secret="test-secret-" + ("x" * 48),
        persist_to_file=False,
        store_path=tmp_path / "store.json",
        upload_path=tmp_path / "uploads",
        snapshot_debounce_seconds=0.0,
        login_rate_limit_attempts=5,
        login_rate_limit_window_seconds=900,
    )


@pytest.fixture()
def app(settings: Settings):
    return create_app(settings)


@pytest.fixture()
def client(app):
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture()
def register(client: TestClient):
    def _register(
        *,
        email: str = "student@example.com",
        password: str = COMPLIANT_PASSWORD,
        role: str = "student",
        display_name: str = "Maya Chen",
    ):
        return client.post(
            "/auth/register",
            json=registration_payload(
                email=email,
                password=password,
                role=role,
                display_name=display_name,
            ),
        )

    return _register


@pytest.fixture()
def auth_tokens(register):
    response = register()
    assert response.status_code == 201
    return response.json()


@pytest.fixture()
def auth_headers(auth_tokens):
    return {"Authorization": f"Bearer {auth_tokens['access_token']}"}
