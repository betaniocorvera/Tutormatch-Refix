"""Authentication service: registration, login, refresh, logout, and views."""

from __future__ import annotations

import threading
from dataclasses import dataclass
from datetime import datetime, timezone
from uuid import uuid4

from ..errors import (
    DuplicateEmailError,
    EmailAlreadyRegistered,
    InvalidCredentials,
    InvalidToken,
    RateLimited,
)
from ..models.auth import RefreshToken
from ..models.user import Role, User, UserMe
from ..repositories.interfaces import (
    RefreshTokenRepository,
    UserRepository,
)
from ..security import (
    ACCESS_TOKEN_TYPE,
    REFRESH_TOKEN_TYPE,
    IssuedToken,
    PasswordHasher,
    TokenService,
)
from .rate_limit import LoginRateLimiter


@dataclass(frozen=True, slots=True)
class AuthResult:
    user: User
    access: IssuedToken
    refresh: IssuedToken


class AuthService:
    def __init__(
        self,
        *,
        users: UserRepository,
        refresh_tokens: RefreshTokenRepository,
        passwords: PasswordHasher,
        tokens: TokenService,
        rate_limiter: LoginRateLimiter,
    ) -> None:
        self._users = users
        self._refresh_tokens = refresh_tokens
        self._passwords = passwords
        self._tokens = tokens
        self._rate_limiter = rate_limiter
        # Refresh rotation is a check-then-write operation. Without this lock,
        # two concurrent uses of the same refresh token could both succeed.
        self._refresh_lock = threading.Lock()

    def register(
        self,
        *,
        email: str,
        password: str,
        role: Role,
        display_name: str,
    ) -> AuthResult:
        normalized_email = self._normalize_email(email)
        if self._users.get_by_email(normalized_email) is not None:
            raise EmailAlreadyRegistered()

        now = datetime.now(timezone.utc)
        user = User(
            id=str(uuid4()),
            email=normalized_email,
            password_hash=self._passwords.hash(password),
            role=role,
            display_name=display_name.strip(),
            onboarding_complete=False,
            created_at=now,
            updated_at=now,
        )
        try:
            self._users.add(user)
        except DuplicateEmailError as exc:
            # A concurrent registration won the race.
            raise EmailAlreadyRegistered() from exc

        return self._issue_tokens(user)

    def login(
        self,
        *,
        email: str,
        password: str,
        client_key: str,
    ) -> AuthResult:
        normalized_email = self._normalize_email(email)
        rate_key = self._rate_key(client_key, normalized_email)

        retry_after = self._rate_limiter.check(rate_key)
        if retry_after is not None:
            raise RateLimited(retry_after)

        user = self._users.get_by_email(normalized_email)
        if user is None:
            # Spend roughly the same work as a real verification so the
            # unknown-email path is not a cheap account-enumeration oracle.
            self._passwords.verify_dummy(password)
            self._rate_limiter.record_failure(rate_key)
            raise InvalidCredentials()

        if not self._passwords.verify(password, user.password_hash):
            self._rate_limiter.record_failure(rate_key)
            raise InvalidCredentials()

        self._rate_limiter.clear(rate_key)
        return self._issue_tokens(user)

    def refresh(self, refresh_token: str) -> AuthResult:
        payload = self._tokens.decode(refresh_token, REFRESH_TOKEN_TYPE)
        jti = payload.get("jti")
        user_id = payload.get("sub")
        if not isinstance(jti, str) or not isinstance(user_id, str):
            raise InvalidToken()

        with self._refresh_lock:
            stored = self._refresh_tokens.get_by_jti(jti)
            if stored is None or stored.revoked_at is not None:
                raise InvalidToken()
            if stored.user_id != user_id:
                raise InvalidToken()
            if stored.expires_at <= datetime.now(timezone.utc):
                raise InvalidToken()

            user = self._users.get_by_id(user_id)
            if user is None:
                raise InvalidToken()

            access = self._tokens.create_access_token(user)
            new_refresh = self._tokens.create_refresh_token(user)
            self._refresh_tokens.revoke(
                jti,
                replaced_by_jti=new_refresh.jti,
            )
            self._store_refresh_token(user, new_refresh)
        return AuthResult(user=user, access=access, refresh=new_refresh)

    def logout(self, user: User, refresh_token: str | None) -> None:
        if not refresh_token:
            with self._refresh_lock:
                self._refresh_tokens.revoke_all_for_user(user.id)
            return

        try:
            payload = self._tokens.decode(
                refresh_token,
                REFRESH_TOKEN_TYPE,
            )
        except InvalidToken:
            # Logout is intentionally idempotent and does not reveal whether
            # a supplied token was valid.
            return

        if payload.get("sub") != user.id:
            return
        jti = payload.get("jti")
        if isinstance(jti, str) and jti:
            with self._refresh_lock:
                self._refresh_tokens.revoke(jti)

    def get_user_from_access_token(self, token: str) -> User:
        payload = self._tokens.decode(token, ACCESS_TOKEN_TYPE)
        user_id = payload.get("sub")
        if not isinstance(user_id, str):
            raise InvalidToken()
        user = self._users.get_by_id(user_id)
        if user is None:
            raise InvalidToken()
        return user

    def me(self, user: User) -> UserMe:
        return UserMe.model_validate(user)

    def access_expires_in(self) -> int:
        return self._tokens.access_expires_in()

    def _issue_tokens(self, user: User) -> AuthResult:
        access = self._tokens.create_access_token(user)
        refresh = self._tokens.create_refresh_token(user)
        self._store_refresh_token(user, refresh)
        return AuthResult(user=user, access=access, refresh=refresh)

    def _store_refresh_token(
        self,
        user: User,
        issued: IssuedToken,
    ) -> None:
        self._refresh_tokens.add(
            RefreshToken(
                jti=issued.jti,
                user_id=user.id,
                expires_at=issued.expires_at,
                created_at=datetime.now(timezone.utc),
            )
        )

    @staticmethod
    def _normalize_email(email: str) -> str:
        return email.strip().lower()

    @staticmethod
    def _rate_key(client_key: str, email: str) -> str:
        return f"{client_key.strip() or 'unknown'}|{email}"
