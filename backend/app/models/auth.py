"""Token and refresh-session models."""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, ConfigDict

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
