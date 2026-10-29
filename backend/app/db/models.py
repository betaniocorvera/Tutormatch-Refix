"""PostgreSQL table models for the TutorMatch data store.

The Pydantic models in ``app.models`` remain the transport and service-layer
contracts. These SQLAlchemy models only describe persistence. IDs stay strings
for compatibility with the existing API and JSON snapshot, while PostgreSQL
uses timezone-aware timestamps, arrays for the fixed profile grids, and
database constraints for the invariants the services rely on.
"""

from __future__ import annotations

from datetime import date, datetime

from sqlalchemy import (
    ARRAY,
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .base import Base

_ROLE_VALUES = "'student', 'tutor'"
_MODE_VALUES = "'online', 'in_person', 'both'"
_LOCATION_PRIVACY_VALUES = "'area', 'city_only', 'hidden'"
_PRESENCE_VALUES = "'available', 'busy', 'away'"
_REQUEST_STATUS_VALUES = "'pending', 'accepted', 'declined'"
_MESSAGE_KIND_VALUES = "'text', 'image', 'voice', 'session', 'call'"
_SESSION_STATE_VALUES = "'proposed', 'accepted', 'declined'"
_CALL_KIND_VALUES = "'voice', 'video'"
_EVENT_TYPE_VALUES = (
    "'request_created', 'request_accepted', 'request_declined', "
    "'message_created', 'session_updated', 'call_logged', "
    "'conversation_read'"
)


class UserRow(Base):
    __tablename__ = "users"
    __table_args__ = (
        CheckConstraint(f"role IN ({_ROLE_VALUES})", name="ck_users_role"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    email: Mapped[str] = mapped_column(
        String(320),
        nullable=False,
        unique=True,
        index=True,
    )
    password_hash: Mapped[str] = mapped_column(String(512), nullable=False)
    role: Mapped[str] = mapped_column(String(16), nullable=False)
    display_name: Mapped[str] = mapped_column(
        String(80),
        nullable=False,
        default="",
    )
    phone: Mapped[str] = mapped_column(String(20), nullable=False, default="")
    onboarding_complete: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=False,
    )
    privacy_consent: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=False,
    )
    privacy_consent_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    privacy_policy_version: Mapped[str] = mapped_column(
        String(40),
        nullable=False,
        default="",
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )

    security_answers: Mapped[list[SecurityAnswerRow]] = relationship(
        back_populates="user",
        cascade="all, delete-orphan",
        order_by="SecurityAnswerRow.question_id",
    )


class SecurityAnswerRow(Base):
    __tablename__ = "security_answers"

    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        primary_key=True,
    )
    question_id: Mapped[str] = mapped_column(String(80), primary_key=True)
    answer_hash: Mapped[str] = mapped_column(String(512), nullable=False)

    user: Mapped[UserRow] = relationship(back_populates="security_answers")


class ProfileRow(Base):
    __tablename__ = "profiles"
    __table_args__ = (
        CheckConstraint(
            "budget >= 0 AND budget <= 80",
            name="ck_profiles_budget",
        ),
        CheckConstraint(
            "years IS NULL OR (years >= 0 AND years <= 80)",
            name="ck_profiles_years",
        ),
        CheckConstraint(
            f"mode IN ({_MODE_VALUES})",
            name="ck_profiles_mode",
        ),
        CheckConstraint(
            f"location_privacy IN ({_LOCATION_PRIVACY_VALUES})",
            name="ck_profiles_location_privacy",
        ),
        CheckConstraint(
            f"presence IN ({_PRESENCE_VALUES})",
            name="ck_profiles_presence",
        ),
        CheckConstraint(
            "coalesce(array_length(availability, 1), 0) = 21",
            name="ck_profiles_availability_21",
        ),
        CheckConstraint(
            "coalesce(array_length(subjects, 1), 0) <= 4",
            name="ck_profiles_subjects_max",
        ),
        CheckConstraint(
            "coalesce(array_length(languages, 1), 0) <= 15",
            name="ck_profiles_languages_max",
        ),
    )

    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        primary_key=True,
    )
    name: Mapped[str] = mapped_column(String(80), nullable=False, default="")
    subjects: Mapped[list[str]] = mapped_column(
        ARRAY(String(120)),
        nullable=False,
        default=list,
    )
    style: Mapped[str] = mapped_column(String(200), nullable=False, default="")
    mode: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        default="both",
    )
    budget: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    availability: Mapped[list[bool]] = mapped_column(
        ARRAY(Boolean),
        nullable=False,
        default=lambda: [False] * 21,
    )
    goal: Mapped[str] = mapped_column(String(300), nullable=False, default="")
    birthdate: Mapped[date | None] = mapped_column(Date, nullable=True)
    area_id: Mapped[str] = mapped_column(
        String(120),
        nullable=False,
        default="",
    )
    location_privacy: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        default="city_only",
    )
    status_text: Mapped[str] = mapped_column(
        String(160),
        nullable=False,
        default="",
    )
    presence: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        default="available",
    )
    bio: Mapped[str] = mapped_column(String(1000), nullable=False, default="")
    gender: Mapped[str] = mapped_column(
        String(40),
        nullable=False,
        default="Prefer not to say",
    )
    languages: Mapped[list[str]] = mapped_column(
        ARRAY(String(40)),
        nullable=False,
        default=list,
    )
    years: Mapped[int | None] = mapped_column(Integer, nullable=True)
    education: Mapped[str] = mapped_column(
        String(200),
        nullable=False,
        default="",
    )
    grade: Mapped[str] = mapped_column(String(80), nullable=False, default="")
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )

    user: Mapped[UserRow] = relationship()


