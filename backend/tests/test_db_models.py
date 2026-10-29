from __future__ import annotations

from sqlalchemy import CheckConstraint, UniqueConstraint
from sqlalchemy.orm import configure_mappers

import app.db.models  # noqa: F401  (register tables on Base.metadata)
from app.db.base import Base

_EXPECTED_TABLES = {
    "users",
    "security_answers",
    "profiles",
    "refresh_tokens",
    "conversations",
    "messages",
    "conversation_events",
    "conversation_reads",
}


def test_models_define_every_expected_table() -> None:
    assert set(Base.metadata.tables) == _EXPECTED_TABLES


def test_relationships_configure_cleanly() -> None:
    configure_mappers()


def test_key_constraints_and_indexes_are_registered() -> None:
    users = Base.metadata.tables["users"]
    assert any(
        isinstance(constraint, CheckConstraint)
        and constraint.name == "ck_users_role"
        for constraint in users.constraints
    )
    assert any(
        index.name == "ix_users_email" and index.unique
        for index in users.indexes
    )

    conversations = Base.metadata.tables["conversations"]
    assert any(
        isinstance(constraint, UniqueConstraint)
        and constraint.name == "uq_conversations_student_tutor"
        for constraint in conversations.constraints
    )

    messages = Base.metadata.tables["messages"]
    assert any(
        isinstance(constraint, UniqueConstraint)
        and constraint.name == "uq_messages_conversation_sequence"
        for constraint in messages.constraints
    )

    events = Base.metadata.tables["conversation_events"]
    assert any(
        isinstance(constraint, CheckConstraint)
        and constraint.name == "ck_events_type"
        for constraint in events.constraints
    )
