"""PostgreSQL engine, session factory, and transaction boundary.

The application uses the in-memory repositories by default and can switch to
the SQL repositories with ``STORAGE_BACKEND=postgres``. This module provides the
shared engine, a session factory, a small unit of work, and a connection check
for readiness probes.
"""

from __future__ import annotations

from contextlib import contextmanager
from contextvars import ContextVar, Token
from typing import Iterator

from sqlalchemy import Engine, create_engine, text
from sqlalchemy.orm import Session, sessionmaker

from .config import Settings

# A repository method normally owns its own short transaction. Services that
# need several repository calls to succeed or fail together open an explicit
# transaction; repositories then join the session stored here instead of
# committing one call at a time.
_current_session: ContextVar[Session | None] = ContextVar(
    "tutormatch_current_session",
    default=None,
)
_transaction_active: ContextVar[bool] = ContextVar(
    "tutormatch_transaction_active",
    default=False,
)


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

    @property
    def in_transaction(self) -> bool:
        """Whether an explicit service transaction is active."""

        return _transaction_active.get()

    @contextmanager
    def operation(self) -> Iterator[Session]:
        """Yield the transaction session, or own one for a single operation.

        Repository methods use this instead of ``session()``. When a service
        opened ``transaction()``, every repository call joins that transaction
        and the service decides when to commit. Outside one, the method still
        gets a short-lived transaction with the same commit-on-success
        behavior as before.
        """

        current = _current_session.get()
        if current is not None:
            yield current
            return

        session = self._session_factory()
        token = _current_session.set(session)
        try:
            yield session
            session.commit()
        except BaseException:
            session.rollback()
            raise
        finally:
            _current_session.reset(token)
            session.close()

    @contextmanager
    def transaction(self) -> Iterator[None]:
        """Run several repository calls as one commit or rollback unit."""

        current = _current_session.get()
        if current is not None:
            yield
            return

        session = self._session_factory()
        session_token = _current_session.set(session)
        active_token = _transaction_active.set(True)
        try:
            yield
            session.commit()
        except BaseException:
            session.rollback()
            raise
        finally:
            _transaction_active.reset(active_token)
            _current_session.reset(session_token)
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

    Repositories automatically join the active session, so a multi-table
    operation such as registration or accepting a request commits or rolls
    back as one unit. ``uow.session`` remains available for code that needs
    raw SQLAlchemy access inside the scope.
    """

    def __init__(self, session_factory: sessionmaker[Session]) -> None:
        self._session_factory = session_factory
        self._session: Session | None = None
        self._owns_session = False
        self._session_token: Token[Session | None] | None = None
        self._active_token: Token[bool] | None = None

    @property
    def session(self) -> Session:
        if self._session is None:
            raise RuntimeError(
                "UnitOfWork.session is only available inside a context."
            )
        return self._session

    def __enter__(self) -> "UnitOfWork":
        current = _current_session.get()
        if current is not None:
            self._session = current
            self._owns_session = False
            return self

        self._session = self._session_factory()
        self._owns_session = True
        self._session_token = _current_session.set(self._session)
        self._active_token = _transaction_active.set(True)
        return self

    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        traceback: object,
    ) -> None:
        if self._session is None:
            return
        if not self._owns_session:
            self._session = None
            return

        try:
            if exc_type is None:
                self._session.commit()
            else:
                self._session.rollback()
        finally:
            if self._active_token is not None:
                _transaction_active.reset(self._active_token)
            if self._session_token is not None:
                _current_session.reset(self._session_token)
            self._session.close()
            self._session = None
            self._owns_session = False
            self._session_token = None
            self._active_token = None

    def commit(self) -> None:
        self.session.commit()

    def rollback(self) -> None:
        self.session.rollback()


__all__ = ["Database", "UnitOfWork"]
