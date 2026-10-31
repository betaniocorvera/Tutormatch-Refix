"""Authentication endpoints."""

from __future__ import annotations

from fastapi import APIRouter, Request, Response, status
from fastapi.responses import JSONResponse

from ..dependencies import AuthServiceDep, CurrentUser
from ..models.auth import (
    AuthResponse,
    LoginOTPChallengeResponse,
    LoginOTPVerifyRequest,
)
from ..models.verification import (
    PasswordResetConfirm,
    PasswordResetRequest,
    PasswordResetRequestResponse,
)
from ..models.user import (
    LoginRequest,
    LogoutRequest,
    RefreshRequest,
    RegisterRequest,
    UserMe,
)
from ..services.auth import AuthResult, AuthService
from ..services.verification import LoginOTPChallenge

router = APIRouter(prefix="/auth", tags=["auth"])


def _auth_response(
    result: AuthResult,
    service: AuthService,
) -> AuthResponse:
    return AuthResponse(
        access_token=result.access.token,
        refresh_token=result.refresh.token,
        token_type="bearer",
        expires_in=service.access_expires_in(),
        user=UserMe.model_validate(result.user),
    )


@router.post(
    "/register",
    response_model=AuthResponse,
    status_code=status.HTTP_201_CREATED,
)
def register(
    payload: RegisterRequest,
    auth: AuthServiceDep,
) -> AuthResponse:
    result = auth.register(
        email=str(payload.email),
        password=payload.password,
        role=payload.role,
        display_name=payload.display_name,
        phone=payload.phone,
        area_id=payload.area_id,
        subjects=payload.subjects,
        security_questions=payload.security_questions,
        privacy_consent=payload.privacy_consent,
        privacy_policy_version=payload.privacy_policy_version,
    )
    return _auth_response(result, auth)


@router.post(
    "/login",
    response_model=AuthResponse | LoginOTPChallengeResponse,
)
def login(
    payload: LoginRequest,
    request: Request,
    auth: AuthServiceDep,
) -> AuthResponse | JSONResponse:
    client_key = request.client.host if request.client else "unknown"
    result = auth.login(
        email=str(payload.email),
        password=payload.password,
        client_key=client_key,
    )
    if isinstance(result, LoginOTPChallenge):
        challenge = LoginOTPChallengeResponse(
            challenge_id=result.challenge_id,
            expires_at=result.expires_at,
        )
        return JSONResponse(
            status_code=status.HTTP_202_ACCEPTED,
            content=challenge.model_dump(mode="json"),
        )
    return _auth_response(result, auth)


@router.post("/login/otp/verify", response_model=AuthResponse)
def verify_login_otp(
    payload: LoginOTPVerifyRequest,
    request: Request,
    auth: AuthServiceDep,
) -> AuthResponse:
    client_key = request.client.host if request.client else "unknown"
    result = auth.verify_login_otp(
        challenge_id=payload.challenge_id,
        code=payload.code,
        client_key=client_key,
    )
    return _auth_response(result, auth)


@router.post(
    "/password-reset/request",
    response_model=PasswordResetRequestResponse,
    status_code=status.HTTP_202_ACCEPTED,
)
def request_password_reset(
    payload: PasswordResetRequest,
    request: Request,
    auth: AuthServiceDep,
) -> PasswordResetRequestResponse:
    client_key = request.client.host if request.client else "unknown"
    auth.request_password_reset(
        email=str(payload.email),
        captcha_id=payload.captcha_id,
        captcha_answer=payload.captcha_answer,
        client_key=client_key,
    )
    return PasswordResetRequestResponse()


@router.post(
    "/password-reset/confirm",
    status_code=status.HTTP_204_NO_CONTENT,
)
def confirm_password_reset(
    payload: PasswordResetConfirm,
    request: Request,
    auth: AuthServiceDep,
) -> Response:
    client_key = request.client.host if request.client else "unknown"
    auth.confirm_password_reset(
        email=str(payload.email),
        code=payload.code,
        new_password=payload.new_password,
        client_key=client_key,
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/refresh", response_model=AuthResponse)
def refresh(
    payload: RefreshRequest,
    auth: AuthServiceDep,
) -> AuthResponse:
    result = auth.refresh(payload.refresh_token)
    return _auth_response(result, auth)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(
    user: CurrentUser,
    auth: AuthServiceDep,
    payload: LogoutRequest | None = None,
) -> Response:
    auth.logout(user, payload.refresh_token if payload else None)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/me", response_model=UserMe)
def me(user: CurrentUser) -> UserMe:
    return UserMe.model_validate(user)
