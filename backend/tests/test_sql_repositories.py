from __future__ import annotations

import os
from datetime import datetime, timedelta, timezone
from pathlib import Path
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import text

import app.db.models  # noqa: F401  (register tables on Base.metadata)
from app.config import Settings
from app.container import AppContainer
from app.database import Database
from app.db.base import Base
from app.errors import DuplicateEmailError
from app.main import create_app
from app.models.auth import RefreshToken
from app.models.chat import (
    ChatMessage,
    Conversation,
    ConversationEvent,
    ConversationEventType,
    MessageKind,
    RequestStatus,
)
from app.models.profile import Profile
from app.models.user import Role, SecurityAnswer, User
from app.repositories.sql import (
    SqlConversationRepository,
    SqlProfileRepository,
    SqlRefreshTokenRepository,
    SqlUserRepository,
)
from tests.registration import COMPLIANT_PASSWORD, registration_payload

TEST_DATABASE_URL = os.getenv("TEST_DATABASE_URL", "").strip()

pytestmark = pytest.mark.skipif(
    not TEST_DATABASE_URL,
    reason="Set TEST_DATABASE_URL to run PostgreSQL integration tests.",
)


@pytest.fixture(scope="session")
def sql_database() -> Database:
    settings = Settings(
        app_env="test",
        jwt_secret="test-secret-" + ("x" * 48),
        storage_backend="postgres",
        database_url=TEST_DATABASE_URL,
    )
    database = Database(settings)
    Base.metadata.drop_all(database.engine)
    Base.metadata.create_all(database.engine)
    yield database
    Base.metadata.drop_all(database.engine)
    with database.engine.begin() as connection:
        connection.execute(text("DROP TABLE IF EXISTS alembic_version"))
    database.dispose()


@pytest.fixture()
def sql_repositories(sql_database: Database):
    with sql_database.engine.begin() as connection:
        connection.execute(text("TRUNCATE users CASCADE"))

    yield {
        "users": SqlUserRepository(sql_database),
        "profiles": SqlProfileRepository(sql_database),
        "tokens": SqlRefreshTokenRepository(sql_database),
        "conversations": SqlConversationRepository(sql_database),
    }


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _user(
    *,
    user_id: str | None = None,
    email: str = "user@example.com",
    role: Role = Role.student,
    display_name: str = "Test User",
) -> User:
    now = _now()
    return User(
        id=user_id or str(uuid4()),
        email=email,
        password_hash="hash",
        role=role,
        display_name=display_name,
        phone="1234567",
        onboarding_complete=True,
        privacy_consent=True,
        privacy_consent_at=now,
        privacy_policy_version="2026-10-v1",
        security_answers=[
            SecurityAnswer(question_id="q1", answer_hash="h1"),
            SecurityAnswer(question_id="q2", answer_hash="h2"),
        ],
        created_at=now,
        updated_at=now,
    )


def _profile(user_id: str) -> Profile:
    return Profile(
        user_id=user_id,
        name="Test User",
        subjects=["Calculus"],
        style="Visual",
        mode="online",
        budget=40,
        availability=[True] * 21,
        goal="Pass",
        area_id="london-highbury",
        location_privacy="area",
        presence="busy",
        languages=["English"],
        updated_at=_now(),
    )


def _conversation(student_id: str, tutor_id: str) -> Conversation:
    now = _now()
    conversation = Conversation(
        id=str(uuid4()),
        student_id=student_id,
        tutor_id=tutor_id,
        subject="Calculus",
        score=80,
        note="Could you help me with derivatives?",
        status=RequestStatus.pending,
        requested_by=student_id,
        created_at=now,
        updated_at=now,
        last_read_sequences={student_id: 0, tutor_id: 0},
    )
    message = ChatMessage(
        id=str(uuid4()),
        conversation_id=conversation.id,
        sender_id=student_id,
        kind=MessageKind.text,
        text=conversation.note,
        sequence=1,
        created_at=now,
    )
    conversation.messages.append(message)
    conversation.next_message_sequence = 2
    event = ConversationEvent(
        sequence=1,
        conversation_id=conversation.id,
        type=ConversationEventType.request_created,
        actor_id=student_id,
        created_at=now,
        message=message,
        request_status=RequestStatus.pending,
    )
    conversation.events.append(event)
    conversation.next_event_sequence = 2
    return conversation


def test_user_repository_round_trip_and_email_index(sql_repositories) -> None:
    users: SqlUserRepository = sql_repositories["users"]
    user = _user(email="User@Example.com")

    users.add(user)

    assert users.get_by_id(user.id) is not None
    assert users.get_by_email("USER@example.COM").id == user.id
    assert users.get_by_email("user@example.com").email == "user@example.com"
    assert len(users.list_all()) == 1
    assert users.export_state()[0]["id"] == user.id

    with pytest.raises(DuplicateEmailError):
        users.add(_user(email="user@example.com"))

    updated = user.model_copy(
        update={"email": "new@example.com", "display_name": "New Name"}
    )
    users.update(updated)

    assert users.get_by_email("old@example.com") is None
    assert users.get_by_email("new@example.com").display_name == "New Name"


def test_user_repository_import_replaces_rows(sql_repositories) -> None:
    users: SqlUserRepository = sql_repositories["users"]
    first = _user(email="first@example.com")
    users.add(first)

    second = _user(email="second@example.com")
    users.import_state([second.model_dump(mode="json")])

    assert users.get_by_id(first.id) is None
    assert users.get_by_email("second@example.com").id == second.id


