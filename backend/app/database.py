"""PostgreSQL engine, session factory, and transaction boundary.

The application still uses the in-memory repositories until the SQL
repositories are wired in a later phase. This module provides the database
plumbing they will use: one engine per process, a session factory, a small
unit of work, and a connection check for readiness probes.
"""

from __future__ import annotations

from contextlib import contextmanager
from typing import Iterator

from sqlalchemy import Engine, create_engine, text
from sqlalchemy.orm import Session, sessionmaker

from .config import Settings


class Database:
    """Owns the SQLAlchemy engine and session factory for one application."""

    def __init__(self, settings: Settings) -> None:
        if not settings.database_url:
            raise ValueError(
                "DATABASE_URL is not configured. Set it before creating a "
                "PostgreSQL database connection."
            )

        connect_args: dict[str, object] = {}
        if settings.database_ssl_mode:
            connect_args["sslmode"] = settings.database_ssl_mode

        self._engine = create_engine(
            settings.database_url,
            pool_pre_ping=True,
            pool_size=settings.database_pool_size,
            max_overflow=settings.database_max_overflow,
            pool_timeout=settings.database_pool_timeout_seconds,
            echo=settings.database_echo,
            connect_args=connect_args,
        )
        self._session_factory = sessionmaker(
            bind=self._engine,
            autoflush=False,
            expire_on_commit=False,
        )

    @property
    def engine(self) -> Engine:
        return self._engine

    @property
    def session_factory(self) -> sessionmaker[Session]:
        return self._session_factory

    @contextmanager
    def session(self) -> Iterator[Session]:
        """Yield a session, committing on success and rolling back on error."""

        session = self._session_factory()
        try:
            yield session
            session.commit()
        except BaseException:
            session.rollback()
            raise
        finally:
            session.close()

    def unit_of_work(self) -> "UnitOfWork":
        return UnitOfWork(self._session_factory)

    def check(self) -> None:
        """Raise if PostgreSQL cannot answer a trivial query."""

        with self._engine.connect() as connection:
            connection.execute(text("SELECT 1"))

    def dispose(self) -> None:
        self._engine.dispose()


class UnitOfWork:
    """One transaction spanning one or more repositories.

    Repositories should receive ``uow.session`` so a multi-table operation,
    such as registration or accepting a request, commits or rolls back as one
    unit.
    """

    def __init__(self, session_factory: sessionmaker[Session]) -> None:
        self._session_factory = session_factory
        self._session: Session | None = None

    @property
    def session(self) -> Session:
        if self._session is None:
            raise RuntimeError(
                "UnitOfWork.session is only available inside a context."
            )
        return self._session

    def __enter__(self) -> "UnitOfWork":
        self._session = self._session_factory()
        return self

    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        traceback: object,
    ) -> None:
        if self._session is None:
            return
        try:
            if exc_type is None:
                self._session.commit()
            else:
                self._session.rollback()
        finally:
            self._session.close()
            self._session = None

    def commit(self) -> None:
        self.session.commit()

    def rollback(self) -> None:
        self.session.rollback()


__all__ = ["Database", "UnitOfWork"]
