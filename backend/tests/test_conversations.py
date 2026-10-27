from __future__ import annotations

from fastapi.testclient import TestClient

from tests.chat_helpers import (
    accepted_conversation,
    create_pair,
    create_request,
    headers,
    third_user,
)


def test_conversations_require_authentication(client: TestClient) -> None:
    assert client.get("/conversations").status_code == 401
    assert client.get("/conversations/missing").status_code == 401
    assert client.get("/conversations/missing/messages").status_code == 401
    assert client.get("/conversations/missing/events").status_code == 401


def test_accepted_only_text_chat_and_text_validation(
    client: TestClient,
) -> None:
    student, tutor = create_pair(client)
    request = create_request(client, student, tutor)
    conversation_id = request["conversation_id"]

    pending_send = client.post(
        f"/conversations/{conversation_id}/messages",
        json={"text": "Not yet."},
        headers=headers(student),
    )
    assert pending_send.status_code == 409

    assert (
        client.post(
            f"/requests/{conversation_id}/accept",
            headers=headers(tutor),
        ).status_code
        == 200
    )

    blank = client.post(
        f"/conversations/{conversation_id}/messages",
        json={"text": "   "},
        headers=headers(student),
    )
    assert blank.status_code == 422

    too_long = client.post(
        f"/conversations/{conversation_id}/messages",
        json={"text": "x" * 2001},
        headers=headers(student),
    )
    assert too_long.status_code == 422

    sent = client.post(
        f"/conversations/{conversation_id}/messages",
        json={"text": "  Tuesday after six works for me.  "},
        headers=headers(student),
    )
    assert sent.status_code == 201
    body = sent.json()
    assert body["text"] == "Tuesday after six works for me."
    assert body["from_me"] is True
    assert body["sequence"] == 2
    assert body["read_by_recipient"] is False

    outsider = third_user(client, role="tutor", tag="-chat")
    assert (
        client.post(
            f"/conversations/{conversation_id}/messages",
            json={"text": "I am not a participant."},
            headers=headers(outsider),
        ).status_code
        == 404
    )
    assert (
        client.get(
            f"/conversations/{conversation_id}/messages",
            headers=headers(outsider),
        ).status_code
        == 404
    )


def test_message_pagination_uses_before_and_after(
    client: TestClient,
) -> None:
    student, tutor, conversation_id = accepted_conversation(client)
    for index in range(5):
        response = client.post(
            f"/conversations/{conversation_id}/messages",
            json={"text": f"Message {index}"},
            headers=headers(student),
        )
        assert response.status_code == 201, response.text

    latest = client.get(
        f"/conversations/{conversation_id}/messages?limit=2",
        headers=headers(student),
    )
    assert latest.status_code == 200
    latest_body = latest.json()
    assert [message["sequence"] for message in latest_body["messages"]] == [
        5,
        6,
    ]
    assert latest_body["has_more"] is True
    assert latest_body["next_before"] == 5
    assert latest_body["latest_sequence"] == 6

    older = client.get(
        f"/conversations/{conversation_id}/messages?limit=2&before=5",
        headers=headers(student),
    )
    assert older.status_code == 200
    older_body = older.json()
    assert [message["sequence"] for message in older_body["messages"]] == [
        3,
        4,
    ]
    assert older_body["has_more"] is True
    assert older_body["next_before"] == 3

    newer = client.get(
        f"/conversations/{conversation_id}/messages?limit=2&after=4",
        headers=headers(student),
    )
    assert newer.status_code == 200
    newer_body = newer.json()
    assert [message["sequence"] for message in newer_body["messages"]] == [
        5,
        6,
    ]
    assert newer_body["has_more"] is False
    assert newer_body["next_after"] is None

    more_newer = client.get(
        f"/conversations/{conversation_id}/messages?limit=2&after=1",
        headers=headers(student),
    )
    assert more_newer.status_code == 200
    more_newer_body = more_newer.json()
    assert [message["sequence"] for message in more_newer_body["messages"]] == [
        2,
        3,
    ]
    assert more_newer_body["has_more"] is True
    assert more_newer_body["next_after"] == 3

    both = client.get(
        f"/conversations/{conversation_id}/messages?before=4&after=1",
        headers=headers(student),
    )
    assert both.status_code == 422

    invalid_limit = client.get(
        f"/conversations/{conversation_id}/messages?limit=0",
        headers=headers(student),
    )
    assert invalid_limit.status_code == 422


