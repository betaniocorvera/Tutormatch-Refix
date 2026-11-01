"""HTTP hardening: headers, trusted hosts, body limits, and settings."""

from __future__ import annotations

from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app


def test_security_headers_are_present_on_api_responses(
    client: TestClient,
) -> None:
    response = client.get("/health")

    assert response.status_code == 200
    assert response.headers["x-content-type-options"] == "nosniff"
    assert response.headers["x-frame-options"] == "DENY"
    assert response.headers["referrer-policy"] == "no-referrer"
    assert "camera=()" in response.headers["permissions-policy"]
    assert "default-src 'none'" in response.headers[
        "content-security-policy"
    ]
    assert "strict-transport-security" not in response.headers


def test_security_headers_are_present_on_errors(client: TestClient) -> None:
    response = client.get("/does-not-exist")

    assert response.status_code == 404
    assert response.headers["x-content-type-options"] == "nosniff"


def test_auth_responses_are_not_cached(client: TestClient) -> None:
    response = client.get("/auth/captcha")

    assert response.status_code == 200
    assert response.headers["cache-control"] == "no-store"
    assert response.headers["pragma"] == "no-cache"


def test_production_adds_hsts() -> None:
    settings = Settings(
        app_env="production",
        jwt_secret="s" * 64,
        allowed_hosts=("testserver",),
    )
    app = create_app(settings)

    with TestClient(app) as client:
        response = client.get("/health")

    assert response.status_code == 200
    assert response.headers["strict-transport-security"] == (
        "max-age=31536000; includeSubDomains"
    )


def test_trusted_hosts_reject_an_unlisted_host() -> None:
    settings = Settings(
        jwt_secret="s" * 64,
        allowed_hosts=("example.com",),
    )
    app = create_app(settings)

    with TestClient(app) as client:
        allowed = client.get(
            "/health",
            headers={"Host": "example.com"},
        )
        rejected = client.get(
            "/health",
            headers={"Host": "evil.example"},
        )

    assert allowed.status_code == 200
    assert rejected.status_code == 400


def test_json_body_limit_rejects_an_oversized_request() -> None:
    settings = Settings(
        jwt_secret="s" * 64,
        max_json_body_bytes=50,
    )
    app = create_app(settings)

    with TestClient(app) as client:
        response = client.post(
            "/auth/login",
            json={
                "email": "student@example.com",
                "password": "x" * 100,
            },
        )

    assert response.status_code == 413
    assert response.json()["detail"] == "Request body is too large."


def test_from_env_reads_http_security_settings(monkeypatch) -> None:
    monkeypatch.setenv("JWT_SECRET", "s" * 64)
    monkeypatch.setenv("ALLOWED_HOSTS", "api.example.com, www.example.com")
    monkeypatch.setenv("MAX_JSON_BODY_BYTES", "2048")
    monkeypatch.setenv("CAPTCHA_RATE_LIMIT_ATTEMPTS", "12")
    monkeypatch.setenv("CAPTCHA_RATE_LIMIT_WINDOW_SECONDS", "60")
    monkeypatch.setenv("EMAIL_VERIFICATION_RATE_LIMIT_ATTEMPTS", "4")
    monkeypatch.setenv(
        "EMAIL_VERIFICATION_RATE_LIMIT_WINDOW_SECONDS",
        "120",
    )

    settings = Settings.from_env()

    assert settings.allowed_hosts == (
        "api.example.com",
        "www.example.com",
    )
    assert settings.max_json_body_bytes == 2048
    assert settings.captcha_rate_limit_attempts == 12
    assert settings.captcha_rate_limit_window_seconds == 60
    assert settings.email_verification_rate_limit_attempts == 4
    assert settings.email_verification_rate_limit_window_seconds == 120


def test_production_requires_explicit_allowed_hosts(monkeypatch) -> None:
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("JWT_SECRET", "s" * 64)
    monkeypatch.setenv("ALLOWED_HOSTS", "")

    try:
        Settings.from_env()
    except ValueError as error:
        assert "ALLOWED_HOSTS" in str(error)
    else:  # pragma: no cover - the assertion above is the point
        raise AssertionError("production started without ALLOWED_HOSTS")


def test_allowed_hosts_reject_wildcards() -> None:
    try:
        Settings(jwt_secret="s" * 64, allowed_hosts=("*",))
    except ValueError as error:
        assert "ALLOWED_HOSTS" in str(error)
    else:  # pragma: no cover - the assertion above is the point
        raise AssertionError("a wildcard host was accepted")


def test_max_json_body_bytes_must_be_positive() -> None:
    try:
        Settings(jwt_secret="s" * 64, max_json_body_bytes=0)
    except ValueError as error:
        assert "MAX_JSON_BODY_BYTES" in str(error)
    else:  # pragma: no cover - the assertion above is the point
        raise AssertionError("a zero body limit was accepted")


def test_captcha_rate_limits_must_be_positive() -> None:
    try:
        Settings(jwt_secret="s" * 64, captcha_rate_limit_attempts=0)
    except ValueError as error:
        assert "CAPTCHA_RATE_LIMIT_ATTEMPTS" in str(error)
    else:  # pragma: no cover - the assertion above is the point
        raise AssertionError("a zero CAPTCHA limit was accepted")
