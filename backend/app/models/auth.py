"""Token and refresh-session models."""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

from .user import UserMe


class RefreshToken(BaseModel):
    """A refresh-token session stored server-side for rotation and revocation."""

    model_config = ConfigDict(extra="forbid")

    jti: str
    user_id: str
    expires_at: datetime
    created_at: datetime
    revoked_at: datetime | None = None
    replaced_by_jti: str | None = None


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int


class AuthResponse(TokenResponse):
    user: UserMe


class LoginOTPChallengeResponse(BaseModel):
    """Returned instead of tokens when email OTP login is required."""

    otp_required: Literal[True] = True
    challenge_id: str
    expires_at: datetime
    message: str = "Enter the 6-digit code sent to your email."


class LoginOTPVerifyRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    challenge_id: str = Field(min_length=1, max_length=256)
    code: str = Field(min_length=6, max_length=6)
