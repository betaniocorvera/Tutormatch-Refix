"""User and auth request/response models."""

from __future__ import annotations

from datetime import datetime
from enum import Enum

from pydantic import (
    BaseModel,
    ConfigDict,
    EmailStr,
    Field,
    field_validator,
)


class Role(str, Enum):
    student = "student"
    tutor = "tutor"


class User(BaseModel):
    """Internal user record. Never returned directly by an endpoint."""

    model_config = ConfigDict(extra="forbid")

    id: str
    email: EmailStr
    password_hash: str
    role: Role
    display_name: str = ""
    onboarding_complete: bool = False
    created_at: datetime
    updated_at: datetime


class UserMe(BaseModel):
    """The signed-in user's own account view."""

    model_config = ConfigDict(from_attributes=True)

    id: str
    email: EmailStr
    role: Role
    display_name: str
    onboarding_complete: bool
    created_at: datetime


class RegisterRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    role: Role
    display_name: str = Field(default="", max_length=80)

    @field_validator("display_name")
    @classmethod
    def trim_display_name(cls, value: str) -> str:
        return value.strip()


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
