from __future__ import annotations

from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from tests.chat_helpers import (
    accepted_conversation,
    headers,
    third_user,
)


def _close_code(client: TestClient, url: str) -> int | None:
    try:
        with client.websocket_connect(url) as socket:
            socket.receive_json()
    except WebSocketDisconnect as exc:
        return exc.code
    return None


def test_websocket_rejects_missing_invalid_and_outsider_tokens(
    client: TestClient,
) -> None:
    _student, tutor, conversation_id = accepted_conversation(client)
    outsider = third_user(client, role="tutor", tag="-ws")

    assert (
        _close_code(
            client,
            f"/ws/conversations/{conversation_id}",
        )
        == 4401
    )
    assert (
        _close_code(
            client,
            f"/ws/conversations/{conversation_id}?token=not-a-token",
        )
        == 4401
    )
    assert (
        _close_code(
            client,
            f"/ws/conversations/{conversation_id}"
            f"?token={outsider['access_token']}",
        )
        == 4404
    )
    assert (
        _close_code(
            client,
            f"/ws/conversations/missing?token={tutor['access_token']}",
        )
        == 4404
    )


def test_websocket_rejects_bad_cursors_and_accepts_a_bearer_header(
    client: TestClient,
) -> None:
    _student, tutor, conversation_id = accepted_conversation(client)
    assert (
        _close_code(
            client,
            f"/ws/conversations/{conversation_id}"
            f"?token={tutor['access_token']}&after=not-a-number",
        )
        == 4400
    )
    assert (
        _close_code(
            client,
            f"/ws/conversations/{conversation_id}"
            f"?token={tutor['access_token']}&after=-1",
        )
        == 4400
    )

    with client.websocket_connect(
        f"/ws/conversations/{conversation_id}?after=2",
        headers={
            "Authorization": f"Bearer {tutor['access_token']}",
        },
    ) as socket:
        ready = socket.receive_json()
        assert ready["type"] == "ready"
        assert ready["status"] == "accepted"


def test_websocket_pushes_messages_and_read_receipts(
    client: TestClient,
) -> None:
    student, tutor, conversation_id = accepted_conversation(client)
    url = (
        f"/ws/conversations/{conversation_id}"
        f"?token={tutor['access_token']}&after=2"
    )
    with client.websocket_connect(url) as socket:
        ready = socket.receive_json()
        assert ready["type"] == "ready"
        assert ready["status"] == "accepted"

        sent = client.post(
            f"/conversations/{conversation_id}/messages",
            json={"text": "The socket should deliver this."},
            headers=headers(student),
        )
        assert sent.status_code == 201
        message_event = socket.receive_json()
        assert message_event["type"] == "message_created"
        assert message_event["message"]["text"] == "The socket should deliver this."
        assert message_event["message"]["from_me"] is False

        read = client.post(
            f"/conversations/{conversation_id}/read",
            headers=headers(tutor),
        )
        assert read.status_code == 200
        read_event = socket.receive_json()
        assert read_event["type"] == "conversation_read"
        assert read_event["actor_id"] == tutor["user"]["id"]
        assert read_event["read_through_sequence"] == 2
