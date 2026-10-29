from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from tests.registration import registration_payload


def test_register_returns_tokens_and_own_user(
    client: TestClient,
) -> None:
    response = client.post(
        "/auth/register",
        json=registration_payload(
            email="Student@Example.COM",
            display_name="  Maya Chen  ",
            phone="+63 917 123 4567",
        ),
    )

    assert response.status_code == 201
    body = response.json()
    assert body["token_type"] == "bearer"
    assert body["expires_in"] == 900
    assert body["access_token"]
    assert body["refresh_token"]
    assert body["user"]["email"] == "student@example.com"
    assert body["user"]["role"] == "student"
    assert body["user"]["display_name"] == "Maya Chen"
    assert body["user"]["onboarding_complete"] is False
    assert "password_hash" not in body["user"]
    assert "password" not in body["user"]
    assert "security_answers" not in body["user"]
    assert "phone" not in body["user"]


def test_register_requires_a_display_name(
    client: TestClient,
) -> None:
    payload = registration_payload()
    payload["display_name"] = "  "

    response = client.post("/auth/register", json=payload)

    assert response.status_code == 422


def test_register_duplicate_email_is_case_insensitive(
    client: TestClient,
    register,
) -> None:
    assert register(email="student@example.com").status_code == 201

    duplicate = register(email="STUDENT@example.com")

    assert duplicate.status_code == 409
    assert duplicate.json()["detail"] == (
        "We couldn't create an account with that email. "
        "Try signing in or use a different address."
    )


@pytest.mark.parametrize(
    "overrides",
    [
        {"email": "not-an-email"},
        {"password": "short"},
        {"role": "admin"},
        {"unexpected": True},
        {"password": "x" * 129},
        {"display_name": "x" * 81},
        {"privacy_consent": False},
        {"privacy_consent": "true"},
        {"privacy_policy_version": "2020-01-v1"},
        {"subjects": []},
        {"area_id": ""},
        {"phone": "call me"},
        {"display_name": "Maya 2"},
    ],
)
def test_register_rejects_invalid_payloads(
    client: TestClient,
    overrides: dict,
) -> None:
    payload = registration_payload()
    payload.update(overrides)

    assert client.post("/auth/register", json=payload).status_code == 422


def test_register_does_not_store_plain_text_password(
    client: TestClient,
    app,
) -> None:
    response = client.post(
        "/auth/register",
        json=registration_payload(email="hash@example.com"),
    )
    assert response.status_code == 201

    users = app.state.container.users.list_all()
    assert len(users) == 1
    assert users[0].password_hash != "CorrectHorse1!"
    assert users[0].password_hash.startswith("$argon2")
