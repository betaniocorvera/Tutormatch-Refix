"""Accepted-only conversations, messages, media, sessions, and calls."""

from __future__ import annotations

from typing import Annotated

from fastapi import (
    APIRouter,
    File,
    Form,
    Query,
    Response,
    UploadFile,
    status,
)

from ..dependencies import ChatServiceDep, CurrentUser
from ..errors import AttachmentTooLarge
from ..models.chat import (
    CallEventRequest,
    ConversationDetail,
    ConversationSummary,
    EventPage,
    MarkReadRequest,
    MAX_VOICE_SECONDS,
    MessagePage,
    MessageView,
    ReadState,
    RequestStatus,
    SendTextRequest,
    SessionProposalRequest,
    SessionResponseRequest,
    SimulatedVoiceRequest,
)
from ..services.chat_media import (
    MAX_CHAT_IMAGE_BYTES,
    MAX_CHAT_VOICE_BYTES,
)

router = APIRouter(prefix="/conversations", tags=["conversations"])


@router.get("", response_model=list[ConversationSummary])
def list_conversations(
    user: CurrentUser,
    chat: ChatServiceDep,
    status: RequestStatus | None = None,
) -> list[ConversationSummary]:
    return chat.list_conversations(user, status=status)


@router.get("/{conversation_id}", response_model=ConversationDetail)
def get_conversation(
    conversation_id: str,
    user: CurrentUser,
    chat: ChatServiceDep,
) -> ConversationDetail:
    return chat.get_conversation(user, conversation_id)


@router.get(
    "/{conversation_id}/messages",
    response_model=MessagePage,
)
def list_messages(
    conversation_id: str,
    user: CurrentUser,
    chat: ChatServiceDep,
    limit: Annotated[int, Query(ge=1, le=100)] = 30,
    before: Annotated[int | None, Query(ge=0)] = None,
    after: Annotated[int | None, Query(ge=0)] = None,
) -> MessagePage:
    return chat.list_messages(
        user,
        conversation_id,
        limit=limit,
        before=before,
        after=after,
    )


@router.post(
    "/{conversation_id}/messages",
    response_model=MessageView,
    status_code=status.HTTP_201_CREATED,
)
def send_text(
    conversation_id: str,
    payload: SendTextRequest,
    user: CurrentUser,
    chat: ChatServiceDep,
) -> MessageView:
    return chat.send_text(user, conversation_id, payload)


@router.post(
    "/{conversation_id}/messages/image",
    response_model=MessageView,
    status_code=status.HTTP_201_CREATED,
)
async def send_image(
    conversation_id: str,
    user: CurrentUser,
    chat: ChatServiceDep,
    file: Annotated[UploadFile, File()],
) -> MessageView:
    data = await file.read(MAX_CHAT_IMAGE_BYTES + 1)
    if len(data) > MAX_CHAT_IMAGE_BYTES:
        raise AttachmentTooLarge(
            "That image is too large. Choose one under 5 MB."
        )
    return chat.send_image(user, conversation_id, data)


@router.post(
    "/{conversation_id}/messages/voice",
    response_model=MessageView,
    status_code=status.HTTP_201_CREATED,
)
async def send_voice(
    conversation_id: str,
    user: CurrentUser,
    chat: ChatServiceDep,
    file: Annotated[UploadFile, File()],
    duration_seconds: Annotated[
        int,
        Form(ge=1, le=MAX_VOICE_SECONDS),
    ],
) -> MessageView:
    data = await file.read(MAX_CHAT_VOICE_BYTES + 1)
    if len(data) > MAX_CHAT_VOICE_BYTES:
        raise AttachmentTooLarge(
            "That voice note is too large. Choose one under 10 MB."
        )
    return chat.send_voice(
        user,
        conversation_id,
        data,
        content_type=file.content_type or "",
        duration_seconds=duration_seconds,
    )


@router.post(
    "/{conversation_id}/messages/voice-note",
    response_model=MessageView,
    status_code=status.HTTP_201_CREATED,
)
def send_simulated_voice(
    conversation_id: str,
    payload: SimulatedVoiceRequest,
    user: CurrentUser,
    chat: ChatServiceDep,
) -> MessageView:
    return chat.send_simulated_voice(user, conversation_id, payload)


@router.get(
    "/{conversation_id}/messages/{message_id}/media",
)
def get_message_media(
    conversation_id: str,
    message_id: str,
    user: CurrentUser,
    chat: ChatServiceDep,
) -> Response:
    media = chat.get_media(user, conversation_id, message_id)
    safe_filename = (
        media.filename.replace('"', "").replace("\r", "").replace("\n", "")
    )
    return Response(
        content=media.data,
        media_type=media.content_type,
        headers={
            "Cache-Control": "private, max-age=60",
            "Content-Disposition": f'inline; filename="{safe_filename}"',
        },
    )


@router.post(
    "/{conversation_id}/sessions",
    response_model=MessageView,
    status_code=status.HTTP_201_CREATED,
)
def propose_session(
    conversation_id: str,
    payload: SessionProposalRequest,
    user: CurrentUser,
    chat: ChatServiceDep,
) -> MessageView:
    return chat.propose_session(user, conversation_id, payload)


@router.post(
    "/{conversation_id}/sessions/{message_id}/respond",
    response_model=MessageView,
)
def respond_session(
    conversation_id: str,
    message_id: str,
    payload: SessionResponseRequest,
    user: CurrentUser,
    chat: ChatServiceDep,
) -> MessageView:
    return chat.respond_session(
        user,
        conversation_id,
        message_id,
        payload,
    )


@router.post(
    "/{conversation_id}/calls",
    response_model=MessageView,
    status_code=status.HTTP_201_CREATED,
)
def log_call(
    conversation_id: str,
    payload: CallEventRequest,
    user: CurrentUser,
    chat: ChatServiceDep,
) -> MessageView:
    return chat.log_call(user, conversation_id, payload)


@router.post(
    "/{conversation_id}/read",
    response_model=ReadState,
)
def mark_read(
    conversation_id: str,
    user: CurrentUser,
    chat: ChatServiceDep,
    payload: MarkReadRequest | None = None,
) -> ReadState:
    return chat.mark_read(user, conversation_id, payload)


@router.get(
    "/{conversation_id}/events",
    response_model=EventPage,
)
def list_events(
    conversation_id: str,
    user: CurrentUser,
    chat: ChatServiceDep,
    after: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=100)] = 100,
) -> EventPage:
    return chat.list_events(
        user,
        conversation_id,
        after=after,
        limit=limit,
    )
