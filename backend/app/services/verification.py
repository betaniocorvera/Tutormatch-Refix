"""Internal email OTP and CAPTCHA verification.

The user-facing registration route already enforces the consent and security
questions. This service provides the next layer: a small in-memory CAPTCHA
challenge, a disposable one-time code, and a method to validate an OTP without
ever returning the code.
"""

from __future__ import annotations

import hmac
import secrets
import threading
from dataclasses import dataclass, replace
from datetime import datetime, timedelta, timezone
from email_validator import EmailSyntaxError, validate_email

from ..errors import (
    InvalidCaptcha,
    InvalidEmailVerification,
    RateLimited,
)

_CAPTCHA_TTL = timedelta(minutes=10)
_CAPTCHA_MAX_ATTEMPTS = 3
_OTP_TTL = timedelta(minutes=10)
_OTP_MAX_ATTEMPTS = 3
_OTP_LENGTH = 6
_OTP_ALPHABET = "0123456789"


@dataclass(frozen=True, slots=True)
class CAPTCHAChallengeResponse:
    """What the browser needs to solve a challenge."""

    id: str
    question: str


@dataclass(frozen=True, slots=True)
class _CAPTCHASession:
    """The server-side counterpart to a browser challenge."""

    id: str
    answer: str
    expires_at: datetime
    attempts: int = 0


@dataclass(frozen=True, slots=True)
class _EmailOTPCode:
    """A code that is never returned by an endpoint or logged."""

    email: str
    code: str
    expires_at: datetime
    attempts: int = 0


@dataclass(frozen=True, slots=True)
class LoginOTPChallenge:
    """A pending second-factor challenge for one user."""

    challenge_id: str
    user_id: str
    email: str
    expires_at: datetime
    attempts: int = 0


def _answer_to(left: int, right: int, operator: str) -> tuple[str, str]:
    """Build one small CAPTCHA pair, no external dependency needed."""

    if operator == "+":
        response = str(left + right)
        question = f"What is {left} plus {right}?"
    elif operator == "-":
        response = str(max(left, right) - min(left, right))
        question = (
            f"What is the distance between {left} and {right}?"
        )
    else:
        response = str(left * right)
        question = f"What is {left} times {right}?"
    return question, response


class CAPTCHAService:
    """Small in-memory CAPTCHA challenges.

    Each challenge is deleted when it is used, and expired or over-attempted
    challenges are removed. This is not intended for a public production site;
    it is a compact demonstration of how the API gates automated requests.
    """

    def __init__(self) -> None:
        self._sessions: dict[str, _CAPTCHASession] = {}

    def challenge(self) -> CAPTCHAChallengeResponse:
        """Create and remember a new CAPTCHA challenge."""

        now = datetime.now(timezone.utc)
        operator = secrets.choice(("+", "-", "*"))
        left = secrets.randbelow(20) + 1
        right = secrets.randbelow(20) + 1
        question, response = _answer_to(left, right, operator)
        challenge_id = secrets.token_urlsafe(32)
        self._sessions[challenge_id] = _CAPTCHASession(
            id=challenge_id,
            answer=response,
            expires_at=now + _CAPTCHA_TTL,
        )
        self._gc(now)
        return CAPTCHAChallengeResponse(id=challenge_id, question=question)

    def verify(
        self,
        challenge_id: str,
        response: str,
    ) -> None:
        """Consume a challenge and raise when it is wrong."""

        now = datetime.now(timezone.utc)
        session = self._sessions.get(challenge_id)
        if session is None:
            raise InvalidCaptcha()
        if session.expires_at <= now:
            self._sessions.pop(challenge_id, None)
            raise InvalidCaptcha()
        if session.attempts >= _CAPTCHA_MAX_ATTEMPTS:
            self._sessions.pop(challenge_id, None)
            raise RateLimited(_CAPTCHA_TTL.seconds, detail="Too many CAPTCHA attempts.")

        if response != session.answer:
            attempts = session.attempts + 1
            if attempts >= _CAPTCHA_MAX_ATTEMPTS:
                self._sessions.pop(challenge_id, None)
                raise InvalidCaptcha()
            self._sessions[challenge_id] = replace(
                session, attempts=attempts
            )
            raise InvalidCaptcha()

        self._sessions.pop(challenge_id, None)
        self._gc(now)

    def _gc(self, now: datetime) -> None:
        for challenge_id in list(self._sessions):
            if self._sessions[challenge_id].expires_at <= now:
                self._sessions.pop(challenge_id, None)


