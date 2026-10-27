"""Requests and accepted-only conversations.

The service owns every access-control decision. Repositories are deliberately
dumb stores; routers only translate HTTP. A non-participant sees a not-found
response rather than learning that a conversation exists.
"""

from __future__ import annotations

import threading
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from uuid import uuid4

from ..catalog import Catalog
from ..errors import (
    ConversationLocked,
    ConversationNotFound,
    Forbidden,
    InvalidMessage,
    InvalidPagination,
    InvalidRequest,
    MediaNotFound,
    MessageNotFound,
    RequestAlreadyAnswered,
    RequestAlreadyExists,
    RequestNotFound,
    UserNotFound,
)
from ..models.chat import (
    AcceptRequest,
    CallEventRequest,
    CallKind,
    ChatMessage,
    Conversation,
    ConversationDetail,
    ConversationEvent,
    ConversationEventType,
    ConversationEventView,
    ConversationSummary,
    CreateRequest,
    DeclineRequest,
    EventPage,
    MarkReadRequest,
    MessageKind,
    MessagePage,
    MessagePreview,
    MessageView,
    ReadState,
    RequestDirection,
    RequestStatus,
    RequestSummary,
    SendTextRequest,
    SessionProposalRequest,
    SessionResponseRequest,
    SessionState,
    SimulatedVoiceRequest,
)
from ..models.profile import Profile
from ..models.user import Role, User
from ..repositories.interfaces import ConversationRepository, UserRepository
from ..storage.chat_media import ChatMediaStorage
from .broadcast import ConversationBroadcaster
from .chat_media import (
    PreparedImage,
    PreparedVoice,
    format_call_text,
    format_session_text,
    format_voice_text,
    prepare_image,
    prepare_voice,
)
from .matching import MatchingService
from .profile import ProfileService


@dataclass(frozen=True, slots=True)
class ChatMediaFile:
    data: bytes
    content_type: str
    filename: str


