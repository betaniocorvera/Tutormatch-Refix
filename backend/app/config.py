"""Application configuration.

Values come from environment variables (optionally loaded from ``backend/.env``).
No secret has a committed default: a missing ``JWT_SECRET`` is only tolerated
outside production, where an ephemeral development secret is generated so the
app can start without one. Production must provide a real secret.
"""

from __future__ import annotations

import logging
import os
import secrets
from dataclasses import dataclass, field
from pathlib import Path

from dotenv import load_dotenv

logger = logging.getLogger(__name__)

BACKEND_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_STORE_PATH = BACKEND_ROOT / "data" / "store.json"
DEFAULT_UPLOAD_PATH = BACKEND_ROOT / "data" / "uploads"
_ALLOWED_ALGORITHMS = frozenset({"HS256", "HS384", "HS512"})
_EXAMPLE_JWT_SECRET = (
    "replace-with-a-long-random-string-at-least-32-characters"
)
_ALLOWED_DATABASE_SSL_MODES = frozenset(
    {"", "disable", "allow", "prefer", "require", "verify-ca", "verify-full"}
)


def _normalize_database_url(name: str, value: str) -> str:
    """Return a psycopg 3 SQLAlchemy URL, or an empty string.

    ``postgresql://`` is accepted as a convenience and rewritten to the
    explicitly installed psycopg 3 driver. This prevents SQLAlchemy from
    silently looking for psycopg2.
    """

    cleaned = value.strip()
    if not cleaned:
        return ""
    if cleaned.startswith("postgresql://"):
        cleaned = "postgresql+psycopg://" + cleaned[len("postgresql://") :]
    if not cleaned.startswith("postgresql+psycopg://"):
        raise ValueError(
            f"{name} must be a PostgreSQL URL using psycopg 3 "
            "(postgresql+psycopg://...)"
        )
    return cleaned


