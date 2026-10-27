from __future__ import annotations

from fastapi.testclient import TestClient

from app.config import Settings


def test_flutter_web_origin_is_allowed(client: TestClient) -> None:
    response = client.get(
        "/health",
        headers={"Origin": "http://localhost:8080"},
    )

    assert response.status_code == 200
    assert (
        response.headers["access-control-allow-origin"]
        == "http://localhost:8080"
    )


def test_flutter_web_preflight_is_allowed(client: TestClient) -> None:
    response = client.options(
        "/matches",
        headers={
            "Origin": "http://localhost:8080",
            "Access-Control-Request-Method": "GET",
            "Access-Control-Request-Headers": "authorization",
        },
    )

    assert response.status_code == 200
    assert (
        response.headers["access-control-allow-origin"]
        == "http://localhost:8080"
    )
    assert "authorization" in response.headers[
        "access-control-allow-headers"
    ].lower()


def test_other_origins_are_not_allowed(client: TestClient) -> None:
    response = client.get(
        "/health",
        headers={"Origin": "http://localhost:5173"},
    )

    assert response.status_code == 200
    assert "access-control-allow-origin" not in response.headers


def test_cors_origins_are_configurable(settings: Settings) -> None:
    configured = Settings(
        app_env="test",
        jwt_secret=settings.jwt_secret,
        cors_origins=("https://app.example",),
    )

    assert configured.cors_origins == ("https://app.example",)


def test_cors_origins_reject_non_http_values() -> None:
    try:
        Settings(
            app_env="test",
            jwt_secret="s" * 64,
            cors_origins=("ftp://example.com",),
        )
    except ValueError as error:
        assert "CORS_ORIGINS" in str(error)
    else:  # pragma: no cover - the assertion above is the point
        raise AssertionError("a non-http origin was accepted")


def test_cors_origins_reject_trailing_slashes() -> None:
    try:
        Settings(
            app_env="test",
            jwt_secret="s" * 64,
            cors_origins=("http://localhost:8080/",),
        )
    except ValueError as error:
        assert "CORS_ORIGINS" in str(error)
    else:  # pragma: no cover - the assertion above is the point
        raise AssertionError("a trailing slash was accepted")
