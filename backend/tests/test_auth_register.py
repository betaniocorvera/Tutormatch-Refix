from __future__ import annotations

import pytest
from fastapi.testclient import TestClient


def test_register_returns_tokens_and_own_user(
    client: TestClient,
) -> None:
    response = client.post(
        "/auth/register",
        json={
            "email": "Student@Example.COM",
            "password": "correct horse battery",
            "role": "student",
            "display_name": "  Maya Chen  ",
        },
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


def test_register_accepts_empty_display_name(
    client: TestClient,
) -> None:
    response = client.post(
        "/auth/register",
        json={
            "email": "noname@example.com",
            "password": "correct horse battery",
            "role": "tutor",
        },
    )

    assert response.status_code == 201
    assert response.json()["user"]["display_name"] == ""


def test_register_duplicate_email_is_case_insensitive(
    client: TestClient,
    register,
) -> None:
    assert register(email="student@example.com").status_code == 201

    duplicate = register(email="STUDENT@example.com")

    assert duplicate.status_code == 409
    assert duplicate.json()["detail"] == (
        "An account with that email already exists."
    )


@pytest.mark.parametrize(
    "payload",
    [
        {},
        {"email": "not-an-email", "password": "long enough", "role": "student"},
        {"email": "a@example.com", "password": "short", "role": "student"},
        {"email": "a@example.com", "password": "long enough", "role": "admin"},
        {"email": "a@example.com", "password": "long enough"},
        {
            "email": "a@example.com",
            "password": "long enough",
            "role": "student",
            "unexpected": True,
        },
        {
            "email": "a@example.com",
            "password": "x" * 129,
            "role": "student",
        },
        {
            "email": "a@example.com",
            "password": "long enough",
            "role": "student",
            "display_name": "x" * 81,
        },
    ],
)
def test_register_rejects_invalid_payloads(
    client: TestClient,
    payload: dict,
) -> None:
    assert client.post("/auth/register", json=payload).status_code == 422


def test_register_does_not_store_plain_text_password(
    client: TestClient,
    app,
) -> None:
    response = client.post(
        "/auth/register",
        json={
            "email": "hash@example.com",
            "password": "correct horse battery",
            "role": "student",
        },
    )
    assert response.status_code == 201

    users = app.state.container.users.list_all()
    assert len(users) == 1
    assert users[0].password_hash != "correct horse battery"
    assert users[0].password_hash.startswith("$argon2")