def _env_bool(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    normalized = raw.strip().lower()
    if normalized in {"1", "true", "yes", "on"}:
        return True
    if normalized in {"0", "false", "no", "off"}:
        return False
    raise ValueError(f"{name} must be true or false")


def _env_int(name: str, default: int) -> int:
    raw = os.getenv(name)
    if raw is None:
        return default
    try:
        return int(raw)
    except ValueError as exc:
        raise ValueError(f"{name} must be an integer") from exc


def _env_float(name: str, default: float) -> float:
    raw = os.getenv(name)
    if raw is None:
        return default
    try:
        return float(raw)
    except ValueError as exc:
        raise ValueError(f"{name} must be a number") from exc


@dataclass(frozen=True, slots=True)
class Settings:
    """Runtime settings shared by the app and its tests."""

    app_env: str = "development"
    jwt_secret: str = ""
    jwt_algorithm: str = "HS256"
    access_token_minutes: int = 15
    refresh_token_days: int = 7
    persist_to_file: bool = False
    storage_backend: str = "memory"
    store_path: Path = DEFAULT_STORE_PATH
    upload_path: Path = DEFAULT_UPLOAD_PATH
    snapshot_debounce_seconds: float = 0.5
    login_rate_limit_attempts: int = 5
    login_rate_limit_window_seconds: int = 900
    cors_origins: tuple[str, ...] = ("http://localhost:8080",)
    secret_is_ephemeral: bool = False
    database_url: str = field(default="", repr=False)
    test_database_url: str = field(default="", repr=False)
    database_pool_size: int = 5
    database_max_overflow: int = 10
    database_pool_timeout_seconds: float = 30.0
    database_echo: bool = False
    database_ssl_mode: str = ""

    def __post_init__(self) -> None:
        env = self.app_env.strip().lower()
        if env not in {"development", "test", "production"}:
            raise ValueError("APP_ENV must be development, test, or production")
        object.__setattr__(self, "app_env", env)
        if self.jwt_algorithm not in _ALLOWED_ALGORITHMS:
            raise ValueError(
                "JWT_ALGORITHM must be one of HS256, HS384, or HS512"
            )
        if self.access_token_minutes <= 0:
            raise ValueError("ACCESS_TOKEN_MINUTES must be positive")
        if self.refresh_token_days <= 0:
            raise ValueError("REFRESH_TOKEN_DAYS must be positive")
        if self.login_rate_limit_attempts <= 0:
            raise ValueError("LOGIN_RATE_LIMIT_ATTEMPTS must be positive")
        if self.login_rate_limit_window_seconds <= 0:
            raise ValueError("LOGIN_RATE_LIMIT_WINDOW_SECONDS must be positive")
        if self.snapshot_debounce_seconds < 0:
            raise ValueError("SNAPSHOT_DEBOUNCE_SECONDS cannot be negative")
        for origin in self.cors_origins:
            if not origin.startswith(("http://", "https://")):
                raise ValueError("CORS_ORIGINS entries must be http(s) origins")
            if origin.endswith("/"):
                raise ValueError("CORS_ORIGINS entries must not end with /")

        object.__setattr__(
            self,
            "database_url",
            _normalize_database_url("DATABASE_URL", self.database_url),
        )
        object.__setattr__(
            self,
            "test_database_url",
            _normalize_database_url(
                "TEST_DATABASE_URL",
                self.test_database_url,
            ),
        )
        storage_backend = self.storage_backend.strip().lower()
        if storage_backend not in {"memory", "postgres"}:
            raise ValueError(
                "STORAGE_BACKEND must be memory or postgres"
            )
        object.__setattr__(self, "storage_backend", storage_backend)
        if storage_backend == "postgres" and not self.database_url:
            raise ValueError(
                "DATABASE_URL is required when STORAGE_BACKEND=postgres"
            )
        if storage_backend == "postgres" and self.persist_to_file:
            raise ValueError(
                "PERSIST_TO_FILE is only supported with "
                "STORAGE_BACKEND=memory"
            )
        if self.database_pool_size <= 0:
            raise ValueError("DATABASE_POOL_SIZE must be positive")
        if self.database_max_overflow < 0:
            raise ValueError("DATABASE_MAX_OVERFLOW cannot be negative")
        if self.database_pool_timeout_seconds <= 0:
            raise ValueError(
                "DATABASE_POOL_TIMEOUT_SECONDS must be positive"
            )
        ssl_mode = self.database_ssl_mode.strip().lower()
        if ssl_mode not in _ALLOWED_DATABASE_SSL_MODES:
            raise ValueError(
                "DATABASE_SSL_MODE must be blank or one of "
                "disable, allow, prefer, require, verify-ca, verify-full"
            )
        object.__setattr__(self, "database_ssl_mode", ssl_mode)

        secret = self.jwt_secret
        if not secret:
            if env == "production":
                raise ValueError("JWT_SECRET is required when APP_ENV=production")
            secret = secrets.token_urlsafe(48)
            object.__setattr__(self, "jwt_secret", secret)
            object.__setattr__(self, "secret_is_ephemeral", True)
        elif len(secret) < 32:
            raise ValueError("JWT_SECRET must be at least 32 characters")
        elif secret == _EXAMPLE_JWT_SECRET:
            if env == "production":
                raise ValueError(
                    "JWT_SECRET still has the example value; "
                    "set a unique secret for production"
                )
            logger.warning(
                "JWT_SECRET still has the example value; "
                "replace it before deploying."
            )

        path = Path(self.store_path)
        if not path.is_absolute():
            path = BACKEND_ROOT / path
        object.__setattr__(self, "store_path", path)

        upload_path = Path(self.upload_path)
        if not upload_path.is_absolute():
            upload_path = BACKEND_ROOT / upload_path
        object.__setattr__(self, "upload_path", upload_path)

        if self.secret_is_ephemeral:
            logger.warning(
                "JWT_SECRET is not set; using an ephemeral development secret. "
                "Tokens will be invalid after restart."
            )

    @classmethod
    def from_env(cls) -> "Settings":
        load_dotenv(BACKEND_ROOT / ".env", override=False)
        raw_store_path = os.getenv("STORE_PATH", "").strip()
        store_path = (
            Path(raw_store_path) if raw_store_path else DEFAULT_STORE_PATH
        )
        raw_upload_path = os.getenv("UPLOAD_DIR", "").strip()
        upload_path = (
            Path(raw_upload_path)
            if raw_upload_path
            else DEFAULT_UPLOAD_PATH
        )
        raw_origins = os.getenv("CORS_ORIGINS", "").strip()
        cors_origins = (
            tuple(
                origin.strip()
                for origin in raw_origins.split(",")
                if origin.strip()
            )
            if raw_origins
            else ("http://localhost:8080",)
        )
        return cls(
            app_env=os.getenv("APP_ENV", "development"),
            jwt_secret=os.getenv("JWT_SECRET", ""),
            jwt_algorithm=os.getenv("JWT_ALGORITHM", "HS256"),
            access_token_minutes=_env_int("ACCESS_TOKEN_MINUTES", 15),
            refresh_token_days=_env_int("REFRESH_TOKEN_DAYS", 7),
            persist_to_file=_env_bool("PERSIST_TO_FILE", False),
            storage_backend=os.getenv("STORAGE_BACKEND", "memory"),
            store_path=store_path,
            upload_path=upload_path,
            snapshot_debounce_seconds=_env_float(
                "SNAPSHOT_DEBOUNCE_SECONDS", 0.5
            ),
            login_rate_limit_attempts=_env_int("LOGIN_RATE_LIMIT_ATTEMPTS", 5),
            login_rate_limit_window_seconds=_env_int(
                "LOGIN_RATE_LIMIT_WINDOW_SECONDS", 900
            ),
            cors_origins=cors_origins,
            database_url=os.getenv("DATABASE_URL", ""),
            test_database_url=os.getenv("TEST_DATABASE_URL", ""),
            database_pool_size=_env_int("DATABASE_POOL_SIZE", 5),
            database_max_overflow=_env_int("DATABASE_MAX_OVERFLOW", 10),
            database_pool_timeout_seconds=_env_float(
                "DATABASE_POOL_TIMEOUT_SECONDS", 30.0
            ),
            database_echo=_env_bool("DATABASE_ECHO", False),
            database_ssl_mode=os.getenv("DATABASE_SSL_MODE", ""),
        )
