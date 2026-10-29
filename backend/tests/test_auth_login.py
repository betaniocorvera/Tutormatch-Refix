from __future__ import annotations

from fastapi.testclient import TestClient

from tests.registration import COMPLIANT_PASSWORD


def test_login_success_is_case_insensitive(
    client: TestClient,
    register,
) -> None:
    assert register(email="student@example.com").status_code == 201

    response = client.post(
        "/auth/login",
        json={
            "email": "STUDENT@example.com",
            "password": COMPLIANT_PASSWORD,
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["user"]["email"] == "student@example.com"
    assert body["access_token"]
    assert body["refresh_token"]


def test_login_wrong_password_and_unknown_email_share_a_generic_error(
    client: TestClient,
    register,
) -> None:
    assert register().status_code == 201

    wrong_password = client.post(
        "/auth/login",
        json={
            "email": "student@example.com",
            "password": "wrong password",
        },
    )
    unknown_email = client.post(
        "/auth/login",
        json={
            "email": "missing@example.com",
            "password": "wrong password",
        },
    )

    assert wrong_password.status_code == 401
    assert unknown_email.status_code == 401
    assert wrong_password.json()["detail"] == (
        unknown_email.json()["detail"]
    ) == "Email or password is incorrect."
    assert wrong_password.headers["www-authenticate"] == "Bearer"


def test_login_rate_limit_blocks_after_five_failures(
    client: TestClient,
    register,
) -> None:
    assert register().status_code == 201

    for _ in range(5):
        failed = client.post(
            "/auth/login",
            json={
                "email": "student@example.com",
                "password": "wrong password",
            },
        )
        assert failed.status_code == 401

    blocked = client.post(
        "/auth/login",
        json={
            "email": "student@example.com",
            "password": COMPLIANT_PASSWORD,
        },
    )

    assert blocked.status_code == 429
    assert blocked.json()["detail"] == (
        "Too many sign-in attempts. Try again later."
    )
    assert int(blocked.headers["retry-after"]) > 0


def test_rate_limit_is_scoped_to_email(
    client: TestClient,
    register,
) -> None:
    assert register(email="one@example.com").status_code == 201
    assert register(email="two@example.com").status_code == 201

    for _ in range(5):
        assert (
            client.post(
                "/auth/login",
                json={
                    "email": "one@example.com",
                    "password": "wrong password",
                },
            ).status_code
            == 401
        )

    assert (
        client.post(
            "/auth/login",
            json={
                "email": "one@example.com",
                "password": "wrong password",
            },
        ).status_code
        == 429
    )
    assert (
        client.post(
            "/auth/login",
            json={
                "email": "two@example.com",
                "password": "wrong password",
            },
        ).status_code
        == 401
    )


def test_successful_login_clears_failure_count(
    client: TestClient,
    register,
) -> None:
    assert register().status_code == 201

    for _ in range(4):
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
        == 200
    )

    # The previous four failures were cleared, so five fresh failures are
    # allowed before the next attempt is blocked.
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


def test_login_rejects_invalid_payloads(
    client: TestClient,
) -> None:
    assert (
        client.post(
            "/auth/login",
            json={"email": "not-an-email", "password": "x"},
        ).status_code
        == 422
    )
    assert (
        client.post(
            "/auth/login",
            json={"email": "a@example.com", "password": ""},
        ).status_code
        == 422
    )