class RefreshTokenRow(Base):
    __tablename__ = "refresh_tokens"
    __table_args__ = (
        Index("ix_refresh_tokens_user_id", "user_id"),
    )

    jti: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    revoked_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    replaced_by_jti: Mapped[str | None] = mapped_column(
        String(64),
        nullable=True,
    )

    user: Mapped[UserRow] = relationship()


class ConversationRow(Base):
    __tablename__ = "conversations"
    __table_args__ = (
        UniqueConstraint(
            "student_id",
            "tutor_id",
            name="uq_conversations_student_tutor",
        ),
        CheckConstraint(
            "student_id <> tutor_id",
            name="ck_conversations_distinct_participants",
        ),
        CheckConstraint(
            "requested_by = student_id OR requested_by = tutor_id",
            name="ck_conversations_requester_is_participant",
        ),
        CheckConstraint(
            "score >= 0 AND score <= 100",
            name="ck_conversations_score",
        ),
        CheckConstraint(
            f"status IN ({_REQUEST_STATUS_VALUES})",
            name="ck_conversations_status",
        ),
        CheckConstraint(
            "next_message_sequence >= 1",
            name="ck_conversations_next_message_sequence",
        ),
        CheckConstraint(
            "next_event_sequence >= 1",
            name="ck_conversations_next_event_sequence",
        ),
        Index("ix_conversations_student_id", "student_id"),
        Index("ix_conversations_tutor_id", "tutor_id"),
        Index("ix_conversations_updated_at", "updated_at"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    student_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    tutor_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    subject: Mapped[str] = mapped_column(String(120), nullable=False)
    score: Mapped[int] = mapped_column(Integer, nullable=False)
    note: Mapped[str] = mapped_column(String(1000), nullable=False, default="")
    status: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        default="pending",
    )
    requested_by: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )
    responded_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    response_note: Mapped[str | None] = mapped_column(
        String(1000),
        nullable=True,
    )
    next_message_sequence: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=1,
    )
    next_event_sequence: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=1,
    )

    student: Mapped[UserRow] = relationship(
        foreign_keys="ConversationRow.student_id",
    )
    tutor: Mapped[UserRow] = relationship(
        foreign_keys="ConversationRow.tutor_id",
    )
    messages: Mapped[list[MessageRow]] = relationship(
        back_populates="conversation",
        cascade="all, delete-orphan",
        order_by="MessageRow.sequence",
    )
    events: Mapped[list[ConversationEventRow]] = relationship(
        back_populates="conversation",
        cascade="all, delete-orphan",
        order_by="ConversationEventRow.sequence",
    )
    reads: Mapped[list[ConversationReadRow]] = relationship(
        back_populates="conversation",
        cascade="all, delete-orphan",
    )


