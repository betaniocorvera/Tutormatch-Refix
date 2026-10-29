"""Alembic environment for the TutorMatch PostgreSQL schema.

The database URL comes from ``backend/.env`` through the same Settings loader
used by the application. Alembic's ini value is only a fallback for offline
commands; it is never committed with a real password.
"""

from __future__ import annotations

from logging.config import fileConfig

from alembic import context
from sqlalchemy import engine_from_config, pool

from app.config import Settings
from app.db.base import Base
import app.db.models  # noqa: F401  (register tables on Base.metadata)

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

database_url = (
    Settings.from_env().database_url
    or config.get_main_option("sqlalchemy.url")
    or ""
)
if not database_url:
    raise RuntimeError(
        "DATABASE_URL is not set. Add it to backend/.env before running "
        "Alembic."
    )

# ConfigParser treats % as interpolation; escape it for URLs with encoded
# characters or query strings.
config.set_main_option("sqlalchemy.url", database_url.replace("%", "%%"))

target_metadata = Base.metadata


def run_migrations_offline() -> None:
    """Run migrations without creating a database connection."""

    context.configure(
        url=config.get_main_option("sqlalchemy.url"),
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        compare_type=True,
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """Run migrations against a live PostgreSQL database."""

    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            compare_type=True,
        )

        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
