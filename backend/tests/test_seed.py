from __future__ import annotations

import io

import pytest
from fastapi.testclient import TestClient

from scripts.seed_dev import (
    DEMO_ACCOUNTS,
    DEMO_PASSWORD,
    SeedError,
    assert_development,
    confirm_seed,
    normalize_api_url,
    seed_demo_accounts,
)
from tests.registration import registration_payload


def _login(client: TestClient, email: str, password: str = DEMO_PASSWORD):
    return client.post(
        "/auth/login",
        json={"email": email, "password": password},
    )


def _auth_headers(tokens: dict) -> dict[str, str]:
    return {"Authorization": f"Bearer {tokens['access_token']}"}


def test_seed_creates_two_complete_demo_accounts(
    client: TestClient,
) -> None:
    results = seed_demo_accounts(client)

    assert [result.created for result in results] == [True, True]
    assert {result.email for result in results} == {
        account.email for account in DEMO_ACCOUNTS
    }

    users = client.app.state.container.users.list_all()
    assert len(users) == 2
    assert {user.email for user in users} == {
        account.email for account in DEMO_ACCOUNTS
    }
    assert {user.role.value for user in users} == {"student", "tutor"}
    assert all(user.onboarding_complete for user in users)

    for account in DEMO_ACCOUNTS:
        tokens = _login(client, account.email).json()
        profile = client.get(
            "/profile",
            headers=_auth_headers(tokens),
        )
        assert profile.status_code == 200
        body = profile.json()
        assert body["name"] == account.display_name
        assert body["onboarding_complete"] is True
        assert body["subjects"] == account.profile["subjects"]
        assert body["area_id"] == "london-highbury"
        assert body["public_location"] is not None
        assert body["availability"] == account.profile["availability"]


def test_seed_is_idempotent(client: TestClient) -> None:
    seed_demo_accounts(client)

    second_run = seed_demo_accounts(client)

    assert [result.created for result in second_run] == [False, False]
    assert len(client.app.state.container.users.list_all()) == 2
    assert len(client.app.state.container.profiles.list_all()) == 2


def test_seeded_student_and_tutor_match_each_other(
    client: TestClient,
) -> None:
    seed_demo_accounts(client)
    maya = next(
        account for account in DEMO_ACCOUNTS if account.role == "student"
    )
    amara = next(
        account for account in DEMO_ACCOUNTS if account.role == "tutor"
    )

    tokens = _login(client, maya.email).json()
    response = client.get("/matches", headers=_auth_headers(tokens))

    assert response.status_code == 200
    body = response.json()
    assert body["cold_start"] is None
    assert len(body["matches"]) == 1
    match = body["matches"][0]
    assert match["profile"]["id"] == next(
        user.id
        for user in client.app.state.container.users.list_all()
        if user.email == amara.email
    )
    assert match["score"] >= 80
    assert match["tier"] == "strong"


def test_seed_refuses_an_existing_account_with_a_different_password(
    client: TestClient,
) -> None:
    maya = DEMO_ACCOUNTS[0]
    response = client.post(
        "/auth/register",
        json=registration_payload(
            email=maya.email,
            password="A different password 123!",
            role=maya.role,
            display_name="Not Maya",
        ),
    )
    assert response.status_code == 201

    with pytest.raises(SeedError, match="demo password"):
        seed_demo_accounts(client)


def test_seed_refuses_an_existing_account_with_the_wrong_role(
    client: TestClient,
) -> None:
    maya = DEMO_ACCOUNTS[0]
    response = client.post(
        "/auth/register",
        json=registration_payload(
            email=maya.email,
            password=DEMO_PASSWORD,
            role="tutor",
            display_name="Not Maya",
        ),
    )
    assert response.status_code == 201

    with pytest.raises(SeedError, match="role"):
        seed_demo_accounts(client)


def test_production_is_refused() -> None:
    with pytest.raises(SeedError, match="production"):
        assert_development("production")


def test_api_url_is_local_only_by_default() -> None:
    assert normalize_api_url("http://127.0.0.1:8000/") == (
        "http://127.0.0.1:8000"
    )
    assert normalize_api_url("http://localhost:8000") == (
        "http://localhost:8000"
    )

    with pytest.raises(SeedError, match="non-local"):
        normalize_api_url("https://api.example.com")

    assert normalize_api_url(
        "https://api.example.com",
        allow_remote=True,
    ) == "https://api.example.com"

    with pytest.raises(SeedError, match="http"):
        normalize_api_url("127.0.0.1:8000")


def test_confirmation_requires_a_terminal(monkeypatch) -> None:
    monkeypatch.setattr("sys.stdin", io.StringIO(""))
    with pytest.raises(SeedError, match="--yes"):
        confirm_seed(assume_yes=False, api_url="http://127.0.0.1:8000")

    confirm_seed(assume_yes=True, api_url="http://127.0.0.1:8000")