class EmailOTPService:
    """One-time codes delivered to the stored email address.

    The service validates and deletes codes after use and never returns a
    code. The browser only receives a status and the expiry time.
    """

    def __init__(self) -> None:
        self._codes: dict[str, _EmailOTPCode] = {}
        self._lock = threading.Lock()

    def start(
        self,
        *,
        email: str,
        subject: str = "Your TutorMatch verification code",
    ) -> datetime:
        """Create an OTP for one email address."""

        now = datetime.now(timezone.utc)
        normalized = self._normalize_email(email)
        code = "".join(secrets.choice(_OTP_ALPHABET) for _ in range(_OTP_LENGTH))
        with self._lock:
            self._codes[normalized] = _EmailOTPCode(
                email=normalized,
                code=code,
                expires_at=now + _OTP_TTL,
            )
            self._gc(now)
            return self._codes[normalized].expires_at

    def verify(self, email: str, code: str) -> None:
        """Consume an OTP; raise when it is wrong, expired, or over-attempted."""
        now = datetime.now(timezone.utc)
        normalized = self._normalize_email(email)
        with self._lock:
            pending = self._codes.get(normalized)
            if pending is None:
                raise InvalidEmailVerification()
            if pending.expires_at <= now:
                self._codes.pop(normalized, None)
                raise InvalidEmailVerification()
            if pending.attempts >= _OTP_MAX_ATTEMPTS:
                self._codes.pop(normalized, None)
                raise RateLimited(
                    _OTP_TTL.seconds,
                    detail="Too many verification attempts.",
                )

            if not hmac.compare_digest(code, pending.code):
                attempts = pending.attempts + 1
                if attempts >= _OTP_MAX_ATTEMPTS:
                    self._codes.pop(normalized, None)
                    raise InvalidEmailVerification()
                self._codes[normalized] = replace(
                    pending,
                    attempts=attempts,
                )
                raise InvalidEmailVerification()

            self._codes.pop(normalized, None)

    def clear(self, email: str) -> None:
        """Forget a pending OTP without validating its code."""
        normalized = self._normalize_email(email)
        with self._lock:
            self._codes.pop(normalized, None)

    def _normalize_email(self, email: str) -> str:
        try:
            validate_email(
                email.strip(),
                check_deliverability=False,
            )
        except EmailSyntaxError as exc:
            raise InvalidEmailVerification() from exc
        return email.strip().casefold()

    def _gc(self, now: datetime) -> None:
        for email in list(self._codes):
            if self._codes[email].expires_at <= now:
                self._codes.pop(email, None)


class LoginOTPChallengeService:
    """Links one pending email code to one password-verified user.

    The challenge ID is the only value returned to the client. The code stays
    server-side until it is delivered by a future mail transport.
    """

    def __init__(self) -> None:
        self._by_id: dict[str, LoginOTPChallenge] = {}
        self._by_email: dict[str, LoginOTPChallenge] = {}
        self._lock = threading.Lock()

    def start(
        self,
        *,
        user_id: str,
        email: str,
        email_otp: EmailOTPService,
    ) -> LoginOTPChallenge:
        normalized = email.strip().casefold()
        expires_at = email_otp.start(email=normalized)
        now = datetime.now(timezone.utc)
        challenge = LoginOTPChallenge(
            challenge_id=secrets.token_urlsafe(32),
            user_id=user_id,
            email=normalized,
            expires_at=expires_at,
        )
        with self._lock:
            previous = self._by_email.get(normalized)
            if previous is not None:
                self._by_id.pop(previous.challenge_id, None)
            self._by_id[challenge.challenge_id] = challenge
            self._by_email[normalized] = challenge
            self._gc(now)
        return challenge

    def verify(
        self,
        challenge_id: str,
        code: str,
        email_otp: EmailOTPService,
    ) -> LoginOTPChallenge:
        now = datetime.now(timezone.utc)
        with self._lock:
            challenge = self._by_id.get(challenge_id)
            if challenge is None:
                raise InvalidEmailVerification()
            if challenge.expires_at <= now:
                self._remove_locked(challenge)
                raise InvalidEmailVerification()
            if challenge.attempts >= _OTP_MAX_ATTEMPTS:
                self._remove_locked(challenge)
                raise RateLimited(
                    _OTP_TTL.seconds,
                    detail="Too many verification attempts.",
                )

        try:
            email_otp.verify(challenge.email, code)
        except InvalidEmailVerification:
            with self._lock:
                current = self._by_id.get(challenge_id)
                if current is not None:
                    attempts = current.attempts + 1
                    if attempts >= _OTP_MAX_ATTEMPTS:
                        self._remove_locked(current)
                    else:
                        self._by_id[challenge_id] = replace(
                            current,
                            attempts=attempts,
                        )
            raise
        except RateLimited:
            with self._lock:
                current = self._by_id.get(challenge_id)
                if current is not None:
                    self._remove_locked(current)
            raise

        with self._lock:
            current = self._by_id.get(challenge_id)
            if current is not None:
                self._remove_locked(current)
        return challenge

    def clear(self, challenge_id: str) -> None:
        with self._lock:
            challenge = self._by_id.get(challenge_id)
            if challenge is not None:
                self._remove_locked(challenge)

    def _remove_locked(self, challenge: LoginOTPChallenge) -> None:
        self._by_id.pop(challenge.challenge_id, None)
        current = self._by_email.get(challenge.email)
        if current is not None and current.challenge_id == challenge.challenge_id:
            self._by_email.pop(challenge.email, None)

    def _gc(self, now: datetime) -> None:
        for challenge in list(self._by_id.values()):
            if challenge.expires_at <= now:
                self._remove_locked(challenge)
