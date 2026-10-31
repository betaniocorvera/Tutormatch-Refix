"""CAPTCHA and email OTP verification."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app.errors import InvalidCaptcha, InvalidEmailVerification
from app.services.verification import CAPTCHAService, EmailOTPService


def _start_body(email: str, challenge_id: str, answer: str) -> dict:
    return {
        "email": email,
        "captcha_id": challenge_id,
        "captcha_answer": answer,
    }


def _verify_body(email: str, code: str) -> dict:
    return {"email": email, "code": code}


def test_captcha_challenge_can_be_used_once(
    app,
    client: TestClient,
) -> None:
    """CAPTCHA answers are verified and consume their challenge."""

    challenge = client.get("/auth/captcha").json()
    answer = app.state.container.captcha._sessions[
        challenge["id"]
    ].answer

    response = client.post(
        "/auth/email-verification/start",
        json=_start_body(
            "student@example.com",
            challenge["id"],
            answer,
        ),
    )

    assert response.status_code == 202
    assert response.json()["status"] == "sent"
    with pytest.raises(InvalidCaptcha):
        app.state.container.captcha.verify(
            challenge["id"],
            answer,
        )


def test_captcha_challenge_rejects_an_incorrect_answer(
    app,
    client: TestClient,
) -> None:
    challenge = client.get("/auth/captcha").json()

    response = client.post(
        "/auth/email-verification/start",
        json=_start_body(
            "student@example.com",
            challenge["id"],
            "not-the-answer",
        ),
    )

    assert response.status_code == 422
    assert app.state.container.captcha._sessions.get(challenge["id"])


def test_captcha_response_never_includes_an_answer(client: TestClient) -> None:
    challenge = client.get("/auth/captcha").json()

    assert challenge["question"]
    assert "answer" not in challenge


def test_email_otp_can_be_verified_once(app) -> None:
    """The right code records the account as verified and consumes the OTP."""

    email_otp = EmailOTPService()
    email_otp.start(email="maya@example.com")
    code = email_otp._codes["maya@example.com"].code

    email_otp.verify("maya@example.com", code)

    assert "maya@example.com" not in email_otp._codes
    with pytest.raises(
        InvalidEmailVerification,
    ):
        email_otp.verify("maya@example.com", code)


def test_email_otp_rejects_an_incorrect_code(app) -> None:
    email_otp = EmailOTPService()
    email_otp.start(email="maya@example.com")

    with pytest.raises(InvalidEmailVerification):
        email_otp.verify("maya@example.com", "000000")
        email_otp.verify("maya@example.com", "111111")


def test_email_verification_expiry_and_new_code(app) -> None:
    """Each start call replaces the code and returns the new expiry."""
    email_otp = EmailOTPService()
    expires = email_otp.start(email="maya@example.com")
    assert expires
    new_expires = email_otp.start(email="Maya@example.com")
    assert new_expires != expires
