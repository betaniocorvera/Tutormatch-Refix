"""Small, framework-agnostic application errors and their HTTP mapping."""

from __future__ import annotations

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse


class AppError(Exception):
    status_code = 400
    detail = "Something went wrong."

    def __init__(
        self,
        detail: str | None = None,
        *,
        headers: dict[str, str] | None = None,
    ) -> None:
        self.detail = detail or self.detail
        self.headers = headers or {}
        super().__init__(self.detail)


class EmailAlreadyRegistered(AppError):
    status_code = 409
    detail = "An account with that email already exists."


class InvalidCredentials(AppError):
    status_code = 401
    detail = "Email or password is incorrect."

    def __init__(
        self,
        detail: str | None = None,
        *,
        headers: dict[str, str] | None = None,
    ) -> None:
        super().__init__(
            detail,
            headers=headers or {"WWW-Authenticate": "Bearer"},
        )


class InvalidToken(AppError):
    status_code = 401
    detail = "Your session is no longer valid. Sign in again."

    def __init__(
        self,
        detail: str | None = None,
        *,
        headers: dict[str, str] | None = None,
    ) -> None:
        super().__init__(
            detail,
            headers=headers or {"WWW-Authenticate": "Bearer"},
        )


class UserNotFound(AppError):
    status_code = 404
    detail = "That user was not found."


class InvalidProfile(AppError):
    status_code = 422
    detail = "That profile answer is not valid."


class InvalidPhoto(AppError):
    status_code = 422
    detail = "That file is not a supported image."


class InvalidMatchFilters(AppError):
    status_code = 422
    detail = "Those match filters are not valid."


class PhotoTooLarge(AppError):
    status_code = 413
    detail = "That image is too large. Choose one under 5 MB."


class PhotoNotFound(AppError):
    status_code = 404
    detail = "No photo is set for that user."


class RequestNotFound(AppError):
    status_code = 404
    detail = "That request was not found."


class ConversationNotFound(AppError):
    status_code = 404
    detail = "That conversation was not found."


class MessageNotFound(AppError):
    status_code = 404
    detail = "That message was not found."


class MediaNotFound(AppError):
    status_code = 404
    detail = "That attachment is no longer available."


class RequestAlreadyExists(AppError):
    status_code = 409
    detail = "There is already an open request with that person."


class RequestAlreadyAnswered(AppError):
    status_code = 409
    detail = "That request has already been answered."


class ConversationLocked(AppError):
    status_code = 409
    detail = "Accept the request before using the chat."


class InvalidRequest(AppError):
    status_code = 422
    detail = "That request is not valid."


class InvalidMessage(AppError):
    status_code = 422
    detail = "That message is not valid."


class InvalidPagination(AppError):
    status_code = 422
    detail = "Those message pagination options are not valid."


class InvalidAttachment(AppError):
    status_code = 422
    detail = "That attachment is not a supported file."


class AttachmentTooLarge(AppError):
    status_code = 413
    detail = "That attachment is too large."


class Forbidden(AppError):
    status_code = 403
    detail = "You do not have access to that."


class RateLimited(AppError):
    status_code = 429
    detail = "Too many sign-in attempts. Try again later."

    def __init__(self, retry_after: int) -> None:
        self.retry_after = max(1, retry_after)
        super().__init__(
            headers={"Retry-After": str(self.retry_after)},
        )


class DuplicateEmailError(Exception):
    """Repository-level conflict raised when an email is already stored."""


def install_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(AppError)
    async def _handle_app_error(
        request: Request, exc: AppError
    ) -> JSONResponse:
        return JSONResponse(
            status_code=exc.status_code,
            content={"detail": exc.detail},
            headers=exc.headers,
        )
