"""User and auth request/response models."""

from __future__ import annotations

from datetime import datetime
from enum import Enum

from pydantic import (
    BaseModel,
    ConfigDict,
    EmailStr,
    Field,
    StrictBool,
    field_validator,
)

from ..passwords import validate_password_policy
from ..privacy import PRIVACY_POLICY_VERSION

_PHONE_ALLOWED = frozenset("+0123456789 ()-.")


class Role(str, Enum):
    student = "student"
    tutor = "tutor"


class SecurityAnswer(BaseModel):
    """A stored, hashed security answer. Never returned by an endpoint."""

    model_config = ConfigDict(extra="forbid")

    question_id: str = Field(min_length=1, max_length=80)
    answer_hash: str = Field(min_length=1, max_length=512)


class User(BaseModel):
    """Internal user record. Never returned directly by an endpoint."""

    model_config = ConfigDict(extra="forbid")

    id: str
    email: EmailStr
    password_hash: str
    role: Role
    display_name: str = ""
    phone: str = Field(default="", max_length=20)
    onboarding_complete: bool = False
    privacy_consent: bool = False
    privacy_consent_at: datetime | None = None
    privacy_policy_version: str = Field(default="", max_length=40)
    security_answers: list[SecurityAnswer] = Field(
        default_factory=list,
        max_length=3,
    )
    created_at: datetime
    updated_at: datetime


class UserMe(BaseModel):
    """The signed-in user's own account view.

    Deliberately excludes the phone number, consent record, and security
    answers: none of them is needed by the client, and answers must never leave
    the server.
    """

    model_config = ConfigDict(from_attributes=True)

    id: str
    email: EmailStr
    role: Role
    display_name: str
    onboarding_complete: bool
    created_at: datetime


class SecurityAnswerInput(BaseModel):
    """One plain-text answer received during registration.

    The service normalizes and hashes it immediately; it is never stored or
    logged in this form.
    """

    model_config = ConfigDict(extra="forbid")

    question_id: str = Field(min_length=1, max_length=80)
    answer: str = Field(min_length=3, max_length=128)


class RegisterRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    email: EmailStr
    # Defined before password so the password validator can compare against
    # the email local part and the person's name.
    display_name: str = Field(min_length=2, max_length=80)
    role: Role
    password: str = Field(min_length=10, max_length=128)
    phone: str = Field(default="", max_length=20)
    area_id: str = Field(min_length=1, max_length=120)
    subjects: list[str] = Field(min_length=1, max_length=4)
    security_questions: list[SecurityAnswerInput] = Field(
        min_length=3,
        max_length=3,
    )
    privacy_consent: StrictBool
    privacy_policy_version: str = Field(min_length=1, max_length=40)

    @field_validator("display_name")
    @classmethod
    def _valid_name(cls, value: str) -> str:
        cleaned = " ".join(value.strip().split())
        if len(cleaned) < 2 or sum(
            character.isalpha() for character in cleaned
        ) < 2:
            raise ValueError("Enter your full name.")
        if not all(
            character.isalpha() or character in " .'-"
            for character in cleaned
        ):
            raise ValueError(
                "Use letters, spaces, hyphens, apostrophes, and periods only."
            )
        return cleaned

    @field_validator("phone")
    @classmethod
    def _valid_phone(cls, value: str) -> str:
        cleaned = value.strip()
        if not cleaned:
            return ""
        if any(character not in _PHONE_ALLOWED for character in cleaned):
            raise ValueError(
                "Enter a phone number using digits, spaces, +, -, ( ), "
                "or a period."
            )
        if sum(character.isdigit() for character in cleaned) < 7:
            raise ValueError("Enter a phone number with at least 7 digits.")
        return cleaned

    @field_validator("subjects")
    @classmethod
    def _valid_subjects(cls, value: list[str]) -> list[str]:
        cleaned = [item.strip() for item in value]
        if any(not item for item in cleaned):
            raise ValueError("Choose at least one subject.")
        if len({item.casefold() for item in cleaned}) != len(cleaned):
            raise ValueError("A subject can only appear once.")
        return cleaned

    @field_validator("security_questions")
    @classmethod
    def _distinct_questions(
        cls,
        value: list[SecurityAnswerInput],
    ) -> list[SecurityAnswerInput]:
        ids = [item.question_id for item in value]
        if len(set(ids)) != len(ids):
            raise ValueError("Choose three different security questions.")
        return value

    @field_validator("password")
    @classmethod
    def _valid_password(cls, value: str, info) -> str:
        email = info.data.get("email")
        display_name = info.data.get("display_name")
        validate_password_policy(
            value,
            email=str(email) if email is not None else "",
            display_name=(
                str(display_name) if display_name is not None else ""
            ),
        )
        return value

    @field_validator("privacy_consent")
    @classmethod
    def _consent_required(cls, value: bool) -> bool:
        if not value:
            raise ValueError(
                "You must agree to the Privacy Notice to create an account."
            )
        return value

    @field_validator("privacy_policy_version")
    @classmethod
    def _current_policy(cls, value: str) -> str:
        if value != PRIVACY_POLICY_VERSION:
            raise ValueError(
                "The Privacy Notice has changed. Review it and try again."
            )
        return value


class LoginRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    email: EmailStr
    # Login deliberately does not enforce the registration minimum: a short
    # password should fail with the same generic 401, not a 422 that confirms
    # anything about the stored password policy.
    password: str = Field(min_length=1, max_length=128)


class RefreshRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    refresh_token: str = Field(min_length=1, max_length=4096)


class LogoutRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    refresh_token: str | None = Field(default=None, max_length=4096)
