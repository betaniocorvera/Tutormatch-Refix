"""add case-insensitive email uniqueness

Revision ID: b2d4c9f1a7e3
Revises: edf78218dfd6
Create Date: 2026-10-30 12:00:00.000000

The service normalizes email addresses before storage. This functional index
keeps that invariant for rows written by migrations, scripts, or future
clients that bypass the service layer.
"""

from typing import Sequence, Union

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "b2d4c9f1a7e3"
down_revision: Union[str, Sequence[str], None] = "edf78218dfd6"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        "CREATE UNIQUE INDEX uq_users_email_lower "
        "ON users (lower(email))"
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS uq_users_email_lower")
