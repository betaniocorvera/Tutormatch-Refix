from __future__ import annotations

from fastapi.testclient import TestClient

from tests.chat_helpers import (
    accept_request,
    complete_profile,
    create_pair,
    create_request,
    headers,
    register,
    third_user,
)


def test_requests_require_authentication(client: TestClient) -> None:
    assert client.get("/requests").status_code == 401
    assert (
        client.post(
            "/requests",
            json={
                "counterpart_id": "someone",
                "subject": "Calculus",
                "note": "I need help with a calculus mock next week.",
            },
        ).status_code
        == 401
    )


def test_create_request_returns_a_privacy_safe_summary(
    client: TestClient,
) -> None:
    student, tutor = create_pair(client)
    request = create_request(client, student, tutor)
    conversation_id = request["conversation_id"]

    assert request["status"] == "pending"
    assert request["direction"] == "sent"
    assert request["subject"] == "Calculus"
    assert request["score"] == 100
    assert request["counterpart"]["id"] == tutor["user"]["id"]
    assert "email" not in request["counterpart"]
    assert "password_hash" not in request["counterpart"]
    assert "birthdate" not in request["counterpart"]

    tutor_detail = client.get(
        f"/conversations/{conversation_id}",
        headers=headers(tutor),
    )
    assert tutor_detail.status_code == 200
    tutor_body = tutor_detail.json()
    assert tutor_body["status"] == "pending"
    assert tutor_body["requested_by_me"] is False
    assert tutor_body["unread_count"] == 1
    assert tutor_body["last_message"]["text"] == request["note"]

    student_detail = client.get(
        f"/conversations/{conversation_id}",
        headers=headers(student),
    )
    assert student_detail.status_code == 200
    assert student_detail.json()["unread_count"] == 0

    messages = client.get(
        f"/conversations/{conversation_id}/messages",
        headers=headers(tutor),
    )
    assert messages.status_code == 200
    assert messages.json()["messages"][0]["text"] == request["note"]
    assert messages.json()["messages"][0]["from_me"] is False

    sent = client.get(
        "/requests?direction=sent",
        headers=headers(student),
    )
    received = client.get(
        "/requests?direction=received",
        headers=headers(tutor),
    )
    assert [item["id"] for item in sent.json()] == [conversation_id]
    assert [item["id"] for item in received.json()] == [conversation_id]


def test_request_validation_rejects_bad_pairs_and_subjects(
    client: TestClient,
) -> None:
    student, tutor = create_pair(client)
    note = "I need help with a calculus mock next week."

    self_request = client.post(
        "/requests",
        json={
            "counterpart_id": student["user"]["id"],
            "subject": "Calculus",
            "note": note,
        },
        headers=headers(student),
    )
    assert self_request.status_code == 422

    same_role = register(
        client,
        email="other-student@example.com",
        role="student",
        name="Other Student",
    )
    complete_profile(client, same_role, "student", name="Other Student")
    same_role_request = client.post(
        "/requests",
        json={
            "counterpart_id": same_role["user"]["id"],
            "subject": "Calculus",
            "note": note,
        },
        headers=headers(student),
    )
    assert same_role_request.status_code == 422

    unknown = client.post(
        "/requests",
        json={
            "counterpart_id": "missing-user",
            "subject": "Calculus",
            "note": note,
        },
        headers=headers(student),
    )
    assert unknown.status_code == 404

    unshared_subject = client.post(
        "/requests",
        json={
            "counterpart_id": tutor["user"]["id"],
            "subject": "Chemistry",
            "note": note,
        },
        headers=headers(student),
    )
    assert unshared_subject.status_code == 422

    short_note = client.post(
        "/requests",
        json={
            "counterpart_id": tutor["user"]["id"],
            "subject": "Calculus",
            "note": "Too short",
        },
        headers=headers(student),
    )
    assert short_note.status_code == 422

    incomplete = register(
        client,
        email="incomplete@example.com",
        role="student",
        name="Incomplete",
    )
    incomplete_request = client.post(
        "/requests",
        json={
            "counterpart_id": tutor["user"]["id"],
            "subject": "Calculus",
            "note": note,
        },
        headers=headers(incomplete),
    )
    assert incomplete_request.status_code == 422


def test_open_request_is_unique_per_pair(client: TestClient) -> None:
    student, tutor = create_pair(client)
    request = create_request(client, student, tutor)

    duplicate = client.post(
        "/requests",
        json={
            "counterpart_id": tutor["user"]["id"],
            "subject": "Calculus",
            "note": "A second note while the first is still pending.",
        },
        headers=headers(student),
    )
    assert duplicate.status_code == 409

    accept_request(client, tutor, request["conversation_id"])
    accepted_duplicate = client.post(
        "/requests",
        json={
            "counterpart_id": tutor["user"]["id"],
            "subject": "Calculus",
            "note": "Trying again after the request was accepted.",
        },
        headers=headers(student),
    )
    assert accepted_duplicate.status_code == 409


