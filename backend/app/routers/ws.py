"""WebSocket event stream for one conversation.

Sending stays on REST; the socket is the push channel for new messages,
read receipts, session answers, and call events. Clients that lose the socket
resume from their last event sequence through ``GET /conversations/{id}/events``.
"""

from __future__ import annotations

import asyncio

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from ..errors import AppError, ConversationNotFound

router = APIRouter(tags=["websocket"])

_PING_SECONDS = 5.0
_REPLAY_LIMIT = 100


def _bearer_token(websocket: WebSocket) -> str | None:
    token = websocket.query_params.get("token")
    if token:
        return token
    header = websocket.headers.get("authorization", "")
    if header.lower().startswith("bearer "):
        return header[7:].strip()
    return None


@router.websocket("/ws/conversations/{conversation_id}")
async def conversation_events(
    websocket: WebSocket,
    conversation_id: str,
) -> None:
    container = websocket.app.state.container
    token = _bearer_token(websocket)
    if not token:
        await websocket.close(code=4401)
        return
    try:
        user = container.auth.get_user_from_access_token(token)
    except AppError:
        await websocket.close(code=4401)
        return

    raw_after = websocket.query_params.get("after", "0")
    try:
        after = int(raw_after)
    except (TypeError, ValueError):
        await websocket.close(code=4400)
        return
    if after < 0:
        await websocket.close(code=4400)
        return

    try:
        detail = container.chat.get_conversation(user, conversation_id)
    except ConversationNotFound:
        await websocket.close(code=4404)
        return

    await websocket.accept()
    queue = container.broadcaster.subscribe(conversation_id)
    last_sequence = after
    try:
        await websocket.send_json(
            {
                "type": "ready",
                "conversation_id": conversation_id,
                "status": detail.status.value,
                "last_event_sequence": detail.last_event_sequence,
                "read_through_sequence": detail.read_through_sequence,
            }
        )

        cursor = after
        while True:
            page = container.chat.list_events(
                user,
                conversation_id,
                after=cursor,
                limit=_REPLAY_LIMIT,
            )
            for event in page.events:
                await websocket.send_json(
                    event.model_dump(mode="json")
                )
                last_sequence = max(last_sequence, event.sequence)
            if not page.has_more:
                break
            cursor = page.next_after or (
                page.events[-1].sequence if page.events else cursor
            )

        while True:
            try:
                event = await asyncio.wait_for(
                    queue.get(),
                    timeout=_PING_SECONDS,
                )
            except asyncio.TimeoutError:
                await websocket.send_json({"type": "ping"})
                continue
            if event.sequence <= last_sequence:
                continue
            view = container.chat.event_view(user, event)
            await websocket.send_json(view.model_dump(mode="json"))
            last_sequence = event.sequence
    except WebSocketDisconnect:
        return
    except RuntimeError:
        # The loop or transport closed while a thread-safe publish was queued.
        return
    finally:
        container.broadcaster.unsubscribe(conversation_id, queue)
