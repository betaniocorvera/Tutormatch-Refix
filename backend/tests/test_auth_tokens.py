from __future__ import annotations

from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient
from jose import jwt


def test_me_requires_a_valid_access_token(
    client: TestClient,
) -> None:
    missing = client.get("/auth/me")
    assert missing.status_code == 401
    assert missing.headers["www-authenticate"] == "Bearer"

    malformed = client.get(
        "/auth/me",
        headers={"Authorization": "Bearer not-a-token"},
    )
    assert malformed.status_code == 401


def test_me_returns_the_current_user(
    client: TestClient,
    auth_tokens,
    auth_headers,
) -> None:
    response = client.get("/auth/me", headers=auth_headers)

    assert response.status_code == 200
    body = response.json()
    assert body["id"] == auth_tokens["user"]["id"]
    assert body["email"] == "student@example.com"
    assert "password_hash" not in body


def test_expired_access_token_is_rejected(
    client: TestClient,
    settings,
    auth_tokens,
) -> None:
    now = datetime.now(timezone.utc)
    expired = jwt.encode(
        {
            "sub": auth_tokens["user"]["id"],
            "role": "student",
            "type": "access",
            "jti": "expired",
            "iat": now - timedelta(hours=2),
            "exp": now - timedelta(hours=1),
            "iss": "tutormatch",
        },
        settings.jwt_secret,
        algorithm=settings.jwt_algorithm,
    )

    response = client.get(
        "/auth/me",
        headers={"Authorization": f"Bearer {expired}"},
    )

    assert response.status_code == 401


def test_token_for_unknown_user_is_rejected(
    client: TestClient,
    settings,
) -> None:
    now = datetime.now(timezone.utc)
    token = jwt.encode(
        {
            "sub": "missing-user",
            "role": "student",
            "type": "access",
            "jti": "missing",
            "iat": now,
            "exp": now + timedelta(minutes=5),
            "iss": "tutormatch",
        },
        settings.jwt_secret,
        algorithm=settings.jwt_algorithm,
    )

    response = client.get(
        "/auth/me",
        headers={"Authorization": f"Bearer {token}"},
    )

    assert response.status_code == 401


def test_tampered_access_token_is_rejected(
    client: TestClient,
    auth_tokens,
) -> None:
    response = client.get(
        "/auth/me",
        headers={
            "Authorization": f"Bearer {auth_tokens['access_token']}x"
        },
    )

    assert response.status_code == 401


def test_refresh_rotates_and_old_refresh_token_cannot_be_reused(
    client: TestClient,
    auth_tokens,
) -> None:
    old_refresh = auth_tokens["refresh_token"]

    refreshed = client.post(
        "/auth/refresh",
        json={"refresh_token": old_refresh},
    )

    assert refreshed.status_code == 200
    body = refreshed.json()
    assert body["refresh_token"] != old_refresh
    assert body["access_token"]
    assert body["user"]["id"] == auth_tokens["user"]["id"]

    reused = client.post(
        "/auth/refresh",
        json={"refresh_token": old_refresh},
    )
    assert reused.status_code == 401

    me = client.get(
        "/auth/me",
        headers={"Authorization": f"Bearer {body['access_token']}"},
    )
    assert me.status_code == 200


def test_refresh_rejects_access_token(
    client: TestClient,
    auth_tokens,
) -> None:
    response = client.post(
        "/auth/refresh",
        json={"refresh_token": auth_tokens["access_token"]},
    )

    assert response.status_code == 401


def test_refresh_token_cannot_be_used_as_access_token(
    client: TestClient,
    auth_tokens,
) -> None:
    response = client.get(
        "/auth/me",
        headers={
            "Authorization": f"Bearer {auth_tokens['refresh_token']}"
        },
    )

    assert response.status_code == 401


def test_logout_revokes_the_supplied_refresh_token(
    client: TestClient,
    auth_tokens,
    auth_headers,
) -> None:
    response = client.post(
        "/auth/logout",
        headers=auth_headers,
        json={"refresh_token": auth_tokens["refresh_token"]},
    )

    assert response.status_code == 204
    assert response.content == b""

    refresh = client.post(
        "/auth/refresh",
        json={"refresh_token": auth_tokens["refresh_token"]},
    )
    assert refresh.status_code == 401


def test_logout_without_body_revokes_all_user_refresh_tokens(
    client: TestClient,
    register,
) -> None:
    first = register()
    assert first.status_code == 201
    first_body = first.json()

    second = client.post(
        "/auth/login",
        json={
            "email": "student@example.com",
            "password": "correct horse battery",
        },
    )
    assert second.status_code == 200
    second_body = second.json()

    logout = client.post(
        "/auth/logout",
        headers={
            "Authorization": f"Bearer {first_body['access_token']}"
        },
    )
    assert logout.status_code == 204

    for refresh_token in (
        first_body["refresh_token"],
        second_body["refresh_token"],
    ):
        assert (
            client.post(
                "/auth/refresh",
                json={"refresh_token": refresh_token},
            ).status_code
            == 401
        )


def test_logout_is_idempotent(
    client: TestClient,
    auth_tokens,
    auth_headers,
) -> None:
    body = {"refresh_token": auth_tokens["refresh_token"]}
    assert (
        client.post(
            "/auth/logout",
            headers=auth_headers,
            json=body,
        ).status_code
        == 204
    )
    assert (
        client.post(
            "/auth/logout",
            headers=auth_headers,
            json=body,
        ).status_code
        == 204
    )


def test_logout_requires_authentication(
    client: TestClient,
) -> None:
    assert (
        client.post(
            "/auth/logout",
            json={"refresh_token": "anything"},
        ).status_code
        == 401
    )
