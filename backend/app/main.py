"""FastAPI application factory and ASGI entry point."""

from __future__ import annotations

from contextlib import asynccontextmanager
from typing import AsyncIterator

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import Settings
from .container import AppContainer
from .errors import install_exception_handlers
from .routers import (
    auth,
    catalog,
    conversations,
    health,
    matches,
    profile,
    requests,
    users,
    ws,
)


def create_app(settings: Settings | None = None) -> FastAPI:
    resolved_settings = settings or Settings.from_env()
    container = AppContainer(resolved_settings)

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        try:
            if container.database is not None:
                container.database.check()
            yield
        finally:
            container.close()

    app = FastAPI(
        title="TutorMatch A.I. API",
        version="0.1.0",
        lifespan=lifespan,
    )
    app.state.container = container
    app.add_middleware(
        CORSMiddleware,
        allow_origins=list(resolved_settings.cors_origins),
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    install_exception_handlers(app)
    app.include_router(health.router)
    app.include_router(auth.router)
    app.include_router(profile.router)
    app.include_router(users.router)
    app.include_router(catalog.router)
    app.include_router(matches.router)
    app.include_router(requests.router)
    app.include_router(conversations.router)
    app.include_router(ws.router)
    return app


app = create_app()
