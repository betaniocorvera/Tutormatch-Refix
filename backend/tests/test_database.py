from __future__ import annotations

import pytest

from app.config import Settings
from app.database import Database, UnitOfWork


def _database_settings() -> Settings:
    return Settings(
        jwt_secret="s" * 64,
        database_url=(
            "postgresql+psycopg://user:pass@localhost:5432/tutormatch"
        ),
        database_pool_size=2,
        database_max_overflow=3,
        database_pool_timeout_seconds=5.0,
    )


def test_database_builds_engine_without_connecting() -> None:
    database = Database(_database_settings())
    try:
        assert database.engine.url.drivername == "postgresql+psycopg"
        assert database.session_factory.kw["bind"] is database.engine
    finally:
        database.dispose()


def test_database_requires_a_url() -> None:
    with pytest.raises(ValueError, match="DATABASE_URL is not configured"):
        Database(Settings(jwt_secret="s" * 64))


class _FakeSession:
    def __init__(self) -> None:
        self.committed = False
        self.rolled_back = False
        self.closed = False

    def commit(self) -> None:
        self.committed = True

    def rollback(self) -> None:
        self.rolled_back = True

    def close(self) -> None:
        self.closed = True


def test_unit_of_work_commits_and_closes_on_success() -> None:
    session = _FakeSession()
    unit_of_work = UnitOfWork(lambda: session)

    with unit_of_work:
        assert unit_of_work.session is session

    assert session.committed is True
    assert session.rolled_back is False
    assert session.closed is True


def test_unit_of_work_rolls_back_and_closes_on_error() -> None:
    session = _FakeSession()
    unit_of_work = UnitOfWork(lambda: session)

    with pytest.raises(RuntimeError, match="boom"):
        with unit_of_work:
            raise RuntimeError("boom")

    assert session.committed is False
    assert session.rolled_back is True
    assert session.closed is True