class ChatService:
    def __init__(
        self,
        *,
        users: UserRepository,
        conversations: ConversationRepository,
        profile_service: ProfileService,
        matching: MatchingService,
        catalog: Catalog,
        media: ChatMediaStorage,
        broadcaster: ConversationBroadcaster | None = None,
    ) -> None:
        self._users = users
        self._conversations = conversations
        self._profiles = profile_service
        self._matching = matching
        self._catalog = catalog
        self._media = media
        self._broadcaster = broadcaster
        self._lock = threading.RLock()

    # ── Requests ──────────────────────────────────────────────────────────

    def create_request(
        self,
        user: User,
        payload: CreateRequest,
    ) -> RequestSummary:
        with self._lock:
            counterpart = self._users.get_by_id(payload.counterpart_id)
            if counterpart is None:
                raise UserNotFound()
            if counterpart.id == user.id:
                raise InvalidRequest(
                    "You cannot send a request to yourself."
                )
            if counterpart.role == user.role:
                raise InvalidRequest(
                    "Requests go to a student or tutor on the other side."
                )

            viewer_profile = self._profiles.get_stored(user)
            counterpart_profile = self._profiles.get_stored(counterpart)
            subject = self._catalog.canonical_subject(payload.subject)
            if subject is None:
                raise InvalidRequest(
                    "Choose a subject from the subject catalogue."
                )
            if not _has_subject(viewer_profile, subject) or not _has_subject(
                counterpart_profile,
                subject,
            ):
                raise InvalidRequest(
                    "That subject is not shared by both people."
                )

            score = self._matching.pair_score(user, counterpart)
            if score is None:
                raise InvalidRequest(
                    "Both people need to finish their matching answers "
                    "before a request can be sent."
                )

            now = _now()
            existing = self._conversations.get_between(
                user.id,
                counterpart.id,
            )
            if existing is not None:
                if existing.status in {
                    RequestStatus.pending,
                    RequestStatus.accepted,
                }:
                    raise RequestAlreadyExists()

                # A declined request can be asked again. Keeping the same
                # aggregate preserves one conversation per pair and leaves the
                # old thread readable.
                existing.status = RequestStatus.pending
                existing.requested_by = user.id
                existing.subject = subject
                existing.score = score
                existing.note = payload.note
                existing.response_note = None
                existing.responded_at = None
                existing.last_read_sequences.setdefault(user.id, 0)
                existing.last_read_sequences.setdefault(counterpart.id, 0)
                message = self._append_message(
                    existing,
                    sender_id=user.id,
                    kind=MessageKind.text,
                    text=payload.note,
                    created_at=now,
                )
                event = self._append_event(
                    existing,
                    type=ConversationEventType.request_created,
                    actor_id=user.id,
                    created_at=now,
                    message=message,
                    request_status=RequestStatus.pending,
                )
                self._conversations.update(existing)
                self._publish(event)
                return self._request_summary(existing, user)

            student_id = (
                user.id if user.role is Role.student else counterpart.id
            )
            tutor_id = (
                counterpart.id if user.role is Role.student else user.id
            )
            conversation = Conversation(
                id=str(uuid4()),
                student_id=student_id,
                tutor_id=tutor_id,
                subject=subject,
                score=score,
                note=payload.note,
                status=RequestStatus.pending,
                requested_by=user.id,
                created_at=now,
                updated_at=now,
                last_read_sequences={user.id: 0, counterpart.id: 0},
            )
            message = self._append_message(
                conversation,
                sender_id=user.id,
                kind=MessageKind.text,
                text=payload.note,
                created_at=now,
            )
            event = self._append_event(
                conversation,
                type=ConversationEventType.request_created,
                actor_id=user.id,
                created_at=now,
                message=message,
                request_status=RequestStatus.pending,
            )
            self._conversations.add(conversation)
            self._publish(event)
            return self._request_summary(conversation, user)

    def list_requests(
        self,
        user: User,
        *,
        direction: RequestDirection = RequestDirection.all,
        status: RequestStatus | None = None,
    ) -> list[RequestSummary]:
        with self._lock:
            conversations = [
                conversation
                for conversation in self._conversations.list_all()
                if user.id in conversation.participant_ids
            ]
            if direction is RequestDirection.sent:
                conversations = [
                    conversation
                    for conversation in conversations
                    if conversation.requested_by == user.id
                ]
            elif direction is RequestDirection.received:
                conversations = [
                    conversation
                    for conversation in conversations
                    if conversation.requested_by != user.id
                ]
            if status is not None:
                conversations = [
                    conversation
                    for conversation in conversations
                    if conversation.status is status
                ]
            conversations.sort(
                key=lambda conversation: (
                    conversation.updated_at,
                    conversation.id,
                ),
                reverse=True,
            )
            return [
                self._request_summary(conversation, user)
                for conversation in conversations
            ]

    def get_request(self, user: User, request_id: str) -> RequestSummary:
        with self._lock:
            conversation = self._get_conversation(
                user,
                request_id,
                request=True,
            )
            return self._request_summary(conversation, user)

    def accept_request(
        self,
        user: User,
        request_id: str,
        payload: AcceptRequest | None = None,
    ) -> RequestSummary:
        with self._lock:
            conversation = self._get_conversation(
                user,
                request_id,
                request=True,
            )
            self._require_pending(conversation)
            self._require_receiver(conversation, user)

            now = _now()
            note = payload.note if payload else None
            response_message: ChatMessage | None = None
            if note:
                response_message = self._append_message(
                    conversation,
                    sender_id=user.id,
                    kind=MessageKind.text,
                    text=note,
                    created_at=now,
                )
            conversation.status = RequestStatus.accepted
            conversation.responded_at = now
            conversation.response_note = note
            conversation.updated_at = now
            conversation.last_read_sequences[user.id] = max(
                conversation.last_read_sequences.get(user.id, 0),
                conversation.next_message_sequence - 1,
            )
            event = self._append_event(
                conversation,
                type=ConversationEventType.request_accepted,
                actor_id=user.id,
                created_at=now,
                message=response_message,
                request_status=RequestStatus.accepted,
            )
            self._conversations.update(conversation)
            self._publish(event)
            return self._request_summary(conversation, user)

    def decline_request(
        self,
        user: User,
        request_id: str,
        payload: DeclineRequest,
    ) -> RequestSummary:
        with self._lock:
            conversation = self._get_conversation(
                user,
                request_id,
                request=True,
            )
            self._require_pending(conversation)
            self._require_receiver(conversation, user)

            now = _now()
            response_message = self._append_message(
                conversation,
                sender_id=user.id,
                kind=MessageKind.text,
                text=payload.reason,
                created_at=now,
            )
            conversation.status = RequestStatus.declined
            conversation.responded_at = now
            conversation.response_note = payload.reason
            conversation.updated_at = now
            conversation.last_read_sequences[user.id] = max(
                conversation.last_read_sequences.get(user.id, 0),
                conversation.next_message_sequence - 1,
            )
            event = self._append_event(
                conversation,
                type=ConversationEventType.request_declined,
                actor_id=user.id,
                created_at=now,
                message=response_message,
                request_status=RequestStatus.declined,
            )
            self._conversations.update(conversation)
            self._publish(event)
            return self._request_summary(conversation, user)

    # ── Conversations and messages ────────────────────────────────────────

    def list_conversations(
        self,
        user: User,
        *,
        status: RequestStatus | None = None,
    ) -> list[ConversationSummary]:
        with self._lock:
            conversations = [
                conversation
                for conversation in self._conversations.list_all()
                if user.id in conversation.participant_ids
            ]
            if status is not None:
                conversations = [
                    conversation
                    for conversation in conversations
                    if conversation.status is status
                ]
            conversations.sort(
                key=lambda conversation: (
                    conversation.updated_at,
                    conversation.id,
                ),
                reverse=True,
            )
            return [
                self._conversation_summary(conversation, user)
                for conversation in conversations
            ]

    def get_conversation(
        self,
        user: User,
        conversation_id: str,
    ) -> ConversationDetail:
        with self._lock:
            conversation = self._get_conversation(user, conversation_id)
            return self._conversation_detail(conversation, user)

    def list_messages(
        self,
        user: User,
        conversation_id: str,
        *,
        limit: int = 30,
        before: int | None = None,
        after: int | None = None,
    ) -> MessagePage:
        if not 1 <= limit <= 100:
            raise InvalidPagination("limit must be between 1 and 100.")
        if before is not None and after is not None:
            raise InvalidPagination(
                "Use either before or after, not both."
            )
        if before is not None and before < 0:
            raise InvalidPagination("before cannot be negative.")
        if after is not None and after < 0:
            raise InvalidPagination("after cannot be negative.")

        with self._lock:
            conversation = self._get_conversation(user, conversation_id)
            messages = conversation.messages
            selected: list[ChatMessage]
            has_more = False
            next_before: int | None = None
            next_after: int | None = None

            if after is not None:
                newer = [
                    message
                    for message in messages
                    if message.sequence > after
                ]
                selected = newer[:limit]
                has_more = len(newer) > len(selected)
                if selected and has_more:
                    next_after = selected[-1].sequence
            elif before is not None:
                older = [
                    message
                    for message in messages
                    if message.sequence < before
                ]
                selected = older[-limit:]
                has_more = len(older) > len(selected)
                if selected and has_more:
                    next_before = selected[0].sequence
            else:
                selected = messages[-limit:]
                has_more = len(messages) > len(selected)
                if selected and has_more:
                    next_before = selected[0].sequence

            return MessagePage(
                conversation_id=conversation.id,
                messages=[
                    self._message_view(conversation, message, user)
                    for message in selected
                ],
                limit=limit,
                has_more=has_more,
                next_before=next_before,
                next_after=next_after,
                latest_sequence=conversation.next_message_sequence - 1,
                read_through_sequence=self._read_through(
                    conversation,
                    user.id,
                ),
                unread_count=self._unread_count(conversation, user.id),
            )

    def send_text(
        self,
        user: User,
        conversation_id: str,
        payload: SendTextRequest,
    ) -> MessageView:
        with self._lock:
            conversation = self._get_accepted(user, conversation_id)
            message = self._append_message(
                conversation,
                sender_id=user.id,
                kind=MessageKind.text,
                text=payload.text,
            )
            event = self._append_event(
                conversation,
                type=ConversationEventType.message_created,
                actor_id=user.id,
                message=message,
            )
            self._conversations.update(conversation)
            self._publish(event)
            return self._message_view(conversation, message, user)

    def send_image(
        self,
        user: User,
        conversation_id: str,
        data: bytes,
    ) -> MessageView:
        prepared = prepare_image(data)
        return self._send_media(user, conversation_id, prepared)

    def send_voice(
        self,
        user: User,
        conversation_id: str,
        data: bytes,
        *,
        content_type: str,
        duration_seconds: int,
    ) -> MessageView:
        prepared = prepare_voice(
            data,
            content_type=content_type,
            duration_seconds=duration_seconds,
        )
        return self._send_media(user, conversation_id, prepared)

    def send_simulated_voice(
        self,
        user: User,
        conversation_id: str,
        payload: SimulatedVoiceRequest,
    ) -> MessageView:
        with self._lock:
            conversation = self._get_accepted(user, conversation_id)
            message = self._append_message(
                conversation,
                sender_id=user.id,
                kind=MessageKind.voice,
                text=format_voice_text(payload.duration_seconds),
                voice_seconds=payload.duration_seconds,
            )
            event = self._append_event(
                conversation,
                type=ConversationEventType.message_created,
                actor_id=user.id,
                message=message,
            )
            self._conversations.update(conversation)
            self._publish(event)
            return self._message_view(conversation, message, user)

    def propose_session(
        self,
        user: User,
        conversation_id: str,
        payload: SessionProposalRequest,
    ) -> MessageView:
        now = _now()
        proposed_utc = payload.proposed_for.astimezone(timezone.utc)
        if proposed_utc <= now:
            raise InvalidMessage("Choose a time in the future.")
        if proposed_utc > now + timedelta(days=366):
            raise InvalidMessage("Choose a time within the next year.")

        with self._lock:
            conversation = self._get_accepted(user, conversation_id)
            message = self._append_message(
                conversation,
                sender_id=user.id,
                kind=MessageKind.session,
                text=format_session_text(payload.proposed_for),
                session_at=payload.proposed_for,
                session_state=SessionState.proposed,
            )
            event = self._append_event(
                conversation,
                type=ConversationEventType.message_created,
                actor_id=user.id,
                message=message,
            )
            self._conversations.update(conversation)
            self._publish(event)
            return self._message_view(conversation, message, user)

    def respond_session(
        self,
        user: User,
        conversation_id: str,
        message_id: str,
        payload: SessionResponseRequest,
    ) -> MessageView:
        state = SessionState(payload.state)
        with self._lock:
            conversation = self._get_accepted(user, conversation_id)
            index = next(
                (
                    index
                    for index, message in enumerate(conversation.messages)
                    if message.id == message_id
                ),
                None,
            )
            if index is None:
                raise MessageNotFound()
            message = conversation.messages[index]
            if message.kind is not MessageKind.session:
                raise InvalidMessage("That message is not a session proposal.")
            if message.session_state is not SessionState.proposed:
                raise RequestAlreadyAnswered(
                    "That session proposal has already been answered."
                )
            if message.sender_id == user.id:
                raise Forbidden("The other person answers the proposal.")

            now = _now()
            updated = message.model_copy(
                update={"session_state": state}
            )
            conversation.messages[index] = updated
            conversation.last_read_sequences[user.id] = max(
                conversation.last_read_sequences.get(user.id, 0),
                updated.sequence,
            )
            conversation.updated_at = now
            event = self._append_event(
                conversation,
                type=ConversationEventType.session_updated,
                actor_id=user.id,
                created_at=now,
                message=updated,
                session_state=state,
            )
            self._conversations.update(conversation)
            self._publish(event)
            return self._message_view(conversation, updated, user)

    def log_call(
        self,
        user: User,
        conversation_id: str,
        payload: CallEventRequest,
    ) -> MessageView:
        with self._lock:
            conversation = self._get_accepted(user, conversation_id)
            message = self._append_message(
                conversation,
                sender_id=user.id,
                kind=MessageKind.call,
                text=format_call_text(
                    payload.kind,
                    connected=payload.connected,
                    duration_seconds=payload.duration_seconds,
                ),
                call_kind=payload.kind,
                call_connected=payload.connected,
                call_duration_seconds=payload.duration_seconds,
            )
            event = self._append_event(
                conversation,
                type=ConversationEventType.call_logged,
                actor_id=user.id,
                message=message,
            )
            self._conversations.update(conversation)
            self._publish(event)
            return self._message_view(conversation, message, user)

    def mark_read(
        self,
        user: User,
        conversation_id: str,
        payload: MarkReadRequest | None = None,
    ) -> ReadState:
        with self._lock:
            conversation = self._get_conversation(user, conversation_id)
            latest = conversation.next_message_sequence - 1
            current = conversation.last_read_sequences.get(user.id, 0)
            requested = (
                latest
                if payload is None or payload.through_sequence is None
                else payload.through_sequence
            )
            target = min(max(0, requested), latest)
            if target > current:
                conversation.last_read_sequences[user.id] = target
                event = self._append_event(
                    conversation,
                    type=ConversationEventType.conversation_read,
                    actor_id=user.id,
                    read_through_sequence=target,
                )
                self._conversations.update(conversation)
                self._publish(event)
            return ReadState(
                conversation_id=conversation.id,
                read_through_sequence=conversation.last_read_sequences.get(
                    user.id,
                    0,
                ),
                latest_message_sequence=latest,
                unread_count=self._unread_count(conversation, user.id),
            )

    def list_events(
        self,
        user: User,
        conversation_id: str,
        *,
        after: int = 0,
        limit: int = 100,
    ) -> EventPage:
        if not 1 <= limit <= 100:
            raise InvalidPagination("limit must be between 1 and 100.")
        if after < 0:
            raise InvalidPagination("after cannot be negative.")
        with self._lock:
            conversation = self._get_conversation(user, conversation_id)
            newer = [
                event
                for event in conversation.events
                if event.sequence > after
            ]
            selected = newer[:limit]
            has_more = len(newer) > len(selected)
            next_after = (
                selected[-1].sequence
                if selected and has_more
                else None
            )
            return EventPage(
                conversation_id=conversation.id,
                events=[
                    self._event_view(conversation, event, user)
                    for event in selected
                ],
                limit=limit,
                has_more=has_more,
                next_after=next_after,
                last_event_sequence=conversation.next_event_sequence - 1,
            )

    def event_view(
        self,
        user: User,
        event: ConversationEvent,
    ) -> ConversationEventView:
        with self._lock:
            conversation = self._conversations.get_by_id(
                event.conversation_id
            )
            if (
                conversation is None
                or user.id not in conversation.participant_ids
            ):
                raise ConversationNotFound()
            return self._event_view(conversation, event, user)

    def get_media(
        self,
        user: User,
        conversation_id: str,
        message_id: str,
    ) -> ChatMediaFile:
        with self._lock:
            conversation = self._get_conversation(user, conversation_id)
            message = next(
                (
                    message
                    for message in conversation.messages
                    if message.id == message_id
                ),
                None,
            )
            if message is None:
                raise MessageNotFound()
            if not message.media_key:
                raise MediaNotFound()
            stored = self._media.get(message.media_key)
            if stored is None:
                raise MediaNotFound()
            return ChatMediaFile(
                data=stored.data,
                content_type=(
                    message.media_content_type
                    or "application/octet-stream"
                ),
                filename=message.media_filename or "attachment",
            )

    # ── Internals ─────────────────────────────────────────────────────────

    def _send_media(
        self,
        user: User,
        conversation_id: str,
        prepared: PreparedImage | PreparedVoice,
    ) -> MessageView:
        is_image = isinstance(prepared, PreparedImage)
        with self._lock:
            conversation = self._get_accepted(user, conversation_id)
            media_key = str(uuid4())
            self._media.save(media_key, prepared.data)
            if is_image:
                message = self._append_message(
                    conversation,
                    sender_id=user.id,
                    kind=MessageKind.image,
                    text="Photo",
                    media_key=media_key,
                    media_content_type=prepared.content_type,
                    media_size=len(prepared.data),
                    media_filename=prepared.filename,
                    image_width=prepared.width,
                    image_height=prepared.height,
                )
            else:
                message = self._append_message(
                    conversation,
                    sender_id=user.id,
                    kind=MessageKind.voice,
                    text=format_voice_text(prepared.seconds),
                    media_key=media_key,
                    media_content_type=prepared.content_type,
                    media_size=len(prepared.data),
                    media_filename=prepared.filename,
                    voice_seconds=prepared.seconds,
                )
            event = self._append_event(
                conversation,
                type=ConversationEventType.message_created,
                actor_id=user.id,
                message=message,
            )
            self._conversations.update(conversation)
            self._publish(event)
            return self._message_view(conversation, message, user)

    def _get_conversation(
        self,
        user: User,
        conversation_id: str,
        *,
        request: bool = False,
    ) -> Conversation:
        conversation = self._conversations.get_by_id(conversation_id)
        if (
            conversation is None
            or user.id not in conversation.participant_ids
        ):
            if request:
                raise RequestNotFound()
            raise ConversationNotFound()
        return conversation

    def _get_accepted(
        self,
        user: User,
        conversation_id: str,
    ) -> Conversation:
        conversation = self._get_conversation(user, conversation_id)
        if conversation.status is not RequestStatus.accepted:
            raise ConversationLocked()
        return conversation

    @staticmethod
    def _require_pending(conversation: Conversation) -> None:
        if conversation.status is not RequestStatus.pending:
            raise RequestAlreadyAnswered()

    @staticmethod
    def _require_receiver(
        conversation: Conversation,
        user: User,
    ) -> None:
        receiver_id = conversation.other_id(conversation.requested_by)
        if user.id != receiver_id:
            raise Forbidden(
                "Only the person who received this request can answer it."
            )

    def _append_message(
        self,
        conversation: Conversation,
        *,
        sender_id: str,
        kind: MessageKind,
        text: str,
        created_at: datetime | None = None,
        media_key: str | None = None,
        media_content_type: str | None = None,
        media_size: int | None = None,
        media_filename: str | None = None,
        image_width: int | None = None,
        image_height: int | None = None,
        voice_seconds: int | None = None,
        session_at: datetime | None = None,
        session_state: SessionState | None = None,
        call_kind: CallKind | None = None,
        call_connected: bool | None = None,
        call_duration_seconds: int | None = None,
    ) -> ChatMessage:
        now = created_at or _now()
        message = ChatMessage(
            id=str(uuid4()),
            conversation_id=conversation.id,
            sender_id=sender_id,
            kind=kind,
            text=text,
            sequence=conversation.next_message_sequence,
            created_at=now,
            media_key=media_key,
            media_content_type=media_content_type,
            media_size=media_size,
            media_filename=media_filename,
            image_width=image_width,
            image_height=image_height,
            voice_seconds=voice_seconds,
            session_at=session_at,
            session_state=session_state,
            call_kind=call_kind,
            call_connected=call_connected,
            call_duration_seconds=call_duration_seconds,
        )
        conversation.messages.append(message)
        conversation.next_message_sequence += 1
        conversation.last_read_sequences[sender_id] = max(
            conversation.last_read_sequences.get(sender_id, 0),
            message.sequence,
        )
        conversation.updated_at = now
        return message

    def _append_event(
        self,
        conversation: Conversation,
        *,
        type: ConversationEventType,
        actor_id: str,
        created_at: datetime | None = None,
        message: ChatMessage | None = None,
        request_status: RequestStatus | None = None,
        read_through_sequence: int | None = None,
        session_state: SessionState | None = None,
    ) -> ConversationEvent:
        event = ConversationEvent(
            sequence=conversation.next_event_sequence,
            conversation_id=conversation.id,
            type=type,
            actor_id=actor_id,
            created_at=created_at or _now(),
            message=message,
            request_status=request_status,
            read_through_sequence=read_through_sequence,
            session_state=session_state,
        )
        conversation.events.append(event)
        conversation.next_event_sequence += 1
        return event

    def _publish(self, event: ConversationEvent) -> None:
        if self._broadcaster is not None:
            self._broadcaster.publish(event)

    def _request_summary(
        self,
        conversation: Conversation,
        viewer: User,
    ) -> RequestSummary:
        return RequestSummary(
            id=conversation.id,
            conversation_id=conversation.id,
            counterpart=self._counterpart_view(conversation, viewer),
            direction=(
                RequestDirection.sent
                if conversation.requested_by == viewer.id
                else RequestDirection.received
            ),
            subject=conversation.subject,
            score=conversation.score,
            status=conversation.status,
            note=conversation.note,
            response_note=conversation.response_note,
            created_at=conversation.created_at,
            updated_at=conversation.updated_at,
            responded_at=conversation.responded_at,
        )

    def _conversation_summary(
        self,
        conversation: Conversation,
        viewer: User,
    ) -> ConversationSummary:
        last_message = (
            conversation.messages[-1] if conversation.messages else None
        )
        return ConversationSummary(
            id=conversation.id,
            counterpart=self._counterpart_view(conversation, viewer),
            subject=conversation.subject,
            score=conversation.score,
            status=conversation.status,
            requested_by_me=conversation.requested_by == viewer.id,
            created_at=conversation.created_at,
            updated_at=conversation.updated_at,
            last_message=(
                self._message_preview(last_message, viewer)
                if last_message is not None
                else None
            ),
            unread_count=self._unread_count(conversation, viewer.id),
            last_event_sequence=conversation.next_event_sequence - 1,
        )

    def _conversation_detail(
        self,
        conversation: Conversation,
        viewer: User,
    ) -> ConversationDetail:
        summary = self._conversation_summary(conversation, viewer)
        return ConversationDetail(
            **summary.model_dump(),
            request_note=conversation.note,
            response_note=conversation.response_note,
            read_through_sequence=self._read_through(
                conversation,
                viewer.id,
            ),
            latest_message_sequence=conversation.next_message_sequence - 1,
        )

    def _counterpart_view(self, conversation: Conversation, viewer: User):
        target = self._users.get_by_id(conversation.other_id(viewer.id))
        if target is None:
            raise ConversationNotFound()
        return self._profiles.public_profile_for(
            target=target,
            target_profile=self._profiles.get_stored(target),
            viewer_profile=self._profiles.get_stored(viewer),
        )

    def _message_preview(
        self,
        message: ChatMessage,
        viewer: User,
    ) -> MessagePreview:
        return MessagePreview(
            id=message.id,
            kind=message.kind,
            text=message.text,
            sender_id=message.sender_id,
            from_me=message.sender_id == viewer.id,
            sequence=message.sequence,
            created_at=message.created_at,
        )

    def _message_view(
        self,
        conversation: Conversation,
        message: ChatMessage,
        viewer: User,
    ) -> MessageView:
        recipient_id = conversation.other_id(message.sender_id)
        read_by_recipient = (
            conversation.last_read_sequences.get(recipient_id, 0)
            >= message.sequence
        )
        media_url = (
            f"/conversations/{conversation.id}/messages/"
            f"{message.id}/media"
            if message.media_key
            else None
        )
        return MessageView(
            id=message.id,
            conversation_id=conversation.id,
            sender_id=message.sender_id,
            from_me=message.sender_id == viewer.id,
            kind=message.kind,
            text=message.text,
            sequence=message.sequence,
            created_at=message.created_at,
            read_by_recipient=read_by_recipient,
            media_url=media_url,
            media_content_type=message.media_content_type,
            media_size=message.media_size,
            image_width=message.image_width,
            image_height=message.image_height,
            voice_seconds=message.voice_seconds,
            session_at=message.session_at,
            session_state=message.session_state,
            call_kind=message.call_kind,
            call_connected=message.call_connected,
            call_duration_seconds=message.call_duration_seconds,
        )

    def _event_view(
        self,
        conversation: Conversation,
        event: ConversationEvent,
        viewer: User,
    ) -> ConversationEventView:
        return ConversationEventView(
            sequence=event.sequence,
            conversation_id=event.conversation_id,
            type=event.type,
            actor_id=event.actor_id,
            created_at=event.created_at,
            message=(
                self._message_view(conversation, event.message, viewer)
                if event.message is not None
                else None
            ),
            request_status=event.request_status,
            read_through_sequence=event.read_through_sequence,
            session_state=event.session_state,
        )

    @staticmethod
    def _unread_count(conversation: Conversation, user_id: str) -> int:
        read_through = conversation.last_read_sequences.get(user_id, 0)
        return sum(
            1
            for message in conversation.messages
            if message.sender_id != user_id
            and message.sequence > read_through
        )

    @staticmethod
    def _read_through(conversation: Conversation, user_id: str) -> int:
        return max(0, conversation.last_read_sequences.get(user_id, 0))


def _has_subject(profile: Profile, subject: str) -> bool:
    key = subject.casefold()
    return any(value.casefold() == key for value in profile.subjects)


def _now() -> datetime:
    return datetime.now(timezone.utc)
