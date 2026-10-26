from __future__ import annotations

from uuid import uuid4

from fastapi.testclient import TestClient


def test_public_user_view_excludes_private_fields(
    client: TestClient,
    auth_tokens,
    auth_headers,
) -> None:
    user_id = auth_tokens["user"]["id"]

    response = client.get(f"/users/{user_id}", headers=auth_headers)

    assert response.status_code == 200
    body = response.json()
    assert body["id"] == user_id
    assert body["role"] == "student"
    assert body["display_name"] == "Maya Chen"
    assert "email" not in body
    assert "password_hash" not in body
    assert "onboarding_complete" not in body


def test_public_user_view_requires_authentication(
    client: TestClient,
    auth_tokens,
) -> None:
    response = client.get(f"/users/{auth_tokens['user']['id']}")
    assert response.status_code == 401


def test_unknown_public_user_returns_404(
    client: TestClient,
    auth_headers,
) -> None:
    response = client.get(
        f"/users/{uuid4()}",
        headers=auth_headers,
    )
    assert response.status_code == 404


def test_one_user_can_see_another_public_profile_without_email(
    client: TestClient,
    register,
) -> None:
    first = register(email="first@example.com")
    second = register(email="second@example.com")
    assert first.status_code == 201
    assert second.status_code == 201

    first_body = first.json()
    second_body = second.json()

    public = client.get(
        f"/users/{second_body['user']['id']}",
        headers={
            "Authorization": f"Bearer {first_body['access_token']}"
        },
    )
    assert public.status_code == 200
    assert "email" not in public.json()

    me = client.get(
        "/auth/me",
        headers={
            "Authorization": f"Bearer {first_body['access_token']}"
        },
    )
    assert me.status_code == 200
    assert me.json()["id"] == first_body["user"]["id"]
    assert me.json()["email"] == "first@example.com"
