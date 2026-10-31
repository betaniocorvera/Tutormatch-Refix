"""Authentication service: registration, login, refresh, logout, and views."""

from __future__ import annotations

import re
import threading
from dataclasses import dataclass
from datetime import datetime, timezone
from uuid import uuid4

from ..catalog import Catalog
from ..errors import (
    DuplicateEmailError,
    EmailAlreadyRegistered,
    EmailDeliveryFailed,
    EmailDeliveryUnavailable,
    InvalidCredentials,
    InvalidEmailVerification,
    InvalidProfile,
    InvalidToken,
    RateLimited,
)
from ..models.auth import RefreshToken
from ..models.profile import Profile
from ..models.user import (
    Role,
    SecurityAnswer,
    SecurityAnswerInput,
    User,
    UserMe,
)
from ..passwords import normalize_security_answer, validate_password_policy
from ..privacy import PRIVACY_POLICY_VERSION
from ..repositories.interfaces import (
    ProfileRepository,
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
from ..transactions import TransactionFactory, no_transaction
from .email import EmailService, UnavailableEmailTransport
from .lockout import AccountLockout
from .rate_limit import LoginRateLimiter
from .security_events import SecurityEventService
from .verification import (
    CAPTCHAService,
    EmailOTPService,
    LoginOTPChallenge,
    LoginOTPChallengeService,
    PASSWORD_RESET_OTP_SCOPE,
)


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
        profiles: ProfileRepository,
        refresh_tokens: RefreshTokenRepository,
        passwords: PasswordHasher,
        tokens: TokenService,
        rate_limiter: LoginRateLimiter,
        catalog: Catalog,
        transaction: TransactionFactory | None = None,
        account_lockout: AccountLockout | None = None,
        security_events: SecurityEventService | None = None,
        email_service: EmailService | None = None,
        email_otp: EmailOTPService | None = None,
        login_otp_challenges: LoginOTPChallengeService | None = None,
        captcha: CAPTCHAService | None = None,
        password_reset_rate_limiter: LoginRateLimiter | None = None,
        login_otp_required: bool = False,
    ) -> None:
        self._users = users
        self._profiles = profiles
        self._refresh_tokens = refresh_tokens
        self._passwords = passwords
        self._tokens = tokens
        self._rate_limiter = rate_limiter
        self._catalog = catalog
        self._transaction = transaction or no_transaction
        self._account_lockout = account_lockout or AccountLockout(5, 900)
        self._security_events = security_events or SecurityEventService()
        self._email = email_service or EmailService(
            UnavailableEmailTransport()
        )
        self._email_otp = email_otp or EmailOTPService()
        self._login_otp_challenges = (
            login_otp_challenges or LoginOTPChallengeService()
        )
        self._captcha = captcha or CAPTCHAService()
        self._password_reset_rate_limiter = (
            password_reset_rate_limiter or LoginRateLimiter(3, 900)
        )
        self._login_otp_required = login_otp_required
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
        phone: str,
        area_id: str,
        subjects: list[str],
        security_questions: list[SecurityAnswerInput],
        privacy_consent: bool,
        privacy_policy_version: str,
    ) -> AuthResult:
        normalized_email = self._normalize_email(email)
        if self._users.get_by_email(normalized_email) is not None:
            raise EmailAlreadyRegistered()

        if not privacy_consent:
            raise InvalidProfile(
                "You must agree to the Privacy Notice to create an account."
            )
        if privacy_policy_version != PRIVACY_POLICY_VERSION:
            raise InvalidProfile(
                "The Privacy Notice has changed. Review it and try again."
            )

        area = self._catalog.area(area_id)
        if area is None:
            raise InvalidProfile("Choose an area from the catalogue.")
        canonical_subjects = self._canonical_subjects(subjects)
        answers = self._hash_security_answers(
            security_questions,
            email=normalized_email,
            display_name=display_name,
        )

        now = datetime.now(timezone.utc)
        user = User(
            id=str(uuid4()),
            email=normalized_email,
            password_hash=self._passwords.hash(password),
            role=role,
            display_name=display_name,
            phone=phone,
            onboarding_complete=False,
            privacy_consent=True,
            privacy_consent_at=now,
            privacy_policy_version=PRIVACY_POLICY_VERSION,
            security_answers=answers,
            created_at=now,
            updated_at=now,
        )
        with self._transaction():
            try:
                self._users.add(user)
            except DuplicateEmailError as exc:
                # A concurrent registration won the race.
                raise EmailAlreadyRegistered() from exc

            # Registration already knows two onboarding answers. The remaining
            # five questions still decide when onboarding is complete.
            self._profiles.add(
                Profile(
                    user_id=user.id,
                    name=display_name,
                    subjects=canonical_subjects,
                    area_id=area.id,
                    updated_at=now,
                )
            )

            return self._issue_tokens(user)

    def login(
        self,
        *,
        email: str,
        password: str,
        client_key: str,
    ) -> AuthResult | LoginOTPChallenge:
        normalized_email = self._normalize_email(email)
        rate_key = self._rate_key(client_key, normalized_email)

        retry_after = self._rate_limiter.check(rate_key)
        if retry_after is not None:
            raise RateLimited(retry_after)

        retry_after = self._account_lockout.check(normalized_email)
        if retry_after is not None:
            raise RateLimited(retry_after)

        user = self._users.get_by_email(normalized_email)
        if user is None:
            # Spend roughly the same work as a real verification so the
            # unknown-email path is not a cheap account-enumeration oracle.
            self._passwords.verify_dummy(password)
            self._record_failure(
                rate_key=rate_key,
                email=normalized_email,
                client_key=client_key,
                user=None,
            )
            raise InvalidCredentials()

        if not self._passwords.verify(password, user.password_hash):
            self._record_failure(
                rate_key=rate_key,
                email=normalized_email,
                client_key=client_key,
                user=user,
            )
            raise InvalidCredentials()

        self._rate_limiter.clear(rate_key)
        self._account_lockout.clear(normalized_email)

        if self._login_otp_required:
            challenge = self._login_otp_challenges.start(
                user_id=user.id,
                email=str(user.email),
                email_otp=self._email_otp,
                email_service=self._email,
            )
            self._security_events.record(
                "login_otp_sent",
                user_id=user.id,
                email=str(user.email),
                client_key=client_key,
            )
            return challenge

        result = self._issue_tokens(user)
        self._security_events.record(
            "login_succeeded",
            user_id=user.id,
            email=str(user.email),
            client_key=client_key,
            detail="password",
        )
        return result

    def verify_login_otp(
        self,
        *,
        challenge_id: str,
        code: str,
        client_key: str,
    ) -> AuthResult:
        pending_challenge = self._login_otp_challenges.get(challenge_id)
        try:
            challenge = self._login_otp_challenges.verify(
                challenge_id,
                code,
                self._email_otp,
            )
        except (InvalidEmailVerification, RateLimited):
            self._security_events.record(
                "login_otp_failed",
                user_id=(
                    pending_challenge.user_id
                    if pending_challenge is not None
                    else None
                ),
                email=(
                    pending_challenge.email
                    if pending_challenge is not None
                    else None
                ),
                client_key=client_key,
            )
            raise

        user = self._users.get_by_id(challenge.user_id)
        if user is None:
            raise InvalidToken()

        self._security_events.record(
            "login_otp_verified",
            user_id=user.id,
            email=str(user.email),
            client_key=client_key,
        )
        result = self._issue_tokens(user)
        self._security_events.record(
            "login_succeeded",
            user_id=user.id,
            email=str(user.email),
            client_key=client_key,
            detail="otp",
        )
        return result

    def request_password_reset(
        self,
        *,
        email: str,
        captcha_id: str,
        captcha_answer: str,
        client_key: str,
    ) -> None:
        """Send a reset code without revealing whether the account exists."""

        normalized_email = self._normalize_email(email)
        rate_key = self._rate_key(client_key, normalized_email)
        retry_after = self._password_reset_rate_limiter.check(rate_key)
        if retry_after is not None:
            raise RateLimited(retry_after)
        self._password_reset_rate_limiter.record_failure(rate_key)

        self._captcha.verify(captcha_id, captcha_answer)

        if not self._email.is_configured:
            raise EmailDeliveryUnavailable()

        user = self._users.get_by_email(normalized_email)
        if user is None:
            return

        try:
            self._email_otp.start(
                email=normalized_email,
                email_service=self._email,
                purpose="password reset",
                scope=PASSWORD_RESET_OTP_SCOPE,
            )
        except (EmailDeliveryFailed, EmailDeliveryUnavailable):
            # The response stays generic even when delivery fails for an
            # existing account; the pending code has already been cleared.
            return

        self._security_events.record(
            "password_reset_requested",
            user_id=user.id,
            email=str(user.email),
            client_key=client_key,
        )

    def confirm_password_reset(
        self,
        *,
        email: str,
        code: str,
        new_password: str,
        client_key: str,
    ) -> None:
        """Consume a reset code, change the password, and revoke sessions."""

        normalized_email = self._normalize_email(email)
        self._email_otp.verify(
            normalized_email,
            code,
            scope=PASSWORD_RESET_OTP_SCOPE,
        )

        user = self._users.get_by_email(normalized_email)
        if user is None:
            raise InvalidEmailVerification()

        try:
            validate_password_policy(
                new_password,
                email=str(user.email),
                display_name=user.display_name,
            )
        except ValueError as exc:
            raise InvalidProfile(str(exc)) from exc

        password_hash = self._passwords.hash(new_password)
        now = datetime.now(timezone.utc)
        with self._refresh_lock:
            with self._transaction():
                current = self._users.get_by_email(normalized_email)
                if current is None:
                    raise InvalidEmailVerification()
                self._users.update(
                    current.model_copy(
                        update={
                            "password_hash": password_hash,
                            "updated_at": now,
                        }
                    )
                )
                self._refresh_tokens.revoke_all_for_user(current.id)

        self._account_lockout.clear(normalized_email)
        self._rate_limiter.clear(
            self._rate_key(client_key, normalized_email)
        )
        self._security_events.record(
            "password_reset_completed",
            user_id=current.id,
            email=str(current.email),
            client_key=client_key,
            detail="email OTP",
        )

    def _record_failure(
        self,
        *,
        rate_key: str,
        email: str,
        client_key: str,
        user: User | None,
    ) -> None:
        self._rate_limiter.record_failure(rate_key)
        newly_locked = self._account_lockout.record_failure(email)
        self._security_events.record(
            "login_failed",
            user_id=user.id if user is not None else None,
            email=email,
            client_key=client_key,
        )
        if newly_locked:
            self._security_events.record(
                "account_locked",
                user_id=user.id if user is not None else None,
                email=email,
                client_key=client_key,
                detail=(
                    f"{self._account_lockout.max_attempts} failed attempts"
                ),
            )

    def refresh(self, refresh_token: str) -> AuthResult:
        payload = self._tokens.decode(refresh_token, REFRESH_TOKEN_TYPE)
        jti = payload.get("jti")
        user_id = payload.get("sub")
        if not isinstance(jti, str) or not isinstance(user_id, str):
            raise InvalidToken()

        with self._refresh_lock:
            with self._transaction():
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
        with self._transaction():
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
                # Logout is intentionally idempotent and does not reveal
                # whether a supplied token was valid.
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

    def _canonical_subjects(self, subjects: list[str]) -> list[str]:
        canonical: list[str] = []
        seen: set[str] = set()
        for item in subjects:
            name = self._catalog.canonical_subject(item)
            if name is None:
                raise InvalidProfile(
                    "Choose subjects from the subject catalogue."
                )
            key = name.casefold()
            if key in seen:
                raise InvalidProfile("A subject can only appear once.")
            seen.add(key)
            canonical.append(name)
        if not canonical:
            raise InvalidProfile("Choose at least one subject.")
        if len(canonical) > 4:
            raise InvalidProfile("Choose up to four subjects.")
        return canonical

    def _hash_security_answers(
        self,
        questions: list[SecurityAnswerInput],
        *,
        email: str,
        display_name: str,
    ) -> list[SecurityAnswer]:
        if len(questions) != 3:
            raise InvalidProfile("Choose three security questions.")

        answers: list[SecurityAnswer] = []
        seen: set[str] = set()
        for item in questions:
            if self._catalog.security_question(item.question_id) is None:
                raise InvalidProfile(
                    "Choose security questions from the list."
                )
            if item.question_id in seen:
                raise InvalidProfile(
                    "Choose three different security questions."
                )
            seen.add(item.question_id)

            answer = normalize_security_answer(item.answer)
            if len(answer) < 3:
                raise InvalidProfile(
                    "Each security answer must be at least 3 characters."
                )
            if self._answer_matches_identity(
                answer,
                email=email,
                display_name=display_name,
            ):
                raise InvalidProfile(
                    "Security answers cannot be your email or name."
                )
            answers.append(
                SecurityAnswer(
                    question_id=item.question_id,
                    answer_hash=self._passwords.hash(answer),
                )
            )
        return answers

    @staticmethod
    def _answer_matches_identity(
        answer: str,
        *,
        email: str,
        display_name: str,
    ) -> bool:
        candidates = {
            email.casefold(),
            email.split("@", 1)[0].casefold(),
            display_name.casefold(),
        }
        for token in re.split(r"[\s\-'.]+", display_name.casefold()):
            if len(token) >= 3:
                candidates.add(token)
        normalized = {
            normalize_security_answer(candidate)
            for candidate in candidates
            if candidate.strip()
        }
        return answer in normalized

    def _issue_tokens(self, user: User) -> AuthResult:
        with self._transaction():
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
