from __future__ import annotations

from fastapi.testclient import TestClient

STUDENT_STYLE = "Watch one worked example, then do the next one myself"
TUTOR_STYLE = "I work through examples slowly and let the student steer"
STUDENT_GOAL = "Move up a grade or two this year"
TUTOR_GOAL = "Fill a few steady evenings a week"

_DAYS = {
    "Mon": 0,
    "Tue": 1,
    "Wed": 2,
    "Thu": 3,
    "Fri": 4,
    "Sat": 5,
    "Sun": 6,
}
_PARTS = {"Morn": 0, "Aft": 1, "Eve": 2}


def availability(*slots: str) -> list[bool]:
    grid = [False] * 21
    for slot in slots:
        day, part = slot.split("-")
        grid[_DAYS[day] * 3 + _PARTS[part]] = True
    return grid


def register(
    client: TestClient,
    *,
    email: str,
    role: str,
    name: str,
) -> dict:
    response = client.post(
        "/auth/register",
        json={
            "email": email,
            "password": "correct horse battery",
            "role": role,
            "display_name": name,
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


def headers(tokens: dict) -> dict[str, str]:
    return {"Authorization": f"Bearer {tokens['access_token']}"}


def complete_profile(
    client: TestClient,
    tokens: dict,
    role: str,
    *,
    name: str | None = None,
    omit: tuple[str, ...] = (),
    **overrides,
) -> dict:
    if role == "student":
        payload = {
            "name": name or "Maya Chen",
            "subjects": ["Calculus", "Physics"],
            "style": STUDENT_STYLE,
            "mode": "both",
            "budget": 50,
            "availability": availability(
                "Mon-Eve",
                "Tue-Eve",
                "Wed-Eve",
                "Thu-Eve",
                "Sat-Morn",
            ),
            "goal": STUDENT_GOAL,
            "area_id": "london-highbury",
            "location_privacy": "city_only",
        }
    else:
        payload = {
            "name": name or "Amara Okonkwo",
            "subjects": ["Calculus", "Physics", "Algebra"],
            "style": TUTOR_STYLE,
            "mode": "both",
            "budget": 46,
            "availability": availability(
                "Mon-Eve",
                "Tue-Eve",
                "Wed-Eve",
                "Thu-Eve",
                "Sat-Morn",
            ),
            "goal": TUTOR_GOAL,
            "area_id": "london-highbury",
            "location_privacy": "city_only",
        }
    for key in omit:
        payload.pop(key, None)
    payload.update(overrides)
    response = client.put(
        "/profile",
        json=payload,
        headers=headers(tokens),
    )
    assert response.status_code == 200, response.text
    return response.json()


def create_pair(
    client: TestClient,
    *,
    tag: str = "",
    student_name: str = "Maya Chen",
    tutor_name: str = "Amara Okonkwo",
) -> tuple[dict, dict]:
    student = register(
        client,
        email=f"student{tag}@example.com",
        role="student",
        name=student_name,
    )
    tutor = register(
        client,
        email=f"tutor{tag}@example.com",
        role="tutor",
        name=tutor_name,
    )
    complete_profile(
        client,
        student,
        "student",
        name=student_name,
    )
    complete_profile(
        client,
        tutor,
        "tutor",
        name=tutor_name,
    )
    return student, tutor


def create_request(
    client: TestClient,
    student: dict,
    tutor: dict,
    *,
    subject: str = "Calculus",
    note: str = (
        "I have a mock in three weeks and need help with calculus."
    ),
) -> dict:
    response = client.post(
        "/requests",
        json={
            "counterpart_id": tutor["user"]["id"],
            "subject": subject,
            "note": note,
        },
        headers=headers(student),
    )
    assert response.status_code == 201, response.text
    return response.json()


def accept_request(
    client: TestClient,
    tutor: dict,
    conversation_id: str,
    *,
    note: str | None = None,
) -> dict:
    body = {} if note is None else {"note": note}
    response = client.post(
        f"/requests/{conversation_id}/accept",
        json=body,
        headers=headers(tutor),
    )
    assert response.status_code == 200, response.text
    return response.json()


def accepted_conversation(
    client: TestClient,
    *,
    tag: str = "",
    accept_note: str | None = None,
) -> tuple[dict, dict, str]:
    student, tutor = create_pair(client, tag=tag)
    request = create_request(client, student, tutor)
    accept_request(
        client,
        tutor,
        request["conversation_id"],
        note=accept_note,
    )
    return student, tutor, request["conversation_id"]


def third_user(
    client: TestClient,
    *,
    role: str = "student",
    tag: str = "",
) -> dict:
    return register(
        client,
        email=f"third{tag}@example.com",
        role=role,
        name="Third Person",
    )
