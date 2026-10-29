"""initial schema

Revision ID: edf78218dfd6
Revises:
Create Date: 2026-10-29 12:38:22.950193

This is the complete PostgreSQL foundation for the existing Pydantic models.
It creates the tables, constraints, and indexes used by the SQL repositories.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "edf78218dfd6"
down_revision: Union[str, Sequence[str], None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Create the initial TutorMatch schema."""

    op.create_table(
        "users",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("email", sa.String(length=320), nullable=False),
        sa.Column("password_hash", sa.String(length=512), nullable=False),
        sa.Column("role", sa.String(length=16), nullable=False),
        sa.Column("display_name", sa.String(length=80), nullable=False),
        sa.Column("phone", sa.String(length=20), nullable=False),
        sa.Column("onboarding_complete", sa.Boolean(), nullable=False),
        sa.Column("privacy_consent", sa.Boolean(), nullable=False),
        sa.Column(
            "privacy_consent_at",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
        sa.Column(
            "privacy_policy_version",
            sa.String(length=40),
            nullable=False,
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.CheckConstraint(
            "role IN ('student', 'tutor')",
            name="ck_users_role",
        ),
        sa.PrimaryKeyConstraint("id"),
    )

    op.create_table(
        "conversations",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("student_id", sa.String(length=36), nullable=False),
        sa.Column("tutor_id", sa.String(length=36), nullable=False),
        sa.Column("subject", sa.String(length=120), nullable=False),
        sa.Column("score", sa.Integer(), nullable=False),
        sa.Column("note", sa.String(length=1000), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("requested_by", sa.String(length=36), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "responded_at",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
        sa.Column("response_note", sa.String(length=1000), nullable=True),
        sa.Column(
            "next_message_sequence",
            sa.Integer(),
            nullable=False,
        ),
        sa.Column(
            "next_event_sequence",
            sa.Integer(),
            nullable=False,
        ),
        sa.CheckConstraint(
            "student_id <> tutor_id",
            name="ck_conversations_distinct_participants",
        ),
        sa.CheckConstraint(
            "requested_by = student_id OR requested_by = tutor_id",
            name="ck_conversations_requester_is_participant",
        ),
        sa.CheckConstraint(
            "score >= 0 AND score <= 100",
            name="ck_conversations_score",
        ),
        sa.CheckConstraint(
            "status IN ('pending', 'accepted', 'declined')",
            name="ck_conversations_status",
        ),
        sa.CheckConstraint(
            "next_message_sequence >= 1",
            name="ck_conversations_next_message_sequence",
        ),
        sa.CheckConstraint(
            "next_event_sequence >= 1",
            name="ck_conversations_next_event_sequence",
        ),
        sa.ForeignKeyConstraint(
            ["student_id"],
            ["users.id"],
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["tutor_id"],
            ["users.id"],
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["requested_by"],
            ["users.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "student_id",
            "tutor_id",
            name="uq_conversations_student_tutor",
        ),
    )

    op.create_table(
        "profiles",
        sa.Column("user_id", sa.String(length=36), nullable=False),
        sa.Column("name", sa.String(length=80), nullable=False),
        sa.Column(
            "subjects",
            postgresql.ARRAY(sa.String(length=120)),
            nullable=False,
        ),
        sa.Column("style", sa.String(length=200), nullable=False),
        sa.Column("mode", sa.String(length=16), nullable=False),
        sa.Column("budget", sa.Integer(), nullable=False),
        sa.Column(
            "availability",
            postgresql.ARRAY(sa.Boolean()),
            nullable=False,
        ),
        sa.Column("goal", sa.String(length=300), nullable=False),
        sa.Column("birthdate", sa.Date(), nullable=True),
        sa.Column("area_id", sa.String(length=120), nullable=False),
        sa.Column(
            "location_privacy",
            sa.String(length=16),
            nullable=False,
        ),
        sa.Column("status_text", sa.String(length=160), nullable=False),
        sa.Column("presence", sa.String(length=16), nullable=False),
        sa.Column("bio", sa.String(length=1000), nullable=False),
        sa.Column("gender", sa.String(length=40), nullable=False),
        sa.Column(
            "languages",
            postgresql.ARRAY(sa.String(length=40)),
            nullable=False,
        ),
        sa.Column("years", sa.Integer(), nullable=True),
        sa.Column("education", sa.String(length=200), nullable=False),
        sa.Column("grade", sa.String(length=80), nullable=False),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.CheckConstraint(
            "budget >= 0 AND budget <= 80",
            name="ck_profiles_budget",
        ),
        sa.CheckConstraint(
            "years IS NULL OR (years >= 0 AND years <= 80)",
            name="ck_profiles_years",
        ),
        sa.CheckConstraint(
            "mode IN ('online', 'in_person', 'both')",
            name="ck_profiles_mode",
        ),
        sa.CheckConstraint(
            "location_privacy IN ('area', 'city_only', 'hidden')",
            name="ck_profiles_location_privacy",
        ),
        sa.CheckConstraint(
            "presence IN ('available', 'busy', 'away')",
            name="ck_profiles_presence",
        ),
        sa.CheckConstraint(
            "coalesce(array_length(availability, 1), 0) = 21",
            name="ck_profiles_availability_21",
        ),
        sa.CheckConstraint(
            "coalesce(array_length(subjects, 1), 0) <= 4",
            name="ck_profiles_subjects_max",
        ),
        sa.CheckConstraint(
            "coalesce(array_length(languages, 1), 0) <= 15",
            name="ck_profiles_languages_max",
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("user_id"),
    )

    op.create_table(
        "refresh_tokens",
        sa.Column("jti", sa.String(length=64), nullable=False),
        sa.Column("user_id", sa.String(length=36), nullable=False),
        sa.Column(
            "expires_at",
            sa.DateTime(timezone=True),
            nullable=False,
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "revoked_at",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
        sa.Column("replaced_by_jti", sa.String(length=64), nullable=True),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("jti"),
    )

    op.create_table(
        "security_answers",
        sa.Column("user_id", sa.String(length=36), nullable=False),
        sa.Column("question_id", sa.String(length=80), nullable=False),
        sa.Column("answer_hash", sa.String(length=512), nullable=False),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("user_id", "question_id"),
    )

    op.create_table(
        "conversation_reads",
        sa.Column("conversation_id", sa.String(length=36), nullable=False),
        sa.Column("user_id", sa.String(length=36), nullable=False),
        sa.Column("through_sequence", sa.Integer(), nullable=False),
        sa.CheckConstraint(
            "through_sequence >= 0",
            name="ck_conversation_reads_sequence",
        ),
        sa.ForeignKeyConstraint(
            ["conversation_id"],
            ["conversations.id"],
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("conversation_id", "user_id"),
    )

    op.create_table(
        "messages",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("conversation_id", sa.String(length=36), nullable=False),
        sa.Column("sender_id", sa.String(length=36), nullable=False),
        sa.Column("kind", sa.String(length=16), nullable=False),
        sa.Column("text", sa.String(length=2000), nullable=False),
        sa.Column("sequence", sa.Integer(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("media_key", sa.String(length=200), nullable=True),
        sa.Column(
            "media_content_type",
            sa.String(length=100),
            nullable=True,
        ),
        sa.Column("media_size", sa.Integer(), nullable=True),
        sa.Column("media_filename", sa.String(length=255), nullable=True),
        sa.Column("image_width", sa.Integer(), nullable=True),
        sa.Column("image_height", sa.Integer(), nullable=True),
        sa.Column("voice_seconds", sa.Integer(), nullable=True),
        sa.Column(
            "session_at",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
        sa.Column("session_state", sa.String(length=16), nullable=True),
        sa.Column("call_kind", sa.String(length=16), nullable=True),
        sa.Column("call_connected", sa.Boolean(), nullable=True),
        sa.Column(
            "call_duration_seconds",
            sa.Integer(),
            nullable=True,
        ),
        sa.CheckConstraint(
            "kind IN ('text', 'image', 'voice', 'session', 'call')",
            name="ck_messages_kind",
        ),
        sa.CheckConstraint(
            "sequence >= 1",
            name="ck_messages_sequence",
        ),
        sa.CheckConstraint(
            "media_size IS NULL OR media_size >= 0",
            name="ck_messages_media_size",
        ),
        sa.CheckConstraint(
            "image_width IS NULL OR image_width >= 1",
            name="ck_messages_image_width",
        ),
        sa.CheckConstraint(
            "image_height IS NULL OR image_height >= 1",
            name="ck_messages_image_height",
        ),
        sa.CheckConstraint(
            "voice_seconds IS NULL OR "
            "(voice_seconds >= 1 AND voice_seconds <= 300)",
            name="ck_messages_voice_seconds",
        ),
        sa.CheckConstraint(
            "call_duration_seconds IS NULL OR "
            "(call_duration_seconds >= 0 AND call_duration_seconds <= 3600)",
            name="ck_messages_call_duration",
        ),
        sa.CheckConstraint(
            "session_state IS NULL OR "
            "session_state IN ('proposed', 'accepted', 'declined')",
            name="ck_messages_session_state",
        ),
        sa.CheckConstraint(
            "call_kind IS NULL OR call_kind IN ('voice', 'video')",
            name="ck_messages_call_kind",
        ),
        sa.ForeignKeyConstraint(
            ["conversation_id"],
            ["conversations.id"],
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["sender_id"],
            ["users.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "conversation_id",
            "sequence",
            name="uq_messages_conversation_sequence",
        ),
    )

    op.create_table(
        "conversation_events",
        sa.Column("conversation_id", sa.String(length=36), nullable=False),
        sa.Column("sequence", sa.Integer(), nullable=False),
        sa.Column("type", sa.String(length=32), nullable=False),
        sa.Column("actor_id", sa.String(length=36), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("message_id", sa.String(length=36), nullable=True),
        sa.Column("request_status", sa.String(length=16), nullable=True),
        sa.Column("read_through_sequence", sa.Integer(), nullable=True),
        sa.Column("session_state", sa.String(length=16), nullable=True),
        sa.CheckConstraint(
            "sequence >= 1",
            name="ck_events_sequence",
        ),
        sa.CheckConstraint(
            "type IN ("
            "'request_created', 'request_accepted', 'request_declined', "
            "'message_created', 'session_updated', 'call_logged', "
            "'conversation_read'"
            ")",
            name="ck_events_type",
        ),
        sa.CheckConstraint(
            "request_status IS NULL OR "
            "request_status IN ('pending', 'accepted', 'declined')",
            name="ck_events_request_status",
        ),
        sa.CheckConstraint(
            "read_through_sequence IS NULL OR read_through_sequence >= 0",
            name="ck_events_read_through_sequence",
        ),
        sa.CheckConstraint(
            "session_state IS NULL OR "
            "session_state IN ('proposed', 'accepted', 'declined')",
            name="ck_events_session_state",
        ),
        sa.ForeignKeyConstraint(
            ["conversation_id"],
            ["conversations.id"],
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["actor_id"],
            ["users.id"],
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["message_id"],
            ["messages.id"],
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("conversation_id", "sequence"),
    )

    op.create_index(
        "ix_users_email",
        "users",
        ["email"],
        unique=True,
    )
    op.create_index(
        "ix_conversations_student_id",
        "conversations",
        ["student_id"],
        unique=False,
    )
    op.create_index(
        "ix_conversations_tutor_id",
        "conversations",
        ["tutor_id"],
        unique=False,
    )
    op.create_index(
        "ix_conversations_updated_at",
        "conversations",
        ["updated_at"],
        unique=False,
    )
    op.create_index(
        "ix_refresh_tokens_user_id",
        "refresh_tokens",
        ["user_id"],
        unique=False,
    )
    op.create_index(
        "ix_messages_conversation_created_at",
        "messages",
        ["conversation_id", "created_at"],
        unique=False,
    )
    op.create_index(
        "ix_events_conversation_created_at",
        "conversation_events",
        ["conversation_id", "created_at"],
        unique=False,
    )


def downgrade() -> None:
    """Drop the initial TutorMatch schema."""

    op.drop_index(
        "ix_events_conversation_created_at",
        table_name="conversation_events",
    )
    op.drop_index(
        "ix_messages_conversation_created_at",
        table_name="messages",
    )
    op.drop_index(
        "ix_refresh_tokens_user_id",
        table_name="refresh_tokens",
    )
    op.drop_index(
        "ix_conversations_updated_at",
        table_name="conversations",
    )
    op.drop_index(
        "ix_conversations_tutor_id",
        table_name="conversations",
    )
    op.drop_index(
        "ix_conversations_student_id",
        table_name="conversations",
    )
    op.drop_index("ix_users_email", table_name="users")

    op.drop_table("conversation_events")
    op.drop_table("messages")
    op.drop_table("conversation_reads")
    op.drop_table("security_answers")
    op.drop_table("refresh_tokens")
    op.drop_table("profiles")
    op.drop_table("conversations")
    op.drop_table("users")
