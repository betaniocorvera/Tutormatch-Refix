"""Models for the CAPTCHA and email-OTP verification layer."""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, EmailStr, Field


class CAPTCHAChallenge(BaseModel):
    """The browser solves the CAPTCHA question and returns the id."""

    id: str
    question: str


class EmailVerificationStart(BaseModel):
    """Start a registration/email OTP flow."""

    email: EmailStr
    captcha_id: str = Field(min_length=1, max_length=128)
    captcha_answer: str = Field(min_length=1, max_length=10)


class EmailVerificationVerify(BaseModel):
    """Verify a one-time email code."""

    email: EmailStr
    code: str = Field(min_length=6, max_length=6)


class PasswordResetRequest(BaseModel):
    """Start a password-reset flow after a CAPTCHA success."""

    model_config = ConfigDict(extra="forbid")

    email: EmailStr
    captcha_id: str = Field(min_length=1, max_length=128)
    captcha_answer: str = Field(min_length=1, max_length=10)


class PasswordResetConfirm(BaseModel):
    """Complete a password reset with the emailed one-time code."""

    model_config = ConfigDict(extra="forbid")

    email: EmailStr
    code: str = Field(min_length=6, max_length=6)
    new_password: str = Field(min_length=10, max_length=128)


class PasswordResetRequestResponse(BaseModel):
    """The same generic response for known and unknown email addresses."""

    status: Literal["accepted"] = "accepted"
    message: str = (
        "If an account exists for that email, a reset code has been sent."
    )
