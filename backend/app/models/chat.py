"""Request, conversation, message, session, and call models.

A request and its chat share one aggregate because the product keeps exactly
one conversation per pair of people. The request status is the conversation
status; the initial note is also the first message. Messages and events carry
monotonic per-conversation sequences so clients can paginate history and resume
after a dropped WebSocket without missing updates.
"""

from __future__ import annotations

from datetime import datetime, timezone
from enum import Enum
from typing import Literal

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    field_validator,
    model_validator,
)

from .profile import PublicProfile

MAX_REQUEST_NOTE = 1000
MIN_REQUEST_NOTE = 12
MAX_RESPONSE_NOTE = 1000
MIN_DECLINE_REASON = 3
MAX_MESSAGE_TEXT = 2000
MAX_VOICE_SECONDS = 300
MAX_CALL_SECONDS = 3600


class RequestStatus(str, Enum):
    pending = "pending"
    accepted = "accepted"
    declined = "declined"


class RequestDirection(str, Enum):
    sent = "sent"
    received = "received"
    all = "all"


class MessageKind(str, Enum):
    text = "text"
    image = "image"
    voice = "voice"
    session = "session"
    call = "call"


class SessionState(str, Enum):
    proposed = "proposed"
    accepted = "accepted"
    declined = "declined"


class CallKind(str, Enum):
    voice = "voice"
    video = "video"


class ConversationEventType(str, Enum):
    request_created = "request_created"
    request_accepted = "request_accepted"
    request_declined = "request_declined"
    message_created = "message_created"
    session_updated = "session_updated"
    call_logged = "call_logged"
    conversation_read = "conversation_read"


def _aware_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value


class ChatMessage(BaseModel):
    """A stored message. Media bytes live behind the chat media storage."""

    model_config = ConfigDict(extra="forbid")

    id: str
    conversation_id: str
    sender_id: str
    kind: MessageKind
    text: str = Field(default="", max_length=MAX_MESSAGE_TEXT)
    sequence: int = Field(ge=1)
    created_at: datetime

    media_key: str | None = Field(default=None, max_length=200)
    media_content_type: str | None = Field(default=None, max_length=100)
    media_size: int | None = Field(default=None, ge=0)
    media_filename: str | None = Field(default=None, max_length=255)
    image_width: int | None = Field(default=None, ge=1)
    image_height: int | None = Field(default=None, ge=1)
    voice_seconds: int | None = Field(
        default=None,
        ge=1,
        le=MAX_VOICE_SECONDS,
    )

    session_at: datetime | None = None
    session_state: SessionState | None = None

    call_kind: CallKind | None = None
    call_connected: bool | None = None
    call_duration_seconds: int | None = Field(
        default=None,
        ge=0,
        le=MAX_CALL_SECONDS,
    )


class ConversationEvent(BaseModel):
    """One durable update inside a conversation.

    Events are the WebSocket payload and the polling fallback. A read receipt
    is an event without a message; a new message is an event carrying the
    stored message. The event sequence is independent of the message sequence.
    """

    model_config = ConfigDict(extra="forbid")

    sequence: int = Field(ge=1)
    conversation_id: str
    type: ConversationEventType
    actor_id: str
    created_at: datetime
    message: ChatMessage | None = None
    request_status: RequestStatus | None = None
    read_through_sequence: int | None = Field(default=None, ge=0)
    session_state: SessionState | None = None


class Conversation(BaseModel):
    """A request plus the messages that follow it."""

    model_config = ConfigDict(extra="forbid")

    id: str
    student_id: str
    tutor_id: str
    subject: str = Field(min_length=1, max_length=120)
    score: int = Field(ge=0, le=100)
    note: str = Field(default="", max_length=MAX_REQUEST_NOTE)
    status: RequestStatus = RequestStatus.pending
    requested_by: str
    created_at: datetime
    updated_at: datetime
    responded_at: datetime | None = None
    response_note: str | None = Field(
        default=None,
        max_length=MAX_RESPONSE_NOTE,
    )

    messages: list[ChatMessage] = Field(default_factory=list)
    events: list[ConversationEvent] = Field(default_factory=list)
    next_message_sequence: int = Field(default=1, ge=1)
    next_event_sequence: int = Field(default=1, ge=1)
    last_read_sequences: dict[str, int] = Field(default_factory=dict)

    @model_validator(mode="after")
    def _validate_participants(self) -> "Conversation":
        if self.student_id == self.tutor_id:
            raise ValueError("A conversation needs two different people.")
        if self.requested_by not in {self.student_id, self.tutor_id}:
            raise ValueError("The requester must be a participant.")
        return self

    @property
    def participant_ids(self) -> frozenset[str]:
        return frozenset({self.student_id, self.tutor_id})

    def other_id(self, user_id: str) -> str:
        if user_id == self.student_id:
            return self.tutor_id
        if user_id == self.tutor_id:
            return self.student_id
        raise ValueError("That user is not a participant.")


class CreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    counterpart_id: str = Field(min_length=1, max_length=80)
    subject: str = Field(min_length=1, max_length=120)
    note: str = Field(min_length=MIN_REQUEST_NOTE, max_length=MAX_REQUEST_NOTE)

    @field_validator("counterpart_id", "subject", "note")
    @classmethod
    def _trim(cls, value: str) -> str:
        return value.strip()

    @field_validator("note")
    @classmethod
    def _note_has_substance(cls, value: str) -> str:
        if len(value) < MIN_REQUEST_NOTE:
            raise ValueError(
                f"Add at least {MIN_REQUEST_NOTE} characters so the other "
                "person has something to answer."
            )
        return value


class AcceptRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    note: str | None = Field(default=None, max_length=MAX_RESPONSE_NOTE)

    @field_validator("note")
    @classmethod
    def _trim(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = value.strip()
        return cleaned or None


class DeclineRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    reason: str = Field(
        min_length=MIN_DECLINE_REASON,
        max_length=MAX_RESPONSE_NOTE,
    )

    @field_validator("reason")
    @classmethod
    def _trim(cls, value: str) -> str:
        cleaned = value.strip()
        if len(cleaned) < MIN_DECLINE_REASON:
            raise ValueError("Add a short reason for declining.")
        return cleaned


class SendTextRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    text: str = Field(min_length=1, max_length=MAX_MESSAGE_TEXT)

    @field_validator("text")
    @classmethod
    def _trim(cls, value: str) -> str:
        cleaned = value.strip()
        if not cleaned:
            raise ValueError("Write a message first.")
        return cleaned


class SimulatedVoiceRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    duration_seconds: int = Field(ge=1, le=MAX_VOICE_SECONDS)


class SessionProposalRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    proposed_for: datetime

    @field_validator("proposed_for")
    @classmethod
    def _timezone_required(cls, value: datetime) -> datetime:
        return _aware_utc(value)


class SessionResponseRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    state: Literal["accepted", "declined"]


class CallEventRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    kind: CallKind
    connected: bool
    duration_seconds: int = Field(default=0, ge=0, le=MAX_CALL_SECONDS)

    @model_validator(mode="after")
    def _duration_matches_outcome(self) -> "CallEventRequest":
        if not self.connected and self.duration_seconds != 0:
            raise ValueError("A missed call cannot have a duration.")
        return self


class MarkReadRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    through_sequence: int | None = Field(default=None, ge=0)


class RequestSummary(BaseModel):
    """A request as one side sees it."""

    model_config = ConfigDict(extra="forbid")

    id: str
    conversation_id: str
    counterpart: PublicProfile
    direction: RequestDirection
    subject: str
    score: int
    status: RequestStatus
    note: str
    response_note: str | None
    created_at: datetime
    updated_at: datetime
    responded_at: datetime | None


class MessagePreview(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    kind: MessageKind
    text: str
    sender_id: str
    from_me: bool
    sequence: int
    created_at: datetime


class ConversationSummary(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    counterpart: PublicProfile
    subject: str
    score: int
    status: RequestStatus
    requested_by_me: bool
    created_at: datetime
    updated_at: datetime
    last_message: MessagePreview | None
    unread_count: int
    last_event_sequence: int


class ConversationDetail(ConversationSummary):
    request_note: str
    response_note: str | None
    read_through_sequence: int
    latest_message_sequence: int


class MessageView(BaseModel):
    """A message projected for one participant."""

    model_config = ConfigDict(extra="forbid")

    id: str
    conversation_id: str
    sender_id: str
    from_me: bool
    kind: MessageKind
    text: str
    sequence: int
    created_at: datetime
    read_by_recipient: bool

    media_url: str | None
    media_content_type: str | None
    media_size: int | None
    image_width: int | None
    image_height: int | None
    voice_seconds: int | None

    session_at: datetime | None
    session_state: SessionState | None

    call_kind: CallKind | None
    call_connected: bool | None
    call_duration_seconds: int | None


class MessagePage(BaseModel):
    model_config = ConfigDict(extra="forbid")

    conversation_id: str
    messages: list[MessageView]
    limit: int
    has_more: bool
    next_before: int | None
    next_after: int | None
    latest_sequence: int
    read_through_sequence: int
    unread_count: int


class ReadState(BaseModel):
    model_config = ConfigDict(extra="forbid")

    conversation_id: str
    read_through_sequence: int
    latest_message_sequence: int
    unread_count: int


class ConversationEventView(BaseModel):
    model_config = ConfigDict(extra="forbid")

    sequence: int
    conversation_id: str
    type: ConversationEventType
    actor_id: str
    created_at: datetime
    message: MessageView | None
    request_status: RequestStatus | None
    read_through_sequence: int | None
    session_state: SessionState | None


class EventPage(BaseModel):
    model_config = ConfigDict(extra="forbid")

    conversation_id: str
    events: list[ConversationEventView]
    limit: int
    has_more: bool
    next_after: int | None
    last_event_sequence: int
