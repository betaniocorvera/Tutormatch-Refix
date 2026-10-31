from __future__ import annotations

from dataclasses import replace
from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient

from app.errors import EmailDeliveryFailed
from app.services.email import OutboundEmail
from app.services.verification import (
    EMAIL_VERIFICATION_SCOPE,
    PASSWORD_RESET_OTP_SCOPE,
)
from tests.registration import COMPLIANT_PASSWORD

NEW_PASSWORD = "NewCorrectHorse2@"


class _FailingTransport:
    def send(self, message: OutboundEmail) -> None:
        raise EmailDeliveryFailed()


def _captcha(client: TestClient, app) -> tuple[str, str]:
    challenge = client.get("/auth/captcha").json()
    answer = app.state.container.captcha._sessions[challenge["id"]].answer
    return challenge["id"], answer


def _request_reset(
    client: TestClient,
    app,
    email: str = "student@example.com",
):
    captcha_id, answer = _captcha(client, app)
    return client.post(
        "/auth/password-reset/request",
        json={
            "email": email,
            "captcha_id": captcha_id,
            "captcha_answer": answer,
        },
    )


def _reset_code(app, email: str = "student@example.com") -> str:
    return app.state.container.email_otp._codes[
        (email, PASSWORD_RESET_OTP_SCOPE)
    ].code


def _confirm(
    client: TestClient,
    code: str,
    *,
    email: str = "student@example.com",
    new_password: str = NEW_PASSWORD,
):
    return client.post(
        "/auth/password-reset/confirm",
        json={
            "email": email,
            "code": code,
            "new_password": new_password,
        },
    )


def test_reset_request_is_generic_for_known_and_unknown_email(
    app,
    client: TestClient,
    register,
    recording_email,
) -> None:
    assert register().status_code == 201

    known = _request_reset(client, app, "student@example.com")
    unknown = _request_reset(client, app, "unknown@example.com")

    assert known.status_code == 202
    assert unknown.status_code == 202
    assert known.json() == unknown.json()
    assert "If an account exists" in known.json()["message"]
    assert len(recording_email.messages) == 1
    message = recording_email.messages[0]
    assert message.to == "student@example.com"
    assert "password reset" in message.subject.lower()
    code = _reset_code(app)
    assert code in message.body
    assert code not in message.subject
    assert code not in known.text
    assert ("unknown@example.com", PASSWORD_RESET_OTP_SCOPE) not in (
        app.state.container.email_otp._codes
    )
    events = app.state.container.security_events.events
    assert [event.event_type for event in events].count(
        "password_reset_requested"
    ) == 1


def test_reset_request_requires_a_captcha(
    app,
    client: TestClient,
    recording_email,
) -> None:
    response = client.post(
        "/auth/password-reset/request",
        json={
            "email": "student@example.com",
            "captcha_id": "missing",
            "captcha_answer": "1",
        },
    )

    assert response.status_code == 422
    assert recording_email.messages == []
    assert app.state.container.email_otp._codes == {}


def test_reset_request_is_rate_limited(
    app,
    client: TestClient,
    recording_email,
) -> None:
    for _ in range(3):
        assert _request_reset(
            client,
            app,
            "unknown@example.com",
        ).status_code == 202

    blocked = _request_reset(client, app, "unknown@example.com")

    assert blocked.status_code == 429
    assert blocked.headers["Retry-After"]


def test_reset_request_requires_configured_email(
    app,
    client: TestClient,
    register,
) -> None:
    assert register().status_code == 201

    response = _request_reset(client, app)

    assert response.status_code == 503
    assert "code" not in response.json()


def test_reset_delivery_failure_stays_generic_and_clears_the_code(
    app,
    client: TestClient,
    register,
    recording_email,
) -> None:
    assert register().status_code == 201
    app.state.container.email.transport = _FailingTransport()

    response = _request_reset(client, app)

    assert response.status_code == 202
    assert "If an account exists" in response.json()["message"]
    assert app.state.container.email_otp._codes == {}


