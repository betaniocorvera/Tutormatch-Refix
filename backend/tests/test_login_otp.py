from __future__ import annotations

from dataclasses import replace

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from app.services.lockout import AccountLockout
from tests.registration import COMPLIANT_PASSWORD, registration_payload


@pytest.fixture()
def otp_app(settings: Settings, email_outbox):
    app = create_app(replace(settings, login_otp_required=True))
    app.state.container.email.transport = email_outbox
    return app


@pytest.fixture()
def otp_client(otp_app):
    with TestClient(otp_app) as client:
        yield client


def _register(client: TestClient, email: str = "student@example.com"):
    return client.post(
        "/auth/register",
        json=registration_payload(email=email),
    )


def _login(client: TestClient, email: str = "student@example.com"):
    return client.post(
        "/auth/login",
        json={"email": email, "password": COMPLIANT_PASSWORD},
    )


def test_login_returns_an_otp_challenge_instead_of_tokens(
    otp_app,
    otp_client: TestClient,
    email_outbox,
) -> None:
    assert _register(otp_client).status_code == 201

    response = _login(otp_client)

    assert response.status_code == 202
    body = response.json()
    assert body["otp_required"] is True
    assert body["challenge_id"]
    assert body["expires_at"]
    assert "access_token" not in body
    assert "refresh_token" not in body
    assert "code" not in body
    assert len(email_outbox.messages) == 1
    code = otp_app.state.container.email_otp._codes[
        "student@example.com"
    ].code
    assert email_outbox.messages[0].to == "student@example.com"
    assert code in email_outbox.messages[0].body
    events = otp_app.state.container.security_events.events
    assert [event.event_type for event in events].count("login_otp_sent") == 1


def test_login_otp_delivery_failure_does_not_issue_a_challenge(
    settings: Settings,
) -> None:
    app = create_app(replace(settings, login_otp_required=True))
    with TestClient(app) as client:
        assert _register(client).status_code == 201

        response = _login(client)

    assert response.status_code == 503
    assert "code" not in response.json()
    assert app.state.container.email_otp._codes == {}
    assert app.state.container.login_otp_challenges._by_id == {}
    events = app.state.container.security_events.events
    assert [event.event_type for event in events].count("login_otp_sent") == 0


def test_login_otp_verifies_once_and_issues_tokens(
    otp_app,
    otp_client: TestClient,
) -> None:
    assert _register(otp_client).status_code == 201
    challenge = _login(otp_client).json()
    code = otp_app.state.container.email_otp._codes[
        "student@example.com"
    ].code

    response = otp_client.post(
        "/auth/login/otp/verify",
        json={
            "challenge_id": challenge["challenge_id"],
            "code": code,
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["access_token"]
    assert body["refresh_token"]
    assert body["user"]["email"] == "student@example.com"

    reused = otp_client.post(
        "/auth/login/otp/verify",
        json={
            "challenge_id": challenge["challenge_id"],
            "code": code,
        },
    )
    assert reused.status_code == 422

    events = otp_app.state.container.security_events.events
    assert [event.event_type for event in events].count("login_otp_verified") == 1
    assert any(
        event.event_type == "login_succeeded" and event.detail == "otp"
        for event in events
    )


def test_login_otp_rejects_wrong_codes_without_tokens(
    otp_app,
    otp_client: TestClient,
) -> None:
    assert _register(otp_client).status_code == 201
    challenge = _login(otp_client).json()
    actual = otp_app.state.container.email_otp._codes[
        "student@example.com"
    ].code
    wrong = "000000" if actual != "000000" else "111111"

    response = otp_client.post(
        "/auth/login/otp/verify",
        json={
            "challenge_id": challenge["challenge_id"],
            "code": wrong,
        },
    )

    assert response.status_code == 422
    assert "access_token" not in response.json()
    events = otp_app.state.container.security_events.events
    assert [event.event_type for event in events].count("login_otp_failed") == 1


def test_security_events_do_not_store_passwords_or_otp_codes(
    otp_app,
    otp_client: TestClient,
) -> None:
    assert _register(otp_client).status_code == 201
    challenge = _login(otp_client).json()
    code = otp_app.state.container.email_otp._codes[
        "student@example.com"
    ].code
    otp_client.post(
        "/auth/login",
        json={
            "email": "student@example.com",
            "password": "wrong password",
        },
    )

    rendered = " ".join(
        str(event) for event in otp_app.state.container.security_events.events
    )
    assert "wrong password" not in rendered
    assert code not in rendered
    assert challenge["challenge_id"] not in rendered


def test_wrong_password_never_creates_an_otp_challenge(
    otp_app,
    otp_client: TestClient,
) -> None:
    assert _register(otp_client).status_code == 201

    response = otp_client.post(
        "/auth/login",
        json={
            "email": "student@example.com",
            "password": "wrong password",
        },
    )

    assert response.status_code == 401
    assert otp_app.state.container.login_otp_challenges._by_id == {}


def test_account_lockout_is_scoped_to_one_email() -> None:
    now = [100.0]
    lockout = AccountLockout(2, 60, clock=lambda: now[0])

    assert lockout.record_failure("one@example.com") is False
    assert lockout.record_failure("one@example.com") is True
    assert lockout.check("one@example.com") == 60
    assert lockout.check("two@example.com") is None

    now[0] += 61
    assert lockout.check("one@example.com") is None
    assert lockout.record_failure("two@example.com") is False


def test_login_lockout_records_an_alert_event(
    otp_app,
    otp_client: TestClient,
) -> None:
    assert _register(otp_client).status_code == 201

    for _ in range(5):
        response = otp_client.post(
            "/auth/login",
            json={
                "email": "student@example.com",
                "password": "wrong password",
            },
        )
        assert response.status_code == 401

    blocked = _login(otp_client)
    assert blocked.status_code == 429

    events = otp_app.state.container.security_events.events
    assert [event.event_type for event in events].count("account_locked") == 1
    assert [event.event_type for event in events].count("login_failed") == 5


def test_login_success_records_an_alert_event(
    client: TestClient,
    register,
    app,
) -> None:
    assert register().status_code == 201

    response = client.post(
        "/auth/login",
        json={
            "email": "student@example.com",
            "password": COMPLIANT_PASSWORD,
        },
    )

    assert response.status_code == 200
    events = app.state.container.security_events.events
    assert any(
        event.event_type == "login_succeeded"
        and event.detail == "password"
        for event in events
    )
