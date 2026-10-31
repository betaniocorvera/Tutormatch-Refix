"""Health and readiness checks."""

from __future__ import annotations

from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse

router = APIRouter(tags=["health"])


@router.get("/health")
def health() -> dict[str, str]:
    """Liveness: the process is running and can serve requests."""

    return {"status": "ok"}


@router.get("/ready")
def ready(request: Request):
    """Readiness: the configured storage can answer a query."""

    container = request.app.state.container
    if container.database is None:
        return {"status": "ready", "storage": "memory"}
    try:
        container.database.check()
    except Exception:
        # Do not leak connection strings or driver details to the probe.
        return JSONResponse(
            status_code=503,
            content={"status": "not_ready", "storage": "postgres"},
        )
    return {"status": "ready", "storage": "postgres"}