def test_only_the_receiver_can_accept_and_chat_opens(
    client: TestClient,
) -> None:
    student, tutor = create_pair(client)
    request = create_request(client, student, tutor)
    conversation_id = request["conversation_id"]

    own_accept = client.post(
        f"/requests/{conversation_id}/accept",
        headers=headers(student),
    )
    assert own_accept.status_code == 403

    outsider = third_user(client, role="tutor", tag="-accept")
    outsider_accept = client.post(
        f"/requests/{conversation_id}/accept",
        headers=headers(outsider),
    )
    assert outsider_accept.status_code == 404

    pending_send = client.post(
        f"/conversations/{conversation_id}/messages",
        json={"text": "Can I send this yet?"},
        headers=headers(student),
    )
    assert pending_send.status_code == 409

    accepted = client.post(
        f"/requests/{conversation_id}/accept",
        headers=headers(tutor),
    )
    assert accepted.status_code == 200
    assert accepted.json()["status"] == "accepted"
    assert accepted.json()["response_note"] is None

    sent = client.post(
        f"/conversations/{conversation_id}/messages",
        json={"text": "Tuesday after six works for me."},
        headers=headers(student),
    )
    assert sent.status_code == 201

    outsider_send = client.post(
        f"/conversations/{conversation_id}/messages",
        json={"text": "I am not part of this conversation."},
        headers=headers(outsider),
    )
    assert outsider_send.status_code == 404

    second_accept = client.post(
        f"/requests/{conversation_id}/accept",
        headers=headers(tutor),
    )
    assert second_accept.status_code == 409

    accepted_list = client.get(
        "/requests?direction=sent&status=accepted",
        headers=headers(student),
    )
    assert accepted_list.status_code == 200
    assert len(accepted_list.json()) == 1


def test_decline_keeps_reason_and_allows_a_new_request(
    client: TestClient,
) -> None:
    student, tutor = create_pair(client)
    request = create_request(client, student, tutor)
    conversation_id = request["conversation_id"]

    own_decline = client.post(
        f"/requests/{conversation_id}/decline",
        json={"reason": "I cannot take that slot."},
        headers=headers(student),
    )
    assert own_decline.status_code == 403

    declined = client.post(
        f"/requests/{conversation_id}/decline",
        json={"reason": "I am fully booked on weekday evenings."},
        headers=headers(tutor),
    )
    assert declined.status_code == 200
    assert declined.json()["status"] == "declined"
    assert (
        declined.json()["response_note"]
        == "I am fully booked on weekday evenings."
    )

    detail = client.get(
        f"/conversations/{conversation_id}",
        headers=headers(student),
    )
    assert detail.status_code == 200
    body = detail.json()
    assert body["status"] == "declined"
    assert body["response_note"] == "I am fully booked on weekday evenings."
    assert body["last_message"]["text"] == "I am fully booked on weekday evenings."
    assert body["unread_count"] == 1

    locked = client.post(
        f"/conversations/{conversation_id}/messages",
        json={"text": "Can we still talk?"},
        headers=headers(student),
    )
    assert locked.status_code == 409

    reopened = client.post(
        "/requests",
        json={
            "counterpart_id": tutor["user"]["id"],
            "subject": "Calculus",
            "note": "Could Saturday morning work instead?",
        },
        headers=headers(student),
    )
    assert reopened.status_code == 201
    assert reopened.json()["status"] == "pending"
    assert reopened.json()["conversation_id"] == conversation_id

    messages = client.get(
        f"/conversations/{conversation_id}/messages",
        headers=headers(tutor),
    )
    texts = [message["text"] for message in messages.json()["messages"]]
    assert "I am fully booked on weekday evenings." in texts
    assert "Could Saturday morning work instead?" in texts
    assert messages.json()["messages"][-1]["sequence"] == 3

    accepted = client.post(
        f"/requests/{conversation_id}/accept",
        headers=headers(tutor),
    )
    assert accepted.status_code == 200
    assert accepted.json()["status"] == "accepted"


def test_requests_are_private_to_the_two_participants(
    client: TestClient,
) -> None:
    student, tutor = create_pair(client)
    request = create_request(client, student, tutor)
    outsider = third_user(client, role="tutor", tag="-privacy")

    assert (
        client.get(
            f"/requests/{request['id']}",
            headers=headers(outsider),
        ).status_code
        == 404
    )
    assert (
        client.get(
            f"/conversations/{request['conversation_id']}",
            headers=headers(outsider),
        ).status_code
        == 404
    )
    assert (
        client.get(
            f"/conversations/{request['conversation_id']}/messages",
            headers=headers(outsider),
        ).status_code
        == 404
    )
    assert client.get(
        "/requests",
        headers=headers(outsider),
    ).json() == []
