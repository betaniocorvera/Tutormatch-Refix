from __future__ import annotations

import logging

import pytest
from fastapi.testclient import TestClient

from app.privacy import PRIVACY_POLICY_VERSION
from tests.registration import (
    COMPLIANT_PASSWORD,
    DEFAULT_SECURITY_QUESTIONS,
    registration_payload,
)

_NEUTRAL_DUPLICATE = (
    "We couldn't create an account with that email. "
    "Try signing in or use a different address."
)


def _post(client: TestClient, **overrides):
    return client.post(
        "/auth/register",
        json=registration_payload(**overrides),
    )


def _auth_headers(tokens: dict) -> dict[str, str]:
    return {"Authorization": f"Bearer {tokens['access_token']}"}


def test_valid_registration_stores_hashes_and_returns_no_secrets(
    client: TestClient,
    app,
) -> None:
    response = client.post(
        "/auth/register",
        json=registration_payload(
            email="secure@example.com",
            phone="+63 917 123 4567",
            security_questions=[
                {
                    "question_id": "first-pet",
                    "answer": "  BISCUIT  ",
                },
                {
                    "question_id": "first-school",
                    "answer": "St   Mary's",
                },
                {
                    "question_id": "favourite-teacher",
                    "answer": "Mrs Santos",
                },
            ],
        ),
    )

    assert response.status_code == 201
    body = response.text
    for secret in (
        COMPLIANT_PASSWORD,
        "Biscuit",
        "St Mary's",
        "Mrs Santos",
        "answer_hash",
    ):
        assert secret not in body

    user = app.state.container.users.list_all()[0]
    assert user.password_hash.startswith("$argon2")
    assert app.state.container.passwords.verify(
        COMPLIANT_PASSWORD,
        user.password_hash,
    )
    assert user.phone == "+63 917 123 4567"
    assert user.privacy_consent is True
    assert user.privacy_consent_at is not None
    assert user.privacy_policy_version == PRIVACY_POLICY_VERSION
    assert [item.question_id for item in user.security_answers] == [
        "first-pet",
        "first-school",
        "favourite-teacher",
    ]
    assert all(
        item.answer_hash.startswith("$argon2")
        for item in user.security_answers
    )
    # Answers are trimmed, lower-cased, and whitespace-collapsed before hashing.
    assert app.state.container.passwords.verify(
        "biscuit",
        user.security_answers[0].answer_hash,
    )
    assert app.state.container.passwords.verify(
        "st mary's",
        user.security_answers[1].answer_hash,
    )
    assert app.state.container.passwords.verify(
        "mrs santos",
        user.security_answers[2].answer_hash,
    )

    profile = app.state.container.profiles.get_by_user_id(user.id)
    assert profile is not None
    assert profile.subjects == ["Calculus"]
    assert profile.area_id == "london-highbury"

    headers = _auth_headers(response.json())
    me = client.get("/auth/me", headers=headers)
    profile_response = client.get("/profile", headers=headers)
    for text in (me.text, profile_response.text):
        assert "Biscuit" not in text
        assert "answer_hash" not in text
        assert COMPLIANT_PASSWORD not in text


@pytest.mark.parametrize("consent", [False, None])
def test_registration_requires_privacy_consent(
    client: TestClient,
    app,
    consent: bool | None,
) -> None:
    payload = registration_payload()
    if consent is None:
        payload.pop("privacy_consent")
    else:
        payload["privacy_consent"] = consent

    response = client.post("/auth/register", json=payload)

    assert response.status_code == 422
    assert app.state.container.users.list_all() == []


@pytest.mark.parametrize(
    "password",
    [
        "Short1!",
        "alllowercase1!",
        "ALLUPPERCASE1!",
        "NoDigitsHere!",
        "NoSymbols1234",
        "Password123!",
        "Maya-Horse1!",
        "Chen-Horse1!",
    ],
)
def test_weak_or_personal_passwords_are_rejected(
    client: TestClient,
    password: str,
) -> None:
    response = _post(
        client,
        email="maya@example.com",
        display_name="Maya Chen",
        password=password,
    )

    assert response.status_code == 422


