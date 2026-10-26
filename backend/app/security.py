"""Password hashing and JWT creation/validation."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from uuid import uuid4

from jose import JWTError, jwt
from passlib.context import CryptContext

from .config import Settings
from .errors import InvalidToken
from .models.user import User

ACCESS_TOKEN_TYPE = "access"
REFRESH_TOKEN_TYPE = "refresh"
_ISSUER = "tutormatch"


@dataclass(frozen=True, slots=True)
class IssuedToken:
    token: str
    jti: str
    expires_at: datetime


class PasswordHasher:
    """Argon2id hashing through passlib.

    Argon2 avoids bcrypt's 72-byte input limit and its recent passlib
    compatibility warnings, while still using the required passlib context.
    """

    def __init__(self) -> None:
        self._context = CryptContext(schemes=["argon2"], deprecated="auto")
        # A real hash used to keep the unknown-email login path from being
        # obviously faster than the wrong-password path.
        self._dummy_hash = self._context.hash("not-a-real-password")

    def hash(self, password: str) -> str:
        return self._context.hash(password)

    def verify(self, password: str, password_hash: str) -> bool:
        try:
            return self._context.verify(password, password_hash)
        except (TypeError, ValueError):
            return False

    def verify_dummy(self, password: str) -> None:
        self.verify(password, self._dummy_hash)


class TokenService:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings

    def create_access_token(self, user: User) -> IssuedToken:
        return self._create(
            user,
            ACCESS_TOKEN_TYPE,
            timedelta(minutes=self._settings.access_token_minutes),
        )

    def create_refresh_token(self, user: User) -> IssuedToken:
        return self._create(
            user,
            REFRESH_TOKEN_TYPE,
            timedelta(days=self._settings.refresh_token_days),
        )

    def _create(
        self,
        user: User,
        token_type: str,
        lifetime: timedelta,
    ) -> IssuedToken:
        now = datetime.now(timezone.utc)
        expires_at = now + lifetime
        jti = uuid4().hex
        payload = {
            "sub": user.id,
            "role": user.role.value,
            "type": token_type,
            "jti": jti,
            "iat": now,
            "exp": expires_at,
            "iss": _ISSUER,
        }
        token = jwt.encode(
            payload,
            self._settings.jwt_secret,
            algorithm=self._settings.jwt_algorithm,
        )
        return IssuedToken(token=token, jti=jti, expires_at=expires_at)

    def decode(self, token: str, expected_type: str) -> dict[str, object]:
        try:
            payload = jwt.decode(
                token,
                self._settings.jwt_secret,
                algorithms=[self._settings.jwt_algorithm],
                options={
                    "require_exp": True,
                    "require_sub": True,
                    "require_iat": True,
                },
            )
        except (JWTError, ValueError, TypeError) as exc:
            raise InvalidToken() from exc

        if payload.get("type") != expected_type:
            raise InvalidToken()
        subject = payload.get("sub")
        if not isinstance(subject, str) or not subject:
            raise InvalidToken()
        if expected_type == REFRESH_TOKEN_TYPE:
            jti = payload.get("jti")
            if not isinstance(jti, str) or not jti:
                raise InvalidToken()
        return payload

    def access_expires_in(self) -> int:
        return int(self._settings.access_token_minutes * 60)
