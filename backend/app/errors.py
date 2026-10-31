"""Small, framework-agnostic application errors and their HTTP mapping."""

from __future__ import annotations

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
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
    # Neutral by design: it does not say whether the address is registered.
    detail = (
        "We couldn't create an account with that email. "
        "Try signing in or use a different address."
    )


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


class InvalidCaptcha(AppError):
    status_code = 422
    detail = "The CAPTCHA challenge was wrong or expired."


class InvalidEmailVerification(AppError):
    status_code = 422
    detail = "That verification code is wrong, expired, or already used."


class EmailDeliveryUnavailable(AppError):
    status_code = 503
    detail = "Email delivery is not configured. Try again later."


class EmailDeliveryFailed(AppError):
    status_code = 502
    detail = "We couldn't send that email. Try again later."


class Forbidden(AppError):
    status_code = 403
    detail = "You do not have access to that."


class RateLimited(AppError):
    status_code = 429
    detail = "Too many sign-in attempts. Try again later."

    def __init__(
        self,
        retry_after: int,
        detail: str | None = None,
    ) -> None:
        self.retry_after = max(1, retry_after)
        super().__init__(
            detail,
            headers={"Retry-After": str(self.retry_after)},
        )


class DuplicateEmailError(Exception):
    """Repository-level conflict raised when an email is already stored."""


class DuplicateConversationError(ValueError):
    """Repository-level conflict raised when a pair already has a thread."""


def _validation_errors(exc: RequestValidationError) -> list[dict[str, object]]:
    """Keep the location and message, drop the submitted value.

    FastAPI's default handler includes ``input`` and sometimes ``ctx``. For a
    registration form that carries a password and three security answers, that
    would echo secrets back in a 422 response. Only the field path and a
    human-readable message are safe to return.
    """

    errors: list[dict[str, object]] = []
    for error in exc.errors():
        location = [
            str(part) for part in error.get("loc", ())
        ]
        errors.append(
            {
                "loc": location,
                "msg": str(error.get("msg", "Invalid value.")),
                "type": str(error.get("type", "value_error")),
            }
        )
    return errors


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

    @app.exception_handler(RequestValidationError)
    async def _handle_request_validation(
        request: Request,
        exc: RequestValidationError,
    ) -> JSONResponse:
        return JSONResponse(
            status_code=422,
            content={"detail": _validation_errors(exc)},
        )
