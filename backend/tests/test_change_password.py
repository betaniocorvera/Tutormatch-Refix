from __future__ import annotations

from fastapi.testclient import TestClient

from app.services.verification import PASSWORD_RESET_OTP_SCOPE
from tests.registration import COMPLIANT_PASSWORD

NEW_PASSWORD = "NewCorrectHorse2@"
EMAIL = "student@example.com"


def _change(
    client: TestClient,
    headers: dict[str, str],
    *,
    current_password: str = COMPLIANT_PASSWORD,
    new_password: str = NEW_PASSWORD,
):
    return client.post(
        "/auth/password/change",
        headers=headers,
        json={
            "current_password": current_password,
            "new_password": new_password,
        },
    )


def _login(
    client: TestClient,
    password: str = COMPLIANT_PASSWORD,
):
    return client.post(
        "/auth/login",
        json={"email": EMAIL, "password": password},
    )


def _captcha(client: TestClient, app) -> tuple[str, str]:
    challenge = client.get("/auth/captcha").json()
    answer = app.state.container.captcha._sessions[challenge["id"]].answer
    return challenge["id"], answer


def _start_password_reset(client: TestClient, app):
    captcha_id, answer = _captcha(client, app)
    return client.post(
        "/auth/password-reset/request",
        json={
            "email": EMAIL,
            "captcha_id": captcha_id,
            "captcha_answer": answer,
        },
    )


def test_change_password_requires_authentication(
    client: TestClient,
) -> None:
    response = client.post(
        "/auth/password/change",
        json={
            "current_password": COMPLIANT_PASSWORD,
            "new_password": NEW_PASSWORD,
        },
    )

    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"


def test_change_password_rejects_a_wrong_current_password(
    client: TestClient,
    auth_headers: dict[str, str],
    app,
) -> None:
    response = _change(
        client,
        auth_headers,
        current_password="WrongPassword1!",
    )

    assert response.status_code == 422
    assert response.json()["detail"] == "Current password is incorrect."
    assert "WrongPassword1!" not in response.text
    assert _login(client).status_code == 200

    events = app.state.container.security_events.events
    assert [event.event_type for event in events].count(
        "password_change_failed"
    ) == 1


def test_change_password_rejects_the_same_password(
    client: TestClient,
    auth_headers: dict[str, str],
) -> None:
    response = _change(
        client,
        auth_headers,
        current_password=COMPLIANT_PASSWORD,
        new_password=COMPLIANT_PASSWORD,
    )

    assert response.status_code == 422
    assert "different from the current password" in response.json()["detail"]
    assert _login(client).status_code == 200


def test_change_password_rejects_a_weak_password(
    client: TestClient,
    auth_headers: dict[str, str],
) -> None:
    response = _change(
        client,
        auth_headers,
        new_password="alllowercase1",
    )

    assert response.status_code == 422
    assert "upper-case" in response.json()["detail"]
    assert _login(client).status_code == 200


def test_change_password_does_not_echo_short_password(
    client: TestClient,
    auth_headers: dict[str, str],
) -> None:
    response = _change(
        client,
        auth_headers,
        new_password="Tiny1!",
    )

    assert response.status_code == 422
    assert "Tiny1!" not in response.text


def test_change_password_updates_hash_and_revokes_refresh_tokens(
    client: TestClient,
    auth_tokens,
    auth_headers: dict[str, str],
    app,
) -> None:
    first = auth_tokens
    second = _login(client)
    assert second.status_code == 200
    second_body = second.json()

    response = _change(client, auth_headers)

    assert response.status_code == 204
    assert response.content == b""
    assert (
        client.get("/auth/me", headers=auth_headers).status_code == 200
    )

    for refresh_token in (
        first["refresh_token"],
        second_body["refresh_token"],
    ):
        refreshed = client.post(
            "/auth/refresh",
            json={"refresh_token": refresh_token},
        )
        assert refreshed.status_code == 401

    assert _login(client).status_code == 401
    assert _login(client, NEW_PASSWORD).status_code == 200

    events = app.state.container.security_events.events
    assert [event.event_type for event in events].count(
        "password_changed"
    ) == 1
    changed = next(
        event
        for event in events
        if event.event_type == "password_changed"
    )
    assert changed.detail == "signed-in"
    rendered = " ".join(str(event) for event in events)
    assert COMPLIANT_PASSWORD not in rendered
    assert NEW_PASSWORD not in rendered


def test_change_password_clears_a_pending_reset_code(
    client: TestClient,
    auth_tokens,
    auth_headers: dict[str, str],
    app,
    recording_email,
) -> None:
    started = _start_password_reset(client, app)
    assert started.status_code == 202
    key = (EMAIL, PASSWORD_RESET_OTP_SCOPE)
    code = app.state.container.email_otp._codes[key].code

    assert _change(client, auth_headers).status_code == 204
    assert key not in app.state.container.email_otp._codes

    reused = client.post(
        "/auth/password-reset/confirm",
        json={
            "email": EMAIL,
            "code": code,
            "new_password": "AnotherHorse3#",
        },
    )
    assert reused.status_code == 422


def test_change_password_rate_limits_wrong_current_password(
    client: TestClient,
    auth_headers: dict[str, str],
) -> None:
    for _ in range(5):
        assert (
            _change(
                client,
                auth_headers,
                current_password="WrongPassword1!",
            ).status_code
            == 422
        )

    blocked = _change(
        client,
        auth_headers,
        current_password="WrongPassword1!",
    )

    assert blocked.status_code == 429
    assert blocked.headers["Retry-After"]
    assert "password-change" in blocked.json()["detail"]
