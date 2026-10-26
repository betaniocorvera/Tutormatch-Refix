"""FastAPI application factory and ASGI entry point."""

from __future__ import annotations

from contextlib import asynccontextmanager
from typing import AsyncIterator

from fastapi import FastAPI

from .config import Settings
from .container import AppContainer
from .errors import install_exception_handlers
from .routers import auth, catalog, health, profile, users


def create_app(settings: Settings | None = None) -> FastAPI:
    resolved_settings = settings or Settings.from_env()
    container = AppContainer(resolved_settings)

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        try:
            yield
        finally:
            container.close()

    app = FastAPI(
        title="TutorMatch A.I. API",
        version="0.1.0",
        lifespan=lifespan,
    )
    app.state.container = container
    install_exception_handlers(app)
    app.include_router(health.router)
    app.include_router(auth.router)
    app.include_router(profile.router)
    app.include_router(users.router)
    app.include_router(catalog.router)
    return app


app = create_app()
