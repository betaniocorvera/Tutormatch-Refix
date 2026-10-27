from __future__ import annotations

from fastapi.testclient import TestClient

STUDENT_STYLE = "Watch one worked example, then do the next one myself"
STUDENT_STYLE_ALT = "Talk it through until it makes sense"
STUDENT_GOAL = "Move up a grade or two this year"
TUTOR_STYLE = "I work through examples slowly and let the student steer"
TUTOR_STYLE_ALT = "I teach by discussion and questioning"
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


def _availability(*slots: str) -> list[bool]:
    grid = [False] * 21
    for slot in slots:
        day, part = slot.split("-")
        grid[_DAYS[day] * 3 + _PARTS[part]] = True
    return grid


def _register(
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


def _headers(tokens: dict) -> dict[str, str]:
    return {"Authorization": f"Bearer {tokens['access_token']}"}


def _student_payload(**overrides) -> dict:
    payload = {
        "name": "Maya Chen",
        "subjects": ["Calculus", "Physics"],
        "style": STUDENT_STYLE,
        "mode": "both",
        "budget": 50,
        "availability": _availability(
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
    payload.update(overrides)
    return payload


def _tutor_payload(**overrides) -> dict:
    payload = {
        "name": "Amara Okonkwo",
        "subjects": ["Calculus", "Physics", "Algebra"],
        "style": TUTOR_STYLE,
        "mode": "both",
        "budget": 46,
        "availability": _availability(
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
    payload.update(overrides)
    return payload


def _complete(
    client: TestClient,
    tokens: dict,
    payload: dict,
) -> dict:
    response = client.put(
        "/profile",
        json=payload,
        headers=_headers(tokens),
    )
    assert response.status_code == 200, response.text
    return response.json()


def _match_ids(response) -> list[str]:
    assert response.status_code == 200, response.text
    return [match["profile"]["id"] for match in response.json()["matches"]]


def test_matches_require_authentication(client: TestClient) -> None:
    response = client.get("/matches")
    assert response.status_code == 401


def test_matches_cold_start_lists_the_missing_answers(
    client: TestClient,
) -> None:
    tokens = _register(
        client,
        email="cold@example.com",
        role="student",
        name="Cold Start",
    )

    response = client.get("/matches", headers=_headers(tokens))

    assert response.status_code == 200
    body = response.json()
    assert body["matches"] == []
    assert body["pool_size"] == 0
    assert body["ranked_count"] == 0
    assert body["cold_start"]["reason"] == "profile_incomplete"
    assert body["cold_start"]["missing"] == [
        "subjects",
        "style",
        "availability",
        "goal",
        "budget",
    ]

    partial = _student_payload()
    partial.pop("goal")
    partial.pop("budget")
    _complete(client, tokens, partial)

    partial_response = client.get("/matches", headers=_headers(tokens))
    assert partial_response.status_code == 200
    assert partial_response.json()["cold_start"]["missing"] == [
        "goal",
        "budget",
    ]


def test_matches_require_a_completed_opposite_role_candidate(
    client: TestClient,
) -> None:
    viewer = _register(
        client,
        email="viewer@example.com",
        role="student",
        name="Maya Chen",
    )
    _complete(client, viewer, _student_payload())

    incomplete = _register(
        client,
        email="incomplete@example.com",
        role="tutor",
        name="Incomplete Tutor",
    )
    _complete(
        client,
        incomplete,
        {"name": "Incomplete Tutor", "subjects": ["Calculus"]},
    )

    same_role = _register(
        client,
        email="same@example.com",
        role="student",
        name="Same Role",
    )
    _complete(client, same_role, _student_payload(name="Same Role"))

    response = client.get("/matches", headers=_headers(viewer))
    body = response.json()
    assert response.status_code == 200
    assert body["pool_size"] == 0
    assert body["matches"] == []
    assert body["cold_start"]["reason"] == "no_candidates"

    tutor = _register(
        client,
        email="tutor@example.com",
        role="tutor",
        name="Amara Okonkwo",
    )
    _complete(client, tutor, _tutor_payload())

    response = client.get("/matches", headers=_headers(viewer))
    body = response.json()
    assert response.status_code == 200
    assert body["pool_size"] == 1
    assert body["cold_start"] is None
    assert [match["profile"]["id"] for match in body["matches"]] == [
        tutor["user"]["id"]
    ]


def test_matches_returns_score_dimensions_reasons_and_public_profile(
    client: TestClient,
) -> None:
    viewer = _register(
        client,
        email="maya@example.com",
        role="student",
        name="Maya Chen",
    )
    _complete(client, viewer, _student_payload())
    tutor = _register(
        client,
        email="amara@example.com",
        role="tutor",
        name="Amara Okonkwo",
    )
    _complete(client, tutor, _tutor_payload())

    response = client.get("/matches", headers=_headers(viewer))

    assert response.status_code == 200
    body = response.json()
    assert body["viewer_id"] == viewer["user"]["id"]
    assert body["viewer_role"] == "student"
    assert body["pool_size"] == 1
    assert body["ranked_count"] == 1
    assert body["returned"] == 1
    assert body["cold_start"] is None

    match = body["matches"][0]
    assert match["rank"] == 1
    assert match["score"] == 100
    assert match["tier"] == "strong"
    assert match["tier_label"] == "Strong match"
    assert match["overlap_slots"] == 5
    assert len(match["overlap"]) == 21
    assert match["dimensions"] == {
        "subjects": {"score": 40, "max": 40},
        "time": {"score": 25, "max": 25},
        "style": {"score": 15, "max": 15},
        "format": {"score": 10, "max": 10},
        "budget": {"score": 10, "max": 10},
    }
    assert len(match["reasons"]) == 3
    assert match["reasons"][0]["dimension"] == "subjects"
    assert match["reasons"][1]["dimension"] == "time"
    assert match["reasons"][2]["label"] == "Nearby"
    assert match["reasons"][2]["dimension"] == "format"

    profile = match["profile"]
    assert profile["id"] == tutor["user"]["id"]
    assert profile["role"] == "tutor"
    assert profile["name"] == "Amara Okonkwo"
    assert profile["display_name"] == "Amara Okonkwo"
    assert profile["public_location"]["label"] == "London"
    assert profile["distance_km"] == 0.0
    assert profile["distance_text"] == "less than 1 km away"
    assert "email" not in profile
    assert "password_hash" not in profile
    assert "birthdate" not in profile
    assert "area_id" not in profile
    assert "lives_in" not in profile
    assert "onboarding_complete" not in profile
    assert "completeness" not in profile


def test_matches_filters_narrow_without_reordering(
    client: TestClient,
) -> None:
    viewer = _register(
        client,
        email="filter-viewer@example.com",
        role="student",
        name="Maya Chen",
    )
    _complete(client, viewer, _student_payload())

    amara = _register(
        client,
        email="amara@example.com",
        role="tutor",
        name="Amara Okonkwo",
    )
    _complete(client, amara, _tutor_payload())

    dara = _register(
        client,
        email="dara@example.com",
        role="tutor",
        name="Dara Okafor",
    )
    _complete(
        client,
        dara,
        _tutor_payload(
            name="Dara Okafor",
            location_privacy="hidden",
        ),
    )

    ben = _register(
        client,
        email="ben@example.com",
        role="tutor",
        name="Ben Carter",
    )
    _complete(
        client,
        ben,
        _tutor_payload(
            name="Ben Carter",
            subjects=["Calculus"],
            style=TUTOR_STYLE_ALT,
            mode="online",
            budget=55,
            availability=_availability("Tue-Eve"),
            area_id="london-camden",
        ),
    )

    cleo = _register(
        client,
        email="cleo@example.com",
        role="tutor",
        name="Cleo Marsh",
    )
    _complete(
        client,
        cleo,
        _tutor_payload(
            name="Cleo Marsh",
            subjects=["Chemistry"],
            style="I teach by getting the student to build something",
            mode="in_person",
            budget=70,
            availability=_availability("Fri-Morn"),
            area_id="manchester-northern-quarter",
        ),
    )

    unfiltered = client.get("/matches", headers=_headers(viewer))
    all_ids = _match_ids(unfiltered)
    assert all_ids == [
        amara["user"]["id"],
        dara["user"]["id"],
        ben["user"]["id"],
        cleo["user"]["id"],
    ]
    assert unfiltered.json()["matches"][0]["score"] == 100
    assert unfiltered.json()["matches"][1]["score"] == 100
    assert unfiltered.json()["matches"][1]["profile"]["distance_km"] is None
    assert unfiltered.json()["matches"][1]["reasons"][2]["label"] != "Nearby"

    subject = client.get(
        "/matches",
        params={"subjects": "Physics"},
        headers=_headers(viewer),
    )
    assert _match_ids(subject) == [amara["user"]["id"], dara["user"]["id"]]

    mode = client.get(
        "/matches",
        params={"mode": "online"},
        headers=_headers(viewer),
    )
    assert _match_ids(mode) == [
        amara["user"]["id"],
        dara["user"]["id"],
        ben["user"]["id"],
    ]
    assert _match_ids(mode) == [
        candidate
        for candidate in all_ids
        if candidate in set(_match_ids(mode))
    ]

    rate = client.get(
        "/matches",
        params={"max_rate": 50},
        headers=_headers(viewer),
    )
    assert _match_ids(rate) == [amara["user"]["id"], dara["user"]["id"]]

    part = client.get(
        "/matches",
        params=[("required_parts", "0")],
        headers=_headers(viewer),
    )
    assert _match_ids(part) == [amara["user"]["id"], dara["user"]["id"]]

    overlap = client.get(
        "/matches",
        params={"must_be_free_when_i_am": "true"},
        headers=_headers(viewer),
    )
    assert _match_ids(overlap) == [
        amara["user"]["id"],
        dara["user"]["id"],
        ben["user"]["id"],
    ]

    distance = client.get(
        "/matches",
        params={"max_distance_km": 10},
        headers=_headers(viewer),
    )
    assert _match_ids(distance) == [
        amara["user"]["id"],
        ben["user"]["id"],
    ]

    score = client.get(
        "/matches",
        params={"min_score": 90},
        headers=_headers(viewer),
    )
    assert _match_ids(score) == [amara["user"]["id"], dara["user"]["id"]]

    empty = client.get(
        "/matches",
        params={"subjects": "Biology"},
        headers=_headers(viewer),
    )
    empty_body = empty.json()
    assert empty.status_code == 200
    assert empty_body["pool_size"] == 4
    assert empty_body["ranked_count"] == 0
    assert empty_body["matches"] == []
    assert empty_body["cold_start"] is None

    limited = client.get(
        "/matches",
        params={"limit": 2},
        headers=_headers(viewer),
    )
    limited_body = limited.json()
    assert limited.status_code == 200
    assert limited_body["ranked_count"] == 4
    assert limited_body["returned"] == 2
    assert _match_ids(limited) == all_ids[:2]


def test_tutor_viewer_ranks_students_with_the_same_weights(
    client: TestClient,
) -> None:
    tutor = _register(
        client,
        email="tutor-viewer@example.com",
        role="tutor",
        name="Amara Okonkwo",
    )
    _complete(client, tutor, _tutor_payload())

    student = _register(
        client,
        email="student@example.com",
        role="student",
        name="Maya Chen",
    )
    _complete(client, student, _student_payload())

    response = client.get("/matches", headers=_headers(tutor))
    body = response.json()

    assert response.status_code == 200
    assert body["viewer_role"] == "tutor"
    assert body["pool_size"] == 1
    match = body["matches"][0]
    assert match["profile"]["id"] == student["user"]["id"]
    assert match["profile"]["role"] == "student"
    assert match["score"] == 100
    assert match["reasons"][0]["detail"] == (
        "They need every subject you teach."
    )


def test_matches_reject_invalid_filters(client: TestClient) -> None:
    viewer = _register(
        client,
        email="invalid@example.com",
        role="student",
        name="Maya Chen",
    )
    _complete(client, viewer, _student_payload())
    headers = _headers(viewer)

    assert (
        client.get(
            "/matches",
            params={"subjects": "Underwater Basket Weaving"},
            headers=headers,
        ).status_code
        == 422
    )
    assert (
        client.get(
            "/matches",
            params={"max_rate": 81},
            headers=headers,
        ).status_code
        == 422
    )
    assert (
        client.get(
            "/matches",
            params=[("required_parts", "3")],
            headers=headers,
        ).status_code
        == 422
    )
    assert (
        client.get(
            "/matches",
            params={"limit": 0},
            headers=headers,
        ).status_code
        == 422
    )
