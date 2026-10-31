"""PostgreSQL-backed repository implementations.

The service layer still works with the same Pydantic models and repository
interfaces as the in-memory implementation. Each repository method opens a
short-lived SQLAlchemy session, maps rows to those models, and commits before
returning. That keeps the synchronous service layer unchanged while still
using real database constraints and transactions.

Conversation aggregates are stored across the ``conversations``, ``messages``,
``conversation_events``, and ``conversation_reads`` tables. A conversation
update replaces the child rows in one transaction; the service layer never
edits one child independently.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from sqlalchemy import and_, delete, func, or_, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import selectinload

from ..database import Database
from ..db.models import (
    ConversationEventRow,
    ConversationReadRow,
    ConversationRow,
    MessageRow,
    ProfileRow,
    RefreshTokenRow,
    SecurityAnswerRow,
    UserRow,
)
from ..errors import DuplicateConversationError, DuplicateEmailError
from ..models.auth import RefreshToken
from ..models.chat import (
    CallKind,
    ChatMessage,
    Conversation,
    ConversationEvent,
    ConversationEventType,
    MessageKind,
    RequestStatus,
    SessionState,
)
from ..models.profile import (
    LocationPrivacy,
    PresenceStatus,
    Profile,
    SessionMode,
)
from ..models.user import Role, SecurityAnswer, User
from .interfaces import (
    ConversationRepository,
    ProfileRepository,
    RefreshTokenRepository,
    UserRepository,
)


def _normalized_email(email: object) -> str:
    return str(email).strip().lower()


def _is_email_conflict(exc: IntegrityError) -> bool:
    text = str(exc.orig).lower()
    return (
        "ix_users_email" in text
        or "users_email" in text
        or ("duplicate key" in text and "email" in text)
    )


def _is_conversation_conflict(exc: IntegrityError) -> bool:
    text = str(exc.orig).lower()
    return (
        "uq_conversations_student_tutor" in text
        or "conversations_pkey" in text
        or ("duplicate key" in text and "conversations" in text)
    )


def _user_row(user: User) -> UserRow:
    return UserRow(
        id=user.id,
        email=_normalized_email(user.email),
        password_hash=user.password_hash,
        role=user.role.value,
        display_name=user.display_name,
        phone=user.phone,
        onboarding_complete=user.onboarding_complete,
        privacy_consent=user.privacy_consent,
        privacy_consent_at=user.privacy_consent_at,
        privacy_policy_version=user.privacy_policy_version,
        created_at=user.created_at,
        updated_at=user.updated_at,
    )


def _security_answer_rows(user: User) -> list[SecurityAnswerRow]:
    return [
        SecurityAnswerRow(
            user_id=user.id,
            question_id=answer.question_id,
            answer_hash=answer.answer_hash,
        )
        for answer in user.security_answers
    ]


def _user_from_row(row: UserRow) -> User:
    return User(
        id=row.id,
        email=row.email,
        password_hash=row.password_hash,
        role=Role(row.role),
        display_name=row.display_name,
        phone=row.phone,
        onboarding_complete=row.onboarding_complete,
        privacy_consent=row.privacy_consent,
        privacy_consent_at=row.privacy_consent_at,
        privacy_policy_version=row.privacy_policy_version,
        security_answers=[
            SecurityAnswer(
                question_id=answer.question_id,
                answer_hash=answer.answer_hash,
            )
            for answer in row.security_answers
        ],
        created_at=row.created_at,
        updated_at=row.updated_at,
    )


def _user_statement():
    return select(UserRow).options(selectinload(UserRow.security_answers))


def _profile_row(profile: Profile) -> ProfileRow:
    return ProfileRow(
        user_id=profile.user_id,
        name=profile.name,
        subjects=list(profile.subjects),
        style=profile.style,
        mode=profile.mode.value,
        budget=profile.budget,
        availability=list(profile.availability),
        goal=profile.goal,
        birthdate=profile.birthdate,
        area_id=profile.area_id,
        location_privacy=profile.location_privacy.value,
        status_text=profile.status_text,
        presence=profile.presence.value,
        bio=profile.bio,
        gender=profile.gender,
        languages=list(profile.languages),
        years=profile.years,
        education=profile.education,
        grade=profile.grade,
        updated_at=profile.updated_at,
    )


def _apply_profile(row: ProfileRow, profile: Profile) -> None:
    row.name = profile.name
    row.subjects = list(profile.subjects)
    row.style = profile.style
    row.mode = profile.mode.value
    row.budget = profile.budget
    row.availability = list(profile.availability)
    row.goal = profile.goal
    row.birthdate = profile.birthdate
    row.area_id = profile.area_id
    row.location_privacy = profile.location_privacy.value
    row.status_text = profile.status_text
    row.presence = profile.presence.value
    row.bio = profile.bio
    row.gender = profile.gender
    row.languages = list(profile.languages)
    row.years = profile.years
    row.education = profile.education
    row.grade = profile.grade
    row.updated_at = profile.updated_at


def _profile_from_row(row: ProfileRow) -> Profile:
    return Profile(
        user_id=row.user_id,
        name=row.name,
        subjects=list(row.subjects),
        style=row.style,
        mode=SessionMode(row.mode),
        budget=row.budget,
        availability=list(row.availability),
        goal=row.goal,
        birthdate=row.birthdate,
        area_id=row.area_id,
        location_privacy=LocationPrivacy(row.location_privacy),
        status_text=row.status_text,
        presence=PresenceStatus(row.presence),
        bio=row.bio,
        gender=row.gender,
        languages=list(row.languages),
        years=row.years,
        education=row.education,
        grade=row.grade,
        updated_at=row.updated_at,
    )


def _refresh_token_row(token: RefreshToken) -> RefreshTokenRow:
    return RefreshTokenRow(
        jti=token.jti,
        user_id=token.user_id,
        expires_at=token.expires_at,
        created_at=token.created_at,
        revoked_at=token.revoked_at,
        replaced_by_jti=token.replaced_by_jti,
    )


def _refresh_token_from_row(row: RefreshTokenRow) -> RefreshToken:
    return RefreshToken(
        jti=row.jti,
        user_id=row.user_id,
        expires_at=row.expires_at,
        created_at=row.created_at,
        revoked_at=row.revoked_at,
        replaced_by_jti=row.replaced_by_jti,
    )


def _message_row(message: ChatMessage, conversation_id: str) -> MessageRow:
    return MessageRow(
        id=message.id,
        conversation_id=conversation_id,
        sender_id=message.sender_id,
        kind=message.kind.value,
        text=message.text,
        sequence=message.sequence,
        created_at=message.created_at,
        media_key=message.media_key,
        media_content_type=message.media_content_type,
        media_size=message.media_size,
        media_filename=message.media_filename,
        image_width=message.image_width,
        image_height=message.image_height,
        voice_seconds=message.voice_seconds,
        session_at=message.session_at,
        session_state=(
            message.session_state.value
            if message.session_state is not None
            else None
        ),
        call_kind=(
            message.call_kind.value
            if message.call_kind is not None
            else None
        ),
        call_connected=message.call_connected,
        call_duration_seconds=message.call_duration_seconds,
    )


def _message_from_row(row: MessageRow) -> ChatMessage:
    return ChatMessage(
        id=row.id,
        conversation_id=row.conversation_id,
        sender_id=row.sender_id,
        kind=MessageKind(row.kind),
        text=row.text,
        sequence=row.sequence,
        created_at=row.created_at,
        media_key=row.media_key,
        media_content_type=row.media_content_type,
        media_size=row.media_size,
        media_filename=row.media_filename,
        image_width=row.image_width,
        image_height=row.image_height,
        voice_seconds=row.voice_seconds,
        session_at=row.session_at,
        session_state=(
            SessionState(row.session_state)
            if row.session_state is not None
            else None
        ),
        call_kind=(
            CallKind(row.call_kind)
            if row.call_kind is not None
            else None
        ),
        call_connected=row.call_connected,
        call_duration_seconds=row.call_duration_seconds,
    )


def _event_row(
    event: ConversationEvent,
    conversation_id: str,
) -> ConversationEventRow:
    return ConversationEventRow(
        conversation_id=conversation_id,
        sequence=event.sequence,
        type=event.type.value,
        actor_id=event.actor_id,
        created_at=event.created_at,
        message_id=event.message.id if event.message is not None else None,
        request_status=(
            event.request_status.value
            if event.request_status is not None
            else None
        ),
        read_through_sequence=event.read_through_sequence,
        session_state=(
            event.session_state.value
            if event.session_state is not None
            else None
        ),
    )


def _conversation_children(
    conversation: Conversation,
) -> tuple[list[MessageRow], list[ConversationEventRow], list[ConversationReadRow]]:
    messages = list(conversation.messages)
    message_ids = {message.id for message in messages}
    # Events normally point at a message already in ``messages``. If an
    # aggregate was constructed by hand with an event-only message, persist it
    # too so the foreign key remains valid.
    for event in conversation.events:
        if event.message is not None and event.message.id not in message_ids:
            messages.append(event.message)
            message_ids.add(event.message.id)

    message_rows = [
        _message_row(message, conversation.id) for message in messages
    ]
    event_rows = [
        _event_row(event, conversation.id) for event in conversation.events
    ]
    read_rows = [
        ConversationReadRow(
            conversation_id=conversation.id,
            user_id=user_id,
            through_sequence=through_sequence,
        )
        for user_id, through_sequence in conversation.last_read_sequences.items()
    ]
    return message_rows, event_rows, read_rows


def _conversation_row(conversation: Conversation) -> ConversationRow:
    messages, events, reads = _conversation_children(conversation)
    return ConversationRow(
        id=conversation.id,
        student_id=conversation.student_id,
        tutor_id=conversation.tutor_id,
        subject=conversation.subject,
        score=conversation.score,
        note=conversation.note,
        status=conversation.status.value,
        requested_by=conversation.requested_by,
        created_at=conversation.created_at,
        updated_at=conversation.updated_at,
        responded_at=conversation.responded_at,
        response_note=conversation.response_note,
        next_message_sequence=conversation.next_message_sequence,
        next_event_sequence=conversation.next_event_sequence,
        messages=messages,
        events=events,
        reads=reads,
    )


def _apply_conversation(
    row: ConversationRow,
    conversation: Conversation,
) -> None:
    row.student_id = conversation.student_id
    row.tutor_id = conversation.tutor_id
    row.subject = conversation.subject
    row.score = conversation.score
    row.note = conversation.note
    row.status = conversation.status.value
    row.requested_by = conversation.requested_by
    row.created_at = conversation.created_at
    row.updated_at = conversation.updated_at
    row.responded_at = conversation.responded_at
    row.response_note = conversation.response_note
    row.next_message_sequence = conversation.next_message_sequence
    row.next_event_sequence = conversation.next_event_sequence


def _conversation_from_row(row: ConversationRow) -> Conversation:
    messages = [
        _message_from_row(message)
        for message in sorted(row.messages, key=lambda item: item.sequence)
    ]
    messages_by_id = {message.id: message for message in messages}
    events = [
        ConversationEvent(
            sequence=event.sequence,
            conversation_id=event.conversation_id,
            type=ConversationEventType(event.type),
            actor_id=event.actor_id,
            created_at=event.created_at,
            message=(
                messages_by_id.get(event.message_id)
                if event.message_id is not None
                else None
            ),
            request_status=(
                RequestStatus(event.request_status)
                if event.request_status is not None
                else None
            ),
            read_through_sequence=event.read_through_sequence,
            session_state=(
                SessionState(event.session_state)
                if event.session_state is not None
                else None
            ),
        )
        for event in sorted(row.events, key=lambda item: item.sequence)
    ]
    return Conversation(
        id=row.id,
        student_id=row.student_id,
        tutor_id=row.tutor_id,
        subject=row.subject,
        score=row.score,
        note=row.note,
        status=RequestStatus(row.status),
        requested_by=row.requested_by,
        created_at=row.created_at,
        updated_at=row.updated_at,
        responded_at=row.responded_at,
        response_note=row.response_note,
        messages=messages,
        events=events,
        next_message_sequence=row.next_message_sequence,
        next_event_sequence=row.next_event_sequence,
        last_read_sequences={
            read.user_id: read.through_sequence for read in row.reads
        },
    )


def _conversation_statement():
    return select(ConversationRow).options(
        selectinload(ConversationRow.messages),
        selectinload(ConversationRow.events),
        selectinload(ConversationRow.reads),
    )


def _pair_statement(first_user_id: str, second_user_id: str):
    return select(ConversationRow.id).where(
        or_(
            and_(
                ConversationRow.student_id == first_user_id,
                ConversationRow.tutor_id == second_user_id,
            ),
            and_(
                ConversationRow.student_id == second_user_id,
                ConversationRow.tutor_id == first_user_id,
            ),
        )
    )


class SqlUserRepository(UserRepository):
    def __init__(self, database: Database) -> None:
        self._database = database

    def get_by_id(self, user_id: str) -> User | None:
        with self._database.operation() as session:
            row = session.execute(
                _user_statement().where(UserRow.id == user_id)
            ).scalar_one_or_none()
            return _user_from_row(row) if row is not None else None

    def get_by_email(self, email: str) -> User | None:
        normalized = _normalized_email(email)
        with self._database.operation() as session:
            row = session.execute(
                _user_statement().where(
                    func.lower(UserRow.email) == normalized
                )
            ).scalar_one_or_none()
            return _user_from_row(row) if row is not None else None

    def add(self, user: User) -> None:
        email = _normalized_email(user.email)
        try:
            with self._database.operation() as session:
                if session.get(UserRow, user.id) is not None:
                    raise ValueError(f"User already exists: {user.id}")
                if (
                    session.execute(
                        select(UserRow.id).where(
                            func.lower(UserRow.email) == email
                        )
                    ).scalar_one_or_none()
                    is not None
                ):
                    raise DuplicateEmailError(email)
                session.add(_user_row(user))
                session.flush()
                session.add_all(_security_answer_rows(user))
        except IntegrityError as exc:
            if _is_email_conflict(exc):
                raise DuplicateEmailError(email) from exc
            raise

    def update(self, user: User) -> None:
        email = _normalized_email(user.email)
        try:
            with self._database.operation() as session:
                row = session.get(UserRow, user.id)
                if row is None:
                    raise KeyError(f"Unknown user: {user.id}")
                owner = session.execute(
                    select(UserRow.id).where(
                        func.lower(UserRow.email) == email,
                        UserRow.id != user.id,
                    )
                ).scalar_one_or_none()
                if owner is not None:
                    raise DuplicateEmailError(email)

                row.email = email
                row.password_hash = user.password_hash
                row.role = user.role.value
                row.display_name = user.display_name
                row.phone = user.phone
                row.onboarding_complete = user.onboarding_complete
                row.privacy_consent = user.privacy_consent
                row.privacy_consent_at = user.privacy_consent_at
                row.privacy_policy_version = user.privacy_policy_version
                row.created_at = user.created_at
                row.updated_at = user.updated_at

                session.execute(
                    delete(SecurityAnswerRow)
                    .where(SecurityAnswerRow.user_id == user.id)
                    .execution_options(synchronize_session=False)
                )
                session.add_all(_security_answer_rows(user))
                session.flush()
        except IntegrityError as exc:
            if _is_email_conflict(exc):
                raise DuplicateEmailError(email) from exc
            raise

    def list_all(self) -> list[User]:
        with self._database.operation() as session:
            rows = (
                session.execute(
                    _user_statement().order_by(
                        UserRow.created_at,
                        UserRow.id,
                    )
                )
                .scalars()
                .all()
            )
            return [_user_from_row(row) for row in rows]

    def export_state(self) -> list[dict[str, Any]]:
        return [user.model_dump(mode="json") for user in self.list_all()]

    def import_state(self, state: list[dict[str, Any]]) -> None:
        users = [User.model_validate(item) for item in state]
        try:
            with self._database.operation() as session:
                session.execute(
                    delete(UserRow).execution_options(
                        synchronize_session=False
                    )
                )
                session.add_all([_user_row(user) for user in users])
                session.flush()
                for user in users:
                    session.add_all(_security_answer_rows(user))
        except IntegrityError as exc:
            raise ValueError("Could not import users") from exc


class SqlProfileRepository(ProfileRepository):
    def __init__(self, database: Database) -> None:
        self._database = database

    def get_by_user_id(self, user_id: str) -> Profile | None:
        with self._database.operation() as session:
            row = session.get(ProfileRow, user_id)
            return _profile_from_row(row) if row is not None else None

    def add(self, profile: Profile) -> None:
        with self._database.operation() as session:
            if session.get(ProfileRow, profile.user_id) is not None:
                raise ValueError(
                    f"Profile already exists for user: {profile.user_id}"
                )
            if session.get(UserRow, profile.user_id) is None:
                raise ValueError(f"Unknown user: {profile.user_id}")
            session.add(_profile_row(profile))
            session.flush()

    def update(self, profile: Profile) -> None:
        with self._database.operation() as session:
            row = session.get(ProfileRow, profile.user_id)
            if row is None:
                raise KeyError(
                    f"Unknown profile for user: {profile.user_id}"
                )
            _apply_profile(row, profile)
            session.flush()

    def list_all(self) -> list[Profile]:
        with self._database.operation() as session:
            rows = (
                session.execute(
                    select(ProfileRow).order_by(
                        ProfileRow.updated_at,
                        ProfileRow.user_id,
                    )
                )
                .scalars()
                .all()
            )
            return [_profile_from_row(row) for row in rows]

    def export_state(self) -> list[dict[str, Any]]:
        return [
            profile.model_dump(mode="json")
            for profile in self.list_all()
        ]

    def import_state(self, state: list[dict[str, Any]]) -> None:
        profiles = [Profile.model_validate(item) for item in state]
        try:
            with self._database.operation() as session:
                session.execute(
                    delete(ProfileRow).execution_options(
                        synchronize_session=False
                    )
                )
                session.add_all([_profile_row(profile) for profile in profiles])
                session.flush()
        except IntegrityError as exc:
            raise ValueError("Could not import profiles") from exc


class SqlRefreshTokenRepository(RefreshTokenRepository):
    def __init__(self, database: Database) -> None:
        self._database = database

    def add(self, token: RefreshToken) -> None:
        try:
            with self._database.operation() as session:
                if session.get(RefreshTokenRow, token.jti) is not None:
                    raise ValueError(
                        f"Duplicate refresh token id: {token.jti}"
                    )
                session.add(_refresh_token_row(token))
                session.flush()
        except IntegrityError as exc:
            raise ValueError(
                f"Could not store refresh token: {token.jti}"
            ) from exc

    def get_by_jti(self, jti: str) -> RefreshToken | None:
        with self._database.operation() as session:
            statement = select(RefreshTokenRow).where(
                RefreshTokenRow.jti == jti
            )
            if self._database.in_transaction:
                statement = statement.with_for_update()
            row = session.execute(statement).scalar_one_or_none()
            return _refresh_token_from_row(row) if row is not None else None

    def revoke(self, jti: str, *, replaced_by_jti: str | None = None) -> None:
        now = datetime.now(timezone.utc)
        with self._database.operation() as session:
            session.execute(
                update(RefreshTokenRow)
                .where(
                    RefreshTokenRow.jti == jti,
                    RefreshTokenRow.revoked_at.is_(None),
                )
                .values(
                    revoked_at=now,
                    replaced_by_jti=replaced_by_jti,
                )
                .execution_options(synchronize_session=False)
            )

    def revoke_all_for_user(self, user_id: str) -> None:
        now = datetime.now(timezone.utc)
        with self._database.operation() as session:
            session.execute(
                update(RefreshTokenRow)
                .where(
                    RefreshTokenRow.user_id == user_id,
                    RefreshTokenRow.revoked_at.is_(None),
                )
                .values(revoked_at=now)
                .execution_options(synchronize_session=False)
            )

    def list_all(self) -> list[RefreshToken]:
        with self._database.operation() as session:
            rows = (
                session.execute(
                    select(RefreshTokenRow).order_by(
                        RefreshTokenRow.created_at,
                        RefreshTokenRow.jti,
                    )
                )
                .scalars()
                .all()
            )
            return [_refresh_token_from_row(row) for row in rows]

    def export_state(self) -> list[dict[str, Any]]:
        return [token.model_dump(mode="json") for token in self.list_all()]

    def import_state(self, state: list[dict[str, Any]]) -> None:
        tokens = [RefreshToken.model_validate(item) for item in state]
        try:
            with self._database.operation() as session:
                session.execute(
                    delete(RefreshTokenRow).execution_options(
                        synchronize_session=False
                    )
                )
                session.add_all([_refresh_token_row(token) for token in tokens])
                session.flush()
        except IntegrityError as exc:
            raise ValueError("Could not import refresh tokens") from exc


class SqlConversationRepository(ConversationRepository):
    def __init__(self, database: Database) -> None:
        self._database = database

    def get_by_id(self, conversation_id: str) -> Conversation | None:
        with self._database.operation() as session:
            statement = _conversation_statement().where(
                ConversationRow.id == conversation_id
            )
            if self._database.in_transaction:
                statement = statement.with_for_update()
            row = session.execute(statement).scalar_one_or_none()
            return _conversation_from_row(row) if row is not None else None

    def get_between(
        self,
        first_user_id: str,
        second_user_id: str,
    ) -> Conversation | None:
        if first_user_id == second_user_id:
            return None
        with self._database.operation() as session:
            statement = _conversation_statement().where(
                or_(
                    and_(
                        ConversationRow.student_id == first_user_id,
                        ConversationRow.tutor_id == second_user_id,
                    ),
                    and_(
                        ConversationRow.student_id == second_user_id,
                        ConversationRow.tutor_id == first_user_id,
                    ),
                )
            )
            if self._database.in_transaction:
                statement = statement.with_for_update()
            row = session.execute(statement).scalar_one_or_none()
            return _conversation_from_row(row) if row is not None else None

    def add(self, conversation: Conversation) -> None:
        try:
            with self._database.operation() as session:
                if session.get(ConversationRow, conversation.id) is not None:
                    raise DuplicateConversationError(
                        f"Conversation already exists: {conversation.id}"
                    )
                if (
                    session.execute(
                        _pair_statement(
                            conversation.student_id,
                            conversation.tutor_id,
                        )
                    ).scalar_one_or_none()
                    is not None
                ):
                    raise DuplicateConversationError(
                        "A conversation already exists for this pair"
                    )
                session.add(_conversation_row(conversation))
                session.flush()
        except IntegrityError as exc:
            if _is_conversation_conflict(exc):
                raise DuplicateConversationError(
                    f"Conversation already exists: {conversation.id}"
                ) from exc
            raise

    def update(self, conversation: Conversation) -> None:
        try:
            with self._database.operation() as session:
                row = session.execute(
                    select(ConversationRow)
                    .where(ConversationRow.id == conversation.id)
                    .with_for_update()
                ).scalar_one_or_none()
                if row is None:
                    raise KeyError(
                        f"Unknown conversation: {conversation.id}"
                    )

                _apply_conversation(row, conversation)
                messages, events, reads = _conversation_children(conversation)

                existing_messages = {
                    message.id: message
                    for message in session.execute(
                        select(MessageRow).where(
                            MessageRow.conversation_id == conversation.id
                        )
                    ).scalars()
                }
                existing_events = {
                    event.sequence: event
                    for event in session.execute(
                        select(ConversationEventRow).where(
                            ConversationEventRow.conversation_id
                            == conversation.id
                        )
                    ).scalars()
                }
                existing_reads = {
                    read.user_id: read
                    for read in session.execute(
                        select(ConversationReadRow).where(
                            ConversationReadRow.conversation_id
                            == conversation.id
                        )
                    ).scalars()
                }

                # Events reference messages, so remove obsolete events before
                # removing messages. Append-only chats then update only the new
                # rows instead of deleting and reinserting the whole thread.
                incoming_event_sequences = {
                    event.sequence for event in events
                }
                removed_event_sequences = (
                    set(existing_events) - incoming_event_sequences
                )
                if removed_event_sequences:
                    session.execute(
                        delete(ConversationEventRow)
                        .where(
                            ConversationEventRow.conversation_id
                            == conversation.id,
                            ConversationEventRow.sequence.in_(
                                removed_event_sequences
                            ),
                        )
                        .execution_options(synchronize_session=False)
                    )

                incoming_message_ids = {
                    message.id for message in messages
                }
                removed_message_ids = (
                    set(existing_messages) - incoming_message_ids
                )
                if removed_message_ids:
                    session.execute(
                        delete(MessageRow)
                        .where(MessageRow.id.in_(removed_message_ids))
                        .execution_options(synchronize_session=False)
                    )

                for incoming in messages:
                    existing = existing_messages.get(incoming.id)
                    if existing is None:
                        session.add(incoming)
                        continue
                    for key in (
                        "conversation_id",
                        "sender_id",
                        "kind",
                        "text",
                        "sequence",
                        "created_at",
                        "media_key",
                        "media_content_type",
                        "media_size",
                        "media_filename",
                        "image_width",
                        "image_height",
                        "voice_seconds",
                        "session_at",
                        "session_state",
                        "call_kind",
                        "call_connected",
                        "call_duration_seconds",
                    ):
                        value = getattr(incoming, key)
                        if getattr(existing, key) != value:
                            setattr(existing, key, value)

                for incoming in events:
                    existing = existing_events.get(incoming.sequence)
                    if existing is None:
                        session.add(incoming)
                        continue
                    for key in (
                        "type",
                        "actor_id",
                        "created_at",
                        "message_id",
                        "request_status",
                        "read_through_sequence",
                        "session_state",
                    ):
                        value = getattr(incoming, key)
                        if getattr(existing, key) != value:
                            setattr(existing, key, value)

                incoming_read_user_ids = {
                    read.user_id for read in reads
                }
                removed_read_user_ids = (
                    set(existing_reads) - incoming_read_user_ids
                )
                if removed_read_user_ids:
                    session.execute(
                        delete(ConversationReadRow)
                        .where(
                            ConversationReadRow.conversation_id
                            == conversation.id,
                            ConversationReadRow.user_id.in_(
                                removed_read_user_ids
                            ),
                        )
                        .execution_options(synchronize_session=False)
                    )
                for incoming in reads:
                    existing = existing_reads.get(incoming.user_id)
                    if existing is None:
                        session.add(incoming)
                    elif existing.through_sequence != incoming.through_sequence:
                        existing.through_sequence = incoming.through_sequence

                session.flush()
        except IntegrityError as exc:
            if _is_conversation_conflict(exc):
                raise DuplicateConversationError(
                    f"Conversation already exists for this pair: "
                    f"{conversation.id}"
                ) from exc
            raise ValueError(
                f"Could not update conversation: {conversation.id}"
            ) from exc

    def list_all(self) -> list[Conversation]:
        with self._database.operation() as session:
            rows = (
                session.execute(
                    _conversation_statement().order_by(
                        ConversationRow.updated_at,
                        ConversationRow.id,
                    )
                )
                .scalars()
                .all()
            )
            return [_conversation_from_row(row) for row in rows]

    def export_state(self) -> list[dict[str, Any]]:
        return [
            conversation.model_dump(mode="json")
            for conversation in self.list_all()
        ]

    def import_state(self, state: list[dict[str, Any]]) -> None:
        conversations = [
            Conversation.model_validate(item) for item in state
        ]
        try:
            with self._database.operation() as session:
                session.execute(
                    delete(ConversationRow).execution_options(
                        synchronize_session=False
                    )
                )
                session.add_all(
                    [_conversation_row(conversation) for conversation in conversations]
                )
                session.flush()
        except IntegrityError as exc:
            raise ValueError("Could not import conversations") from exc


__all__ = [
    "SqlConversationRepository",
    "SqlProfileRepository",
    "SqlRefreshTokenRepository",
    "SqlUserRepository",
]