def test_password_reset_changes_password_and_revokes_refresh_tokens(
    app,
    client: TestClient,
    register,
    recording_email,
) -> None:
    first = register()
    assert first.status_code == 201
    first_body = first.json()

    second = client.post(
        "/auth/login",
        json={
            "email": "student@example.com",
            "password": COMPLIANT_PASSWORD,
        },
    )
    assert second.status_code == 200
    second_body = second.json()

    requested = _request_reset(client, app)
    assert requested.status_code == 202
    code = _reset_code(app)

    response = _confirm(client, code)

    assert response.status_code == 204
    assert response.content == b""
    for refresh_token in (
        first_body["refresh_token"],
        second_body["refresh_token"],
    ):
        refreshed = client.post(
            "/auth/refresh",
            json={"refresh_token": refresh_token},
        )
        assert refreshed.status_code == 401

    old_password = client.post(
        "/auth/login",
        json={
            "email": "student@example.com",
            "password": COMPLIANT_PASSWORD,
        },
    )
    assert old_password.status_code == 401

    new_password = client.post(
        "/auth/login",
        json={
            "email": "student@example.com",
            "password": NEW_PASSWORD,
        },
    )
    assert new_password.status_code == 200

    events = app.state.container.security_events.events
    assert [event.event_type for event in events].count(
        "password_reset_completed"
    ) == 1
    rendered = " ".join(str(event) for event in events)
    assert code not in rendered
    assert NEW_PASSWORD not in rendered


def test_password_reset_code_is_one_time(
    app,
    client: TestClient,
    register,
    recording_email,
) -> None:
    assert register().status_code == 201
    assert _request_reset(client, app).status_code == 202
    code = _reset_code(app)

    assert _confirm(client, code).status_code == 204
    assert _confirm(client, code).status_code == 422


def test_password_reset_rejects_an_expired_code(
    app,
    client: TestClient,
    register,
    recording_email,
) -> None:
    assert register().status_code == 201
    assert _request_reset(client, app).status_code == 202
    key = ("student@example.com", PASSWORD_RESET_OTP_SCOPE)
    pending = app.state.container.email_otp._codes[key]
    app.state.container.email_otp._codes[key] = replace(
        pending,
        expires_at=datetime.now(timezone.utc) - timedelta(seconds=1),
    )

    response = _confirm(client, pending.code)

    assert response.status_code == 422


def test_password_reset_rejects_a_weak_password(
    app,
    client: TestClient,
    register,
    recording_email,
) -> None:
    assert register().status_code == 201
    assert _request_reset(client, app).status_code == 202
    code = _reset_code(app)

    response = _confirm(client, code, new_password="alllowercase1")

    assert response.status_code == 422
    assert "upper-case" in response.json()["detail"]
    assert ("student@example.com", PASSWORD_RESET_OTP_SCOPE) not in (
        app.state.container.email_otp._codes
    )

    old_password = client.post(
        "/auth/login",
        json={
            "email": "student@example.com",
            "password": COMPLIANT_PASSWORD,
        },
    )
    assert old_password.status_code == 200


def test_reset_code_is_not_valid_for_email_verification(
    app,
    client: TestClient,
    register,
    recording_email,
) -> None:
    assert register().status_code == 201
    assert _request_reset(client, app).status_code == 202
    code = _reset_code(app)

    response = client.post(
        "/auth/email-verification/verify",
        json={"email": "student@example.com", "code": code},
    )

    assert response.status_code == 422


def test_email_verification_code_is_not_valid_for_password_reset(
    app,
    client: TestClient,
    register,
    recording_email,
) -> None:
    assert register().status_code == 201
    captcha_id, answer = _captcha(client, app)
    started = client.post(
        "/auth/email-verification/start",
        json={
            "email": "student@example.com",
            "captcha_id": captcha_id,
            "captcha_answer": answer,
        },
    )
    assert started.status_code == 202
    email_code = app.state.container.email_otp._codes[
        ("student@example.com", EMAIL_VERIFICATION_SCOPE)
    ].code

    response = _confirm(client, email_code)

    assert response.status_code == 422


def test_password_reset_validation_does_not_echo_the_password(
    client: TestClient,
) -> None:
    response = client.post(
        "/auth/password-reset/confirm",
        json={
            "email": "student@example.com",
            "code": "000000",
            "new_password": "Tiny1!",
        },
    )

    assert response.status_code == 422
    assert "Tiny1!" not in response.text


def test_password_reset_recovers_a_locked_account(
    app,
    client: TestClient,
    register,
    recording_email,
) -> None:
    assert register().status_code == 201
    for _ in range(5):
        assert (
            client.post(
                "/auth/login",
                json={
                    "email": "student@example.com",
                    "password": "wrong password",
                },
            ).status_code
            == 401
        )
    assert (
        client.post(
            "/auth/login",
            json={
                "email": "student@example.com",
                "password": COMPLIANT_PASSWORD,
            },
        ).status_code
        == 429
    )

    assert _request_reset(client, app).status_code == 202
    code = _reset_code(app)
    assert _confirm(client, code).status_code == 204

    login = client.post(
        "/auth/login",
        json={
            "email": "student@example.com",
            "password": NEW_PASSWORD,
        },
    )
    assert login.status_code == 200
