"""Models for the CAPTCHA and email-OTP verification layer."""

from __future__ import annotations

from datetime import datetime
from pydantic import BaseModel, EmailStr, Field


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