def test_read_receipts_and_unread_counts(client: TestClient) -> None:
    student, tutor, conversation_id = accepted_conversation(client)
    for text in ("One", "Two"):
        response = client.post(
            f"/conversations/{conversation_id}/messages",
            json={"text": text},
            headers=headers(student),
        )
        assert response.status_code == 201

    tutor_detail = client.get(
        f"/conversations/{conversation_id}",
        headers=headers(tutor),
    )
    assert tutor_detail.status_code == 200
    assert tutor_detail.json()["unread_count"] == 2
    assert tutor_detail.json()["read_through_sequence"] == 1

    student_messages = client.get(
        f"/conversations/{conversation_id}/messages",
        headers=headers(student),
    )
    assert student_messages.status_code == 200
    own = [
        message
        for message in student_messages.json()["messages"]
        if message["from_me"]
    ]
    assert len(own) == 3
    assert [
        message["read_by_recipient"] for message in own
    ] == [True, False, False]

    read = client.post(
        f"/conversations/{conversation_id}/read",
        json={"through_sequence": 3},
        headers=headers(tutor),
    )
    assert read.status_code == 200
    assert read.json()["read_through_sequence"] == 3
    assert read.json()["unread_count"] == 0

    student_messages = client.get(
        f"/conversations/{conversation_id}/messages",
        headers=headers(student),
    )
    own = [
        message
        for message in student_messages.json()["messages"]
        if message["from_me"]
    ]
    assert all(message["read_by_recipient"] for message in own)

    events = client.get(
        f"/conversations/{conversation_id}/events",
        headers=headers(student),
    )
    assert events.status_code == 200
    event_types = [event["type"] for event in events.json()["events"]]
    assert "conversation_read" in event_types
    read_events = [
        event
        for event in events.json()["events"]
        if event["type"] == "conversation_read"
    ]
    assert read_events[-1]["read_through_sequence"] == 3

    before_count = len(events.json()["events"])
    repeat = client.post(
        f"/conversations/{conversation_id}/read",
        json={"through_sequence": 3},
        headers=headers(tutor),
    )
    assert repeat.status_code == 200
    after = client.get(
        f"/conversations/{conversation_id}/events",
        headers=headers(student),
    )
    assert len(after.json()["events"]) == before_count

    future_read = client.post(
        f"/conversations/{conversation_id}/read",
        json={"through_sequence": 999},
        headers=headers(tutor),
    )
    assert future_read.status_code == 200
    assert future_read.json()["read_through_sequence"] == 3


def test_polling_event_page_resumes_after_a_sequence(
    client: TestClient,
) -> None:
    student, tutor, conversation_id = accepted_conversation(
        client,
        accept_note="Tuesday works.",
    )
    first_page = client.get(
        f"/conversations/{conversation_id}/events?after=0&limit=2",
        headers=headers(student),
    )
    assert first_page.status_code == 200
    body = first_page.json()
    assert [event["sequence"] for event in body["events"]] == [1, 2]
    assert body["has_more"] is False
    assert body["next_after"] is None

    sent = client.post(
        f"/conversations/{conversation_id}/messages",
        json={"text": "Great, see you then."},
        headers=headers(student),
    )
    assert sent.status_code == 201

    resumed = client.get(
        f"/conversations/{conversation_id}/events?after=2",
        headers=headers(student),
    )
    assert resumed.status_code == 200
    assert [event["sequence"] for event in resumed.json()["events"]] == [3]
    assert resumed.json()["events"][0]["type"] == "message_created"

    outsider = third_user(client, role="tutor", tag="-events")
    assert (
        client.get(
            f"/conversations/{conversation_id}/events",
            headers=headers(outsider),
        ).status_code
        == 404
    )


def test_conversation_list_reports_last_message_and_status(
    client: TestClient,
) -> None:
    student, tutor, conversation_id = accepted_conversation(
        client,
        accept_note="Tuesday works.",
    )
    sent = client.post(
        f"/conversations/{conversation_id}/messages",
        json={"text": "Great, see you then."},
        headers=headers(student),
    )
    assert sent.status_code == 201

    student_list = client.get(
        "/conversations",
        headers=headers(student),
    )
    assert student_list.status_code == 200
    student_body = student_list.json()
    assert len(student_body) == 1
    assert student_body[0]["id"] == conversation_id
    assert student_body[0]["status"] == "accepted"
    assert student_body[0]["requested_by_me"] is True
    assert student_body[0]["last_message"]["text"] == "Great, see you then."
    assert student_body[0]["unread_count"] == 0

    tutor_list = client.get(
        "/conversations?status=accepted",
        headers=headers(tutor),
    )
    assert tutor_list.status_code == 200
    tutor_body = tutor_list.json()
    assert tutor_body[0]["unread_count"] == 1
    assert tutor_body[0]["last_message"]["from_me"] is False

    declined = client.get(
        "/conversations?status=declined",
        headers=headers(student),
    )
    assert declined.status_code == 200
    assert declined.json() == []
