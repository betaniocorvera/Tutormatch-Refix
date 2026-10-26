"""FastAPI dependencies shared by routers."""

from __future__ import annotations

from typing import Annotated

from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .catalog import Catalog
from .container import AppContainer
from .errors import InvalidToken
from .models.user import User
from .services.auth import AuthService
from .services.profile import ProfileService

_bearer = HTTPBearer(auto_error=False)


def get_container(request: Request) -> AppContainer:
    return request.app.state.container


def get_auth_service(
    container: Annotated[AppContainer, Depends(get_container)],
) -> AuthService:
    return container.auth


def get_profile_service(
    container: Annotated[AppContainer, Depends(get_container)],
) -> ProfileService:
    return container.profile


def get_catalog(
    container: Annotated[AppContainer, Depends(get_container)],
) -> Catalog:
    return container.catalog


def get_current_user(
    credentials: Annotated[
        HTTPAuthorizationCredentials | None,
        Depends(_bearer),
    ],
    auth: Annotated[AuthService, Depends(get_auth_service)],
) -> User:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise InvalidToken()
    return auth.get_user_from_access_token(credentials.credentials)


ContainerDep = Annotated[AppContainer, Depends(get_container)]
AuthServiceDep = Annotated[AuthService, Depends(get_auth_service)]
ProfileServiceDep = Annotated[ProfileService, Depends(get_profile_service)]
CatalogDep = Annotated[Catalog, Depends(get_catalog)]
CurrentUser = Annotated[User, Depends(get_current_user)]
