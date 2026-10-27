from __future__ import annotations

from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient

from tests.chat_helpers import (
    accepted_conversation,
    create_pair,
    create_request,
    headers,
    third_user,
)


def _future(days: int = 2) -> str:
    return (
        datetime.now(timezone.utc) + timedelta(days=days)
    ).isoformat()


def test_session_proposal_is_answered_by_the_other_person(
    client: TestClient,
) -> None:
    student, tutor, conversation_id = accepted_conversation(client)
    proposed = client.post(
        f"/conversations/{conversation_id}/sessions",
        json={"proposed_for": _future()},
        headers=headers(student),
    )
    assert proposed.status_code == 201, proposed.text
    body = proposed.json()
    assert body["kind"] == "session"
    assert body["session_state"] == "proposed"
    assert body["text"].startswith("Session proposed · ")
    assert body["from_me"] is True
    message_id = body["id"]

    own_answer = client.post(
        f"/conversations/{conversation_id}/sessions/{message_id}/respond",
        json={"state": "accepted"},
        headers=headers(student),
    )
    assert own_answer.status_code == 403

    outsider = third_user(client, role="tutor", tag="-session")
    outsider_answer = client.post(
        f"/conversations/{conversation_id}/sessions/{message_id}/respond",
        json={"state": "accepted"},
        headers=headers(outsider),
    )
    assert outsider_answer.status_code == 404

    answered = client.post(
        f"/conversations/{conversation_id}/sessions/{message_id}/respond",
        json={"state": "accepted"},
        headers=headers(tutor),
    )
    assert answered.status_code == 200, answered.text
    assert answered.json()["session_state"] == "accepted"

    repeated = client.post(
        f"/conversations/{conversation_id}/sessions/{message_id}/respond",
        json={"state": "declined"},
        headers=headers(tutor),
    )
    assert repeated.status_code == 409

    events = client.get(
        f"/conversations/{conversation_id}/events",
        headers=headers(student),
    )
    session_events = [
        event
        for event in events.json()["events"]
        if event["type"] == "session_updated"
    ]
    assert len(session_events) == 1
    assert session_events[0]["session_state"] == "accepted"

    messages = client.get(
        f"/conversations/{conversation_id}/messages",
        headers=headers(student),
    )
    session_messages = [
        message
        for message in messages.json()["messages"]
        if message["kind"] == "session"
    ]
    assert session_messages[0]["session_state"] == "accepted"


def test_session_can_be_declined_by_the_other_person(
    client: TestClient,
) -> None:
    student, tutor, conversation_id = accepted_conversation(client)
    proposed = client.post(
        f"/conversations/{conversation_id}/sessions",
        json={"proposed_for": _future()},
        headers=headers(tutor),
    )
    assert proposed.status_code == 201, proposed.text
    message_id = proposed.json()["id"]

    declined = client.post(
        f"/conversations/{conversation_id}/sessions/{message_id}/respond",
        json={"state": "declined"},
        headers=headers(student),
    )
    assert declined.status_code == 200, declined.text
    assert declined.json()["session_state"] == "declined"


def test_session_validation_and_locked_chat(client: TestClient) -> None:
    student, tutor = create_pair(client)
    request = create_request(client, student, tutor)
    conversation_id = request["conversation_id"]

    pending = client.post(
        f"/conversations/{conversation_id}/sessions",
        json={"proposed_for": _future()},
        headers=headers(student),
    )
    assert pending.status_code == 409

    assert (
        client.post(
            f"/requests/{conversation_id}/accept",
            headers=headers(tutor),
        ).status_code
        == 200
    )

    past = client.post(
        f"/conversations/{conversation_id}/sessions",
        json={
            "proposed_for": (
                datetime.now(timezone.utc) - timedelta(days=1)
            ).isoformat()
        },
        headers=headers(student),
    )
    assert past.status_code == 422

    too_far = client.post(
        f"/conversations/{conversation_id}/sessions",
        json={"proposed_for": _future(days=400)},
        headers=headers(student),
    )
    assert too_far.status_code == 422

    invalid_state = client.post(
        f"/conversations/{conversation_id}/sessions/missing/respond",
        json={"state": "proposed"},
        headers=headers(tutor),
    )
    assert invalid_state.status_code == 422

    missing = client.post(
        f"/conversations/{conversation_id}/sessions/missing/respond",
        json={"state": "declined"},
        headers=headers(tutor),
    )
    assert missing.status_code == 404


def test_call_events_are_logged_in_the_thread(client: TestClient) -> None:
    student, tutor, conversation_id = accepted_conversation(client)
    connected = client.post(
        f"/conversations/{conversation_id}/calls",
        json={
            "kind": "video",
            "connected": True,
            "duration_seconds": 75,
        },
        headers=headers(student),
    )
    assert connected.status_code == 201, connected.text
    body = connected.json()
    assert body["kind"] == "call"
    assert body["call_kind"] == "video"
    assert body["call_connected"] is True
    assert body["call_duration_seconds"] == 75
    assert body["text"] == "Video call · 1:15"

    missed = client.post(
        f"/conversations/{conversation_id}/calls",
        json={
            "kind": "voice",
            "connected": False,
            "duration_seconds": 0,
        },
        headers=headers(tutor),
    )
    assert missed.status_code == 201, missed.text
    assert missed.json()["text"] == "Missed call"
    assert missed.json()["call_connected"] is False

    events = client.get(
        f"/conversations/{conversation_id}/events",
        headers=headers(student),
    )
    assert [
        event["type"]
        for event in events.json()["events"]
        if event["type"] == "call_logged"
    ] == ["call_logged", "call_logged"]


def test_call_validation_and_access_control(client: TestClient) -> None:
    student, tutor = create_pair(client)
    request = create_request(client, student, tutor)
    conversation_id = request["conversation_id"]

    pending = client.post(
        f"/conversations/{conversation_id}/calls",
        json={
            "kind": "voice",
            "connected": True,
            "duration_seconds": 10,
        },
        headers=headers(student),
    )
    assert pending.status_code == 409

    assert (
        client.post(
            f"/requests/{conversation_id}/accept",
            headers=headers(tutor),
        ).status_code
        == 200
    )

    missed_with_duration = client.post(
        f"/conversations/{conversation_id}/calls",
        json={
            "kind": "voice",
            "connected": False,
            "duration_seconds": 5,
        },
        headers=headers(student),
    )
    assert missed_with_duration.status_code == 422

    too_long = client.post(
        f"/conversations/{conversation_id}/calls",
        json={
            "kind": "voice",
            "connected": True,
            "duration_seconds": 3601,
        },
        headers=headers(student),
    )
    assert too_long.status_code == 422

    outsider = third_user(client, role="tutor", tag="-call")
    assert (
        client.post(
            f"/conversations/{conversation_id}/calls",
            json={
                "kind": "voice",
                "connected": True,
                "duration_seconds": 10,
            },
            headers=headers(outsider),
        ).status_code
        == 404
    )
