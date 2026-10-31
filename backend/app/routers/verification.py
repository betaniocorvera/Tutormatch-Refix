"""CAPTCHA and email OTP endpoints."""

from __future__ import annotations

from fastapi import APIRouter, Response, status

from ..container import AppContainer
from ..dependencies import ContainerDep
from ..models.verification import (
    CAPTCHAChallenge,
    EmailVerificationStart,
    EmailVerificationVerify,
)
from ..services.verification import EMAIL_VERIFICATION_SCOPE

router = APIRouter(prefix="/auth", tags=["auth"])


@router.get("/captcha", response_model=CAPTCHAChallenge)
def new_captcha(container: ContainerDep) -> CAPTCHAChallenge:
    """Return a fresh CAPTCHA challenge for the client to solve."""

    challenge = container.captcha.challenge()
    return CAPTCHAChallenge(
        id=challenge.id,
        question=challenge.question,
    )


@router.post("/email-verification/start", status_code=status.HTTP_202_ACCEPTED)
def start_email_verification(
    payload: EmailVerificationStart,
    container: ContainerDep,
) -> dict[str, str]:
    """Create and email a one-time code after a CAPTCHA success."""

    container.captcha.verify(payload.captcha_id, payload.captcha_answer)
    expires_at = container.email_otp.start(
        email=str(payload.email),
        email_service=container.email,
        purpose="email verification",
        scope=EMAIL_VERIFICATION_SCOPE,
    )
    return {"status": "sent", "expires_at": expires_at.isoformat()}


@router.post(
    "/email-verification/verify",
    status_code=status.HTTP_204_NO_CONTENT,
)
def verify_email_verification(
    payload: EmailVerificationVerify,
    container: ContainerDep,
) -> Response:
    """Verify the code that was sent in the last email verification step."""
    container.email_otp.verify(
        email=str(payload.email),
        code=payload.code,
        scope=EMAIL_VERIFICATION_SCOPE,
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)