def test_duplicate_email_is_neutral(client: TestClient) -> None:
    assert _post(client, email="dup@example.com").status_code == 201

    duplicate = _post(client, email="DUP@example.com")

    assert duplicate.status_code == 409
    assert duplicate.json()["detail"] == _NEUTRAL_DUPLICATE


def test_admin_role_is_rejected(client: TestClient, app) -> None:
    response = _post(client, role="admin")

    assert response.status_code == 422
    assert app.state.container.users.list_all() == []


def test_duplicate_security_questions_are_rejected(
    client: TestClient,
    app,
) -> None:
    questions = [dict(DEFAULT_SECURITY_QUESTIONS[0]) for _ in range(3)]

    response = _post(client, security_questions=questions)

    assert response.status_code == 422
    assert app.state.container.users.list_all() == []


def test_unknown_security_question_is_rejected(
    client: TestClient,
    app,
) -> None:
    questions = [dict(item) for item in DEFAULT_SECURITY_QUESTIONS]
    questions[1] = {"question_id": "not-a-question", "answer": "Whatever"}

    response = _post(client, security_questions=questions)

    assert response.status_code == 422
    assert app.state.container.users.list_all() == []


@pytest.mark.parametrize(
    "answer",
    ["Maya Chen", "maya@example.com", "Maya"],
)
def test_security_answer_cannot_equal_email_or_name(
    client: TestClient,
    app,
    answer: str,
) -> None:
    questions = [dict(item) for item in DEFAULT_SECURITY_QUESTIONS]
    questions[0]["answer"] = answer

    response = _post(
        client,
        email="maya@example.com",
        security_questions=questions,
    )

    assert response.status_code == 422
    assert app.state.container.users.list_all() == []


def test_validation_errors_do_not_echo_secret_input(
    client: TestClient,
) -> None:
    weak = registration_payload()
    weak["password"] = "LeakPassword1"
    password_response = client.post("/auth/register", json=weak)
    assert password_response.status_code == 422
    assert "LeakPassword1" not in password_response.text

    bad_answer = registration_payload()
    bad_answer["security_questions"][0]["answer"] = 987654321
    answer_response = client.post("/auth/register", json=bad_answer)
    assert answer_response.status_code == 422
    assert "987654321" not in answer_response.text

    short_answer = registration_payload()
    short_answer["security_questions"][0]["answer"] = "Zq"
    short_response = client.post("/auth/register", json=short_answer)
    assert short_response.status_code == 422
    assert "Zq" not in short_response.text


def test_security_answers_are_not_logged(
    client: TestClient,
    caplog: pytest.LogCaptureFixture,
) -> None:
    caplog.set_level(logging.DEBUG)

    response = _post(
        client,
        security_questions=[
            {"question_id": "first-pet", "answer": "Logless Biscuit"},
            {"question_id": "first-school", "answer": "Logless School"},
            {
                "question_id": "favourite-teacher",
                "answer": "Logless Teacher",
            },
        ],
    )

    assert response.status_code == 201
    assert "Logless" not in caplog.text


def test_security_questions_endpoint_is_public_and_never_returns_answers(
    client: TestClient,
) -> None:
    response = client.get("/security-questions")

    assert response.status_code == 200
    questions = response.json()["questions"]
    assert len(questions) >= 10
    assert all(set(item) == {"id", "text"} for item in questions)
    assert all("answer" not in item for item in questions)


@pytest.mark.parametrize(
    "overrides",
    [
        {"display_name": "Maya 2"},
        {"phone": "call me"},
        {"phone": "123"},
        {"area_id": "not-a-real-area"},
        {"subjects": ["Not a real subject"]},
        {"subjects": ["Calculus", "Calculus"]},
    ],
)
def test_safe_field_limits_are_enforced(
    client: TestClient,
    overrides: dict,
) -> None:
    response = _post(client, **overrides)

    assert response.status_code == 422