class MessageRow(Base):
    __tablename__ = "messages"
    __table_args__ = (
        UniqueConstraint(
            "conversation_id",
            "sequence",
            name="uq_messages_conversation_sequence",
        ),
        CheckConstraint(
            f"kind IN ({_MESSAGE_KIND_VALUES})",
            name="ck_messages_kind",
        ),
        CheckConstraint("sequence >= 1", name="ck_messages_sequence"),
        CheckConstraint(
            "media_size IS NULL OR media_size >= 0",
            name="ck_messages_media_size",
        ),
        CheckConstraint(
            "image_width IS NULL OR image_width >= 1",
            name="ck_messages_image_width",
        ),
        CheckConstraint(
            "image_height IS NULL OR image_height >= 1",
            name="ck_messages_image_height",
        ),
        CheckConstraint(
            "voice_seconds IS NULL OR (voice_seconds >= 1 AND voice_seconds <= 300)",
            name="ck_messages_voice_seconds",
        ),
        CheckConstraint(
            "call_duration_seconds IS NULL OR "
            "(call_duration_seconds >= 0 AND call_duration_seconds <= 3600)",
            name="ck_messages_call_duration",
        ),
        CheckConstraint(
            f"session_state IS NULL OR session_state IN ({_SESSION_STATE_VALUES})",
            name="ck_messages_session_state",
        ),
        CheckConstraint(
            f"call_kind IS NULL OR call_kind IN ({_CALL_KIND_VALUES})",
            name="ck_messages_call_kind",
        ),
        Index(
            "ix_messages_conversation_created_at",
            "conversation_id",
            "created_at",
        ),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    conversation_id: Mapped[str] = mapped_column(
        ForeignKey("conversations.id", ondelete="CASCADE"),
        nullable=False,
    )
    sender_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    kind: Mapped[str] = mapped_column(String(16), nullable=False)
    text: Mapped[str] = mapped_column(String(2000), nullable=False, default="")
    sequence: Mapped[int] = mapped_column(Integer, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

    media_key: Mapped[str | None] = mapped_column(String(200), nullable=True)
    media_content_type: Mapped[str | None] = mapped_column(
        String(100),
        nullable=True,
    )
    media_size: Mapped[int | None] = mapped_column(Integer, nullable=True)
    media_filename: Mapped[str | None] = mapped_column(
        String(255),
        nullable=True,
    )
    image_width: Mapped[int | None] = mapped_column(Integer, nullable=True)
    image_height: Mapped[int | None] = mapped_column(Integer, nullable=True)
    voice_seconds: Mapped[int | None] = mapped_column(Integer, nullable=True)

    session_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    session_state: Mapped[str | None] = mapped_column(
        String(16),
        nullable=True,
    )

    call_kind: Mapped[str | None] = mapped_column(String(16), nullable=True)
    call_connected: Mapped[bool | None] = mapped_column(
        Boolean,
        nullable=True,
    )
    call_duration_seconds: Mapped[int | None] = mapped_column(
        Integer,
        nullable=True,
    )

    conversation: Mapped[ConversationRow] = relationship(
        back_populates="messages",
    )
    sender: Mapped[UserRow] = relationship()


class ConversationEventRow(Base):
    __tablename__ = "conversation_events"
    __table_args__ = (
        CheckConstraint("sequence >= 1", name="ck_events_sequence"),
        CheckConstraint(
            f"type IN ({_EVENT_TYPE_VALUES})",
            name="ck_events_type",
        ),
        CheckConstraint(
            f"request_status IS NULL OR request_status IN ({_REQUEST_STATUS_VALUES})",
            name="ck_events_request_status",
        ),
        CheckConstraint(
            "read_through_sequence IS NULL OR read_through_sequence >= 0",
            name="ck_events_read_through_sequence",
        ),
        CheckConstraint(
            f"session_state IS NULL OR session_state IN ({_SESSION_STATE_VALUES})",
            name="ck_events_session_state",
        ),
        Index(
            "ix_events_conversation_created_at",
            "conversation_id",
            "created_at",
        ),
    )

    conversation_id: Mapped[str] = mapped_column(
        ForeignKey("conversations.id", ondelete="CASCADE"),
        primary_key=True,
    )
    sequence: Mapped[int] = mapped_column(Integer, primary_key=True)
    type: Mapped[str] = mapped_column(String(32), nullable=False)
    actor_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    message_id: Mapped[str | None] = mapped_column(
        ForeignKey("messages.id", ondelete="SET NULL"),
        nullable=True,
    )
    request_status: Mapped[str | None] = mapped_column(
        String(16),
        nullable=True,
    )
    read_through_sequence: Mapped[int | None] = mapped_column(
        Integer,
        nullable=True,
    )
    session_state: Mapped[str | None] = mapped_column(
        String(16),
        nullable=True,
    )

    conversation: Mapped[ConversationRow] = relationship(
        back_populates="events",
    )
    actor: Mapped[UserRow] = relationship()
    message: Mapped[MessageRow | None] = relationship()


class ConversationReadRow(Base):
    __tablename__ = "conversation_reads"
    __table_args__ = (
        CheckConstraint(
            "through_sequence >= 0",
            name="ck_conversation_reads_sequence",
        ),
    )

    conversation_id: Mapped[str] = mapped_column(
        ForeignKey("conversations.id", ondelete="CASCADE"),
        primary_key=True,
    )
    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        primary_key=True,
    )
    through_sequence: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=0,
    )

    conversation: Mapped[ConversationRow] = relationship(
        back_populates="reads",
    )
    user: Mapped[UserRow] = relationship()


__all__ = [
    "ConversationEventRow",
    "ConversationReadRow",
    "ConversationRow",
    "MessageRow",
    "ProfileRow",
    "RefreshTokenRow",
    "SecurityAnswerRow",
    "UserRow",
]