def test_profile_repository_round_trip(sql_repositories) -> None:
    users: SqlUserRepository = sql_repositories["users"]
    profiles: SqlProfileRepository = sql_repositories["profiles"]
    user = _user()
    users.add(user)
    profile = _profile(user.id)

    profiles.add(profile)

    assert profiles.get_by_user_id(user.id) == profile
    assert profiles.list_all() == [profile]

    updated = profile.model_copy(update={"budget": 55})
    profiles.update(updated)
    assert profiles.get_by_user_id(user.id).budget == 55

    with pytest.raises(ValueError):
        profiles.add(profile)


def test_refresh_token_repository_revocation(sql_repositories) -> None:
    users: SqlUserRepository = sql_repositories["users"]
    tokens: SqlRefreshTokenRepository = sql_repositories["tokens"]
    user = _user()
    users.add(user)
    now = _now()
    first = RefreshToken(
        jti="first",
        user_id=user.id,
        expires_at=now + timedelta(days=1),
        created_at=now,
    )
    second = RefreshToken(
        jti="second",
        user_id=user.id,
        expires_at=now + timedelta(days=1),
        created_at=now,
    )
    tokens.add(first)
    tokens.add(second)

    tokens.revoke("first", replaced_by_jti="replacement")
    assert tokens.get_by_jti("first").revoked_at is not None
    assert tokens.get_by_jti("first").replaced_by_jti == "replacement"

    tokens.revoke_all_for_user(user.id)
    assert tokens.get_by_jti("second").revoked_at is not None
    assert len(tokens.list_all()) == 2


def test_conversation_repository_preserves_aggregate(sql_repositories) -> None:
    users: SqlUserRepository = sql_repositories["users"]
    conversations: SqlConversationRepository = sql_repositories["conversations"]
    student = _user(email="student@example.com")
    tutor = _user(
        email="tutor@example.com",
        role=Role.tutor,
        display_name="Tutor",
    )
    users.add(student)
    users.add(tutor)
    conversation = _conversation(student.id, tutor.id)

    conversations.add(conversation)

    assert conversations.get_by_id(conversation.id) == conversation
    assert conversations.get_between(student.id, tutor.id) == conversation
    assert conversations.get_between(tutor.id, student.id) == conversation
    assert conversations.get_between(student.id, student.id) is None
    assert conversations.list_all() == [conversation]

    now = _now()
    conversation.status = RequestStatus.accepted
    conversation.updated_at = now
    second_message = ChatMessage(
        id=str(uuid4()),
        conversation_id=conversation.id,
        sender_id=tutor.id,
        kind=MessageKind.text,
        text="Yes, happy to help.",
        sequence=2,
        created_at=now,
    )
    conversation.messages.append(second_message)
    conversation.next_message_sequence = 3
    conversation.last_read_sequences[tutor.id] = 2
    second_event = ConversationEvent(
        sequence=2,
        conversation_id=conversation.id,
        type=ConversationEventType.request_accepted,
        actor_id=tutor.id,
        created_at=now,
        message=second_message,
        request_status=RequestStatus.accepted,
    )
    conversation.events.append(second_event)
    conversation.next_event_sequence = 3

    conversations.update(conversation)

    reloaded = conversations.get_by_id(conversation.id)
    assert reloaded == conversation
    assert reloaded.messages[1].text == "Yes, happy to help."
    assert reloaded.events[1].message.id == second_message.id
    assert reloaded.last_read_sequences[tutor.id] == 2

    with pytest.raises(ValueError):
        conversations.add(_conversation(student.id, tutor.id))


def test_container_uses_postgres_repositories(
    sql_database: Database,
    tmp_path: Path,
) -> None:
    settings = Settings(
        app_env="test",
        jwt_secret="test-secret-" + ("x" * 48),
        storage_backend="postgres",
        database_url=str(sql_database.engine.url),
        upload_path=tmp_path / "uploads",
    )
    container = AppContainer(settings)
    try:
        assert isinstance(container.users, SqlUserRepository)
        assert isinstance(container.profiles, SqlProfileRepository)
        assert isinstance(container.refresh_tokens, SqlRefreshTokenRepository)
        assert isinstance(container.conversations, SqlConversationRepository)
        assert container.database is not None
    finally:
        container.close()


def test_app_registers_and_restores_a_user_from_postgres(
    sql_database: Database,
    tmp_path: Path,
) -> None:
    settings = Settings(
        app_env="test",
        jwt_secret="test-secret-" + ("x" * 48),
        storage_backend="postgres",
        database_url=str(sql_database.engine.url),
        upload_path=tmp_path / "uploads",
    )
    with sql_database.engine.begin() as connection:
        connection.execute(text("TRUNCATE users CASCADE"))

    first_app = create_app(settings)
    with TestClient(first_app) as client:
        registered = client.post(
            "/auth/register",
            json=registration_payload(email="postgres@example.com"),
        )
        assert registered.status_code == 201, registered.text

    second_app = create_app(settings)
    with TestClient(second_app) as client:
        login = client.post(
            "/auth/login",
            json={
                "email": "postgres@example.com",
                "password": COMPLIANT_PASSWORD,
            },
        )
        assert login.status_code == 200, login.text
        access = login.json()["access_token"]
        me = client.get(
            "/auth/me",
            headers={"Authorization": f"Bearer {access}"},
        )
        assert me.status_code == 200, me.text
        assert me.json()["email"] == "postgres@example.com"
