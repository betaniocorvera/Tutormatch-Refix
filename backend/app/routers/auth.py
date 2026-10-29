"""Authentication endpoints."""

from __future__ import annotations

from fastapi import APIRouter, Request, Response, status

from ..dependencies import AuthServiceDep, CurrentUser
from ..models.auth import AuthResponse
from ..models.user import (
    LoginRequest,
    LogoutRequest,
    RefreshRequest,
    RegisterRequest,
    UserMe,
)
from ..services.auth import AuthResult, AuthService

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


@router.post("/login", response_model=AuthResponse)
def login(
    payload: LoginRequest,
    request: Request,
    auth: AuthServiceDep,
) -> AuthResponse:
    client_key = request.client.host if request.client else "unknown"
    result = auth.login(
        email=str(payload.email),
        password=payload.password,
        client_key=client_key,
    )
    return _auth_response(result, auth)


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
