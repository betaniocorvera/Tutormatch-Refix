"""HTTP security middleware.

These middleware classes add protections that do not belong to a single
endpoint: response security headers, a bounded JSON request body, and a
no-store cache policy for authentication responses. Host allow-listing uses
Starlette's ``TrustedHostMiddleware`` directly in the app factory.
"""

from __future__ import annotations

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, Response
from starlette.types import ASGIApp

_DOCS_PATHS = frozenset(
    {
        "/docs",
        "/docs/oauth2-redirect",
        "/openapi.json",
        "/redoc",
    }
)
_BODY_METHODS = frozenset({"POST", "PUT", "PATCH", "DELETE"})
_API_CSP = (
    "default-src 'none'; "
    "base-uri 'none'; "
    "form-action 'none'; "
    "frame-ancestors 'none'"
)


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    """Add browser and proxy hardening headers to every HTTP response."""

    def __init__(self, app: ASGIApp, *, production: bool) -> None:
        super().__init__(app)
        self._production = production

    async def dispatch(self, request: Request, call_next) -> Response:
        response = await call_next(request)

        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("X-Frame-Options", "DENY")
        response.headers.setdefault("Referrer-Policy", "no-referrer")
        response.headers.setdefault(
            "Permissions-Policy",
            "camera=(), microphone=(), geolocation=()",
        )
        if request.url.path not in _DOCS_PATHS:
            response.headers.setdefault(
                "Content-Security-Policy",
                _API_CSP,
            )
        if request.url.path == "/auth" or request.url.path.startswith(
            "/auth/"
        ):
            response.headers.setdefault("Cache-Control", "no-store")
            response.headers.setdefault("Pragma", "no-cache")
        if self._production:
            response.headers.setdefault(
                "Strict-Transport-Security",
                "max-age=31536000; includeSubDomains",
            )
        return response


class JsonBodyLimitMiddleware(BaseHTTPMiddleware):
    """Reject declared request bodies above a configurable limit.

    Multipart uploads are excluded because the upload services enforce their
    own image and voice limits. The check uses ``Content-Length`` so it does not
    consume or buffer the request body. A reverse proxy should still enforce a
    hard limit for chunked requests.
    """

    def __init__(self, app: ASGIApp, *, max_bytes: int) -> None:
        if max_bytes <= 0:
            raise ValueError("max_bytes must be positive")
        super().__init__(app)
        self._max_bytes = max_bytes

    async def dispatch(self, request: Request, call_next) -> Response:
        if request.method in _BODY_METHODS:
            content_type = request.headers.get("content-type", "")
            media_type = content_type.split(";", 1)[0].strip().lower()
            if media_type != "multipart/form-data":
                raw_length = request.headers.get("content-length")
                if raw_length is not None:
                    try:
                        length = int(raw_length)
                    except ValueError:
                        length = 0
                    if length > self._max_bytes:
                        return JSONResponse(
                            status_code=413,
                            content={
                                "detail": "Request body is too large.",
                            },
                        )
        return await call_next(request)
