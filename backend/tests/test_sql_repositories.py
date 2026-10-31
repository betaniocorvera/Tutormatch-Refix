from __future__ import annotations

import os
import threading
from concurrent.futures import ThreadPoolExecutor
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
from app.errors import DuplicateEmailError, InvalidToken
from app.main import create_app
from app.models.auth import RefreshToken
from app.models.chat import (
    ChatMessage,
    Conversation,
    ConversationEvent,
    ConversationEventType,
    MessageKind,
    RequestStatus,
    SendTextRequest,
)
from app.models.profile import Profile
from app.models.user import RegisterRequest, Role, SecurityAnswer, User
from app.repositories.sql import (
    SqlConversationRepository,
    SqlProfileRepository,
    SqlRefreshTokenRepository,
    SqlUserRepository,
)
from app.services.auth import AuthResult
from scripts.import_snapshot import (
    SnapshotImportError,
    import_snapshot,
    load_snapshot,
    main as import_snapshot_main,
    summarize_snapshot,
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


def _sql_url(database: Database) -> str:
    # str(URL) masks the password, which would break an app built from it.
    return database.engine.url.render_as_string(hide_password=False)


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
        database_url=_sql_url(sql_database),
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
        database_url=_sql_url(sql_database),
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


def _sql_container(
    sql_database: Database,
    tmp_path: Path,
    name: str,
) -> AppContainer:
    return AppContainer(
        Settings(
            app_env="test",
            jwt_secret="test-secret-" + ("x" * 48),
            storage_backend="postgres",
            database_url=_sql_url(sql_database),
            upload_path=tmp_path / name,
        )
    )


def _register_with_container(
    container: AppContainer,
    *,
    email: str,
) -> AuthResult:
    payload = RegisterRequest.model_validate(
        registration_payload(email=email)
    )
    return container.auth.register(
        email=payload.email,
        password=payload.password,
        role=payload.role,
        display_name=payload.display_name,
        phone=payload.phone,
        area_id=payload.area_id,
        subjects=payload.subjects,
        security_questions=payload.security_questions,
        privacy_consent=payload.privacy_consent,
        privacy_policy_version=payload.privacy_policy_version,
    )


def test_database_transaction_rolls_back_multiple_repositories(
    sql_database: Database,
    sql_repositories,
) -> None:
    users: SqlUserRepository = sql_repositories["users"]
    profiles: SqlProfileRepository = sql_repositories["profiles"]
    user = _user(email="rollback@example.com")

    with pytest.raises(RuntimeError, match="boom"):
        with sql_database.transaction():
            users.add(user)
            profiles.add(_profile(user.id))
            raise RuntimeError("boom")

    assert users.get_by_id(user.id) is None
    assert profiles.get_by_user_id(user.id) is None


def test_unit_of_work_shares_the_repository_session(
    sql_database: Database,
    sql_repositories,
) -> None:
    users: SqlUserRepository = sql_repositories["users"]
    profiles: SqlProfileRepository = sql_repositories["profiles"]
    user = _user(email="uow@example.com")
    profile = _profile(user.id)

    with sql_database.unit_of_work():
        users.add(user)
        profiles.add(profile)

    assert users.get_by_id(user.id) is not None
    assert profiles.get_by_user_id(user.id) == profile


def test_unit_of_work_rolls_back_the_shared_session(
    sql_database: Database,
    sql_repositories,
) -> None:
    users: SqlUserRepository = sql_repositories["users"]
    user = _user(email="uow-rollback@example.com")

    with pytest.raises(RuntimeError, match="boom"):
        with sql_database.unit_of_work():
            users.add(user)
            raise RuntimeError("boom")

    assert users.get_by_id(user.id) is None


def test_registration_rolls_back_the_user_when_profile_write_fails(
    sql_database: Database,
    tmp_path: Path,
    monkeypatch,
) -> None:
    with sql_database.engine.begin() as connection:
        connection.execute(text("TRUNCATE users CASCADE"))

    container = _sql_container(sql_database, tmp_path, "atomic-registration")
    try:
        def fail_profile_add(profile: Profile) -> None:
            raise RuntimeError("profile write failed")

        monkeypatch.setattr(
            container.profiles,
            "add",
            fail_profile_add,
        )

        with pytest.raises(RuntimeError, match="profile write failed"):
            _register_with_container(
                container,
                email="atomic-registration@example.com",
            )

        assert (
            container.users.get_by_email(
                "atomic-registration@example.com"
            )
            is None
        )
    finally:
        container.close()


def test_concurrent_messages_are_serialised_by_the_conversation_lock(
    sql_database: Database,
    sql_repositories,
    tmp_path: Path,
) -> None:
    users: SqlUserRepository = sql_repositories["users"]
    conversations: SqlConversationRepository = sql_repositories["conversations"]
    student = _user(email="lock-student@example.com")
    tutor = _user(
        email="lock-tutor@example.com",
        role=Role.tutor,
        display_name="Lock Tutor",
    )
    users.add(student)
    users.add(tutor)
    conversation = _conversation(student.id, tutor.id)
    conversation.status = RequestStatus.accepted
    conversations.add(conversation)

    first = _sql_container(sql_database, tmp_path, "first")
    second = _sql_container(sql_database, tmp_path, "second")
    barrier = threading.Barrier(2)

    def send(container: AppContainer, text: str):
        barrier.wait(timeout=10)
        return container.chat.send_text(
            student,
            conversation.id,
            SendTextRequest(text=text),
        )

    try:
        with ThreadPoolExecutor(max_workers=2) as executor:
            first_future = executor.submit(send, first, "First writer")
            second_future = executor.submit(send, second, "Second writer")
            first_future.result(timeout=30)
            second_future.result(timeout=30)
    finally:
        first.close()
        second.close()

    reloaded = conversations.get_by_id(conversation.id)
    assert reloaded is not None
    assert [message.sequence for message in reloaded.messages] == [1, 2, 3]
    assert {message.text for message in reloaded.messages[1:]} == {
        "First writer",
        "Second writer",
    }


def test_refresh_rotation_is_atomic_across_containers(
    sql_database: Database,
    tmp_path: Path,
) -> None:
    with sql_database.engine.begin() as connection:
        connection.execute(text("TRUNCATE users CASCADE"))

    first = _sql_container(sql_database, tmp_path, "refresh-first")
    second = _sql_container(sql_database, tmp_path, "refresh-second")
    try:
        result = _register_with_container(
            first,
            email="refresh-race@example.com",
        )
        refresh_token = result.refresh.token
        barrier = threading.Barrier(2)

        def rotate(container: AppContainer):
            barrier.wait(timeout=10)
            try:
                container.auth.refresh(refresh_token)
            except InvalidToken:
                return "invalid"
            return "ok"

        with ThreadPoolExecutor(max_workers=2) as executor:
            outcomes = [
                future.result(timeout=30)
                for future in (
                    executor.submit(rotate, first),
                    executor.submit(rotate, second),
                )
            ]
    finally:
        first.close()
        second.close()

    assert sorted(outcomes) == ["invalid", "ok"]


def test_ready_checks_postgres_and_reports_degraded_state(
    sql_database: Database,
    tmp_path: Path,
    monkeypatch,
) -> None:
    settings = Settings(
        app_env="test",
        jwt_secret="test-secret-" + ("x" * 48),
        storage_backend="postgres",
        database_url=_sql_url(sql_database),
        upload_path=tmp_path / "ready",
    )
    app = create_app(settings)
    with TestClient(app) as client:
        ready = client.get("/ready")
        assert ready.status_code == 200
        assert ready.json() == {
            "status": "ready",
            "storage": "postgres",
        }

        database = app.state.container.database
        assert database is not None

        def fail_check() -> None:
            raise RuntimeError("database unavailable")

        monkeypatch.setattr(database, "check", fail_check)
        degraded = client.get("/ready")
        assert degraded.status_code == 503
        assert degraded.json() == {
            "status": "not_ready",
            "storage": "postgres",
        }

def _snapshot_payload(
    *,
    users: list[User],
    profiles: list[Profile],
    conversations: list[Conversation],
) -> dict[str, list[dict]]:
    return {
        "users": [user.model_dump(mode="json") for user in users],
        "profiles": [
            profile.model_dump(mode="json") for profile in profiles
        ],
        "refresh_tokens": [],
        "conversations": [
            conversation.model_dump(mode="json")
            for conversation in conversations
        ],
    }


def test_import_snapshot_replaces_existing_data(
    sql_database: Database,
    sql_repositories,
    tmp_path: Path,
) -> None:
    users: SqlUserRepository = sql_repositories["users"]
    profiles: SqlProfileRepository = sql_repositories["profiles"]
    conversations: SqlConversationRepository = sql_repositories["conversations"]
    student = _user(email="snapshot-student@example.com")
    tutor = _user(
        email="snapshot-tutor@example.com",
        role=Role.tutor,
        display_name="Snapshot Tutor",
    )
    users.add(student)
    users.add(tutor)
    profile = _profile(student.id)
    profiles.add(profile)
    conversation = _conversation(student.id, tutor.id)
    conversations.add(conversation)
    payload = _snapshot_payload(
        users=[student, tutor],
        profiles=[profile],
        conversations=[conversation],
    )

    imported = import_snapshot(
        sql_database,
        payload,
        replace_existing=True,
    )

    assert imported == summarize_snapshot(payload)
    assert users.get_by_id(student.id) is not None
    assert profiles.get_by_user_id(student.id) == profile
    reloaded = conversations.get_by_id(conversation.id)
    assert reloaded is not None
    assert reloaded.id == conversation.id


def test_import_snapshot_refuses_a_non_empty_database_without_replace(
    sql_database: Database,
    sql_repositories,
) -> None:
    users: SqlUserRepository = sql_repositories["users"]
    users.add(_user(email="snapshot-existing@example.com"))
    payload = _snapshot_payload(
        users=[],
        profiles=[],
        conversations=[],
    )

    with pytest.raises(
        SnapshotImportError,
        match="already contains data",
    ):
        import_snapshot(sql_database, payload)


def test_import_snapshot_rolls_back_invalid_data(
    sql_database: Database,
    sql_repositories,
) -> None:
    users: SqlUserRepository = sql_repositories["users"]
    existing = _user(email="snapshot-rollback@example.com")
    users.add(existing)
    payload = _snapshot_payload(
        users=[existing],
        profiles=[_profile("missing-user")],
        conversations=[],
    )

    with pytest.raises(SnapshotImportError):
        import_snapshot(
            sql_database,
            payload,
            replace_existing=True,
        )

    assert users.get_by_id(existing.id) is not None


def test_import_snapshot_loads_and_dry_runs_without_a_database(
    tmp_path: Path,
) -> None:
    snapshot = tmp_path / "store.json"
    snapshot.write_text(
        '{"users": [], "profiles": [], "refresh_tokens": [], '
        '"conversations": []}',
        encoding="utf-8",
    )

    payload = load_snapshot(snapshot)
    assert summarize_snapshot(payload).users == 0
    assert import_snapshot_main(
        ["--snapshot", str(snapshot), "--dry-run"]
    ) == 0

def test_postgres_api_end_to_end_and_restart(
    sql_database: Database,
    tmp_path: Path,
) -> None:
    settings = Settings(
        app_env="test",
        jwt_secret="test-secret-" + ("x" * 48),
        storage_backend="postgres",
        database_url=_sql_url(sql_database),
        upload_path=tmp_path / "e2e-uploads",
    )
    with sql_database.engine.begin() as connection:
        connection.execute(text("TRUNCATE users CASCADE"))

    app = create_app(settings)
    with TestClient(app) as client:
        student = client.post(
            "/auth/register",
            json=registration_payload(
                email="e2e-student@example.com",
                role="student",
                display_name="Postgres Student",
            ),
        )
        assert student.status_code == 201, student.text
        student_body = student.json()
        student_id = student_body["user"]["id"]
        student_headers = {
            "Authorization": f"Bearer {student_body['access_token']}"
        }

        tutor = client.post(
            "/auth/register",
            json=registration_payload(
                email="e2e-tutor@example.com",
                role="tutor",
                display_name="Postgres Tutor",
            ),
        )
        assert tutor.status_code == 201, tutor.text
        tutor_body = tutor.json()
        tutor_id = tutor_body["user"]["id"]
        tutor_headers = {
            "Authorization": f"Bearer {tutor_body['access_token']}"
        }

        student_profile = client.put(
            "/profile",
            headers=student_headers,
            json={
                "subjects": ["Calculus"],
                "style": (
                    "Watch one worked example, then do the next one myself"
                ),
                "availability": [True] * 21,
                "goal": "Pass a specific exam that is coming up",
                "budget": 40,
                "area_id": "london-highbury",
            },
        )
        assert student_profile.status_code == 200, student_profile.text

        tutor_profile = client.put(
            "/profile",
            headers=tutor_headers,
            json={
                "subjects": ["Calculus"],
                "style": (
                    "I work through examples slowly and let the student "
                    "steer"
                ),
                "availability": [True] * 21,
                "goal": "Fill a few steady evenings a week",
                "budget": 40,
                "area_id": "london-highbury",
            },
        )
        assert tutor_profile.status_code == 200, tutor_profile.text

        matches = client.get("/matches", headers=student_headers)
        assert matches.status_code == 200, matches.text
        assert any(
            item["profile"]["id"] == tutor_id
            for item in matches.json()["matches"]
        ), matches.text

        request = client.post(
            "/requests",
            headers=student_headers,
            json={
                "counterpart_id": tutor_id,
                "subject": "Calculus",
                "note": "Could you help me with derivatives this week?",
            },
        )
        assert request.status_code == 201, request.text
        conversation_id = request.json()["conversation_id"]

        accepted = client.post(
            f"/requests/{conversation_id}/accept",
            headers=tutor_headers,
            json={"note": "Yes, happy to help."},
        )
        assert accepted.status_code == 200, accepted.text

        sent = client.post(
            f"/conversations/{conversation_id}/messages",
            headers=student_headers,
            json={"text": "Great, thank you!"},
        )
        assert sent.status_code == 201, sent.text

        messages = client.get(
            f"/conversations/{conversation_id}/messages",
            headers=student_headers,
        )
        assert messages.status_code == 200, messages.text
        assert len(messages.json()["messages"]) >= 3

        read = client.post(
            f"/conversations/{conversation_id}/read",
            headers=tutor_headers,
            json={},
        )
        assert read.status_code == 200, read.text

        events = client.get(
            f"/conversations/{conversation_id}/events",
            headers=student_headers,
        )
        assert events.status_code == 200, events.text
        assert len(events.json()["events"]) >= 4

        detail = client.get(
            f"/conversations/{conversation_id}",
            headers=student_headers,
        )
        assert detail.status_code == 200, detail.text

    second_app = create_app(settings)
    with TestClient(second_app) as second_client:
        login = second_client.post(
            "/auth/login",
            json={
                "email": "e2e-student@example.com",
                "password": COMPLIANT_PASSWORD,
            },
        )
        assert login.status_code == 200, login.text
        second_headers = {
            "Authorization": f"Bearer {login.json()['access_token']}"
        }
        second_detail = second_client.get(
            f"/conversations/{conversation_id}",
            headers=second_headers,
        )
        assert second_detail.status_code == 200, second_detail.text
        assert second_detail.json()["id"] == conversation_id

def test_conversation_update_does_not_rewrite_unchanged_children(
    sql_database: Database,
    sql_repositories,
) -> None:
    users: SqlUserRepository = sql_repositories["users"]
    conversations: SqlConversationRepository = sql_repositories["conversations"]
    student = _user(email="diff-student@example.com")
    tutor = _user(
        email="diff-tutor@example.com",
        role=Role.tutor,
        display_name="Diff Tutor",
    )
    users.add(student)
    users.add(tutor)
    conversation = _conversation(student.id, tutor.id)
    conversations.add(conversation)
    message_id = conversation.messages[0].id

    def message_xmin() -> str:
        with sql_database.engine.connect() as connection:
            return connection.execute(
                text("SELECT xmin::text FROM messages WHERE id = :id"),
                {"id": message_id},
            ).scalar_one()

    before = message_xmin()
    conversations.update(conversation)
    after = message_xmin()

    assert after == before

def test_import_snapshot_accepts_a_utf8_bom(tmp_path: Path) -> None:
    snapshot = tmp_path / "bom-store.json"
    snapshot.write_text(
        '\ufeff{"users": [], "profiles": [], "refresh_tokens": [], '
        '"conversations": []}',
        encoding="utf-8",
    )

    assert summarize_snapshot(load_snapshot(snapshot)).users == 0
