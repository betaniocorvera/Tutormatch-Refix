from __future__ import annotations

from datetime import date

from fastapi.testclient import TestClient

from app.services.profile import age_on


def _register(
    client: TestClient,
    *,
    email: str = "student@example.com",
    role: str = "student",
    display_name: str = "Maya Chen",
) -> dict:
    response = client.post(
        "/auth/register",
        json={
            "email": email,
            "password": "correct horse battery",
            "role": role,
            "display_name": display_name,
        },
    )
    assert response.status_code == 201
    return response.json()


def _headers(tokens: dict) -> dict[str, str]:
    return {"Authorization": f"Bearer {tokens['access_token']}"}


def _student_payload(**overrides) -> dict:
    payload = {
        "name": "Maya Chen",
        "subjects": ["Calculus", "Physics"],
        "style": "Watch one worked example, then do the next one myself",
        "mode": "both",
        "budget": 50,
        "availability": [True] + [False] * 20,
        "goal": "Move up a grade or two this year",
        "birthdate": "2009-03-14",
        "area_id": "london-highbury",
        "location_privacy": "city_only",
        "status_text": "Mocks in eleven weeks",
        "presence": "available",
        "bio": "I like to work through examples.",
        "gender": "Female",
        "languages": ["English", "Mandarin"],
        "years": None,
        "education": "",
        "grade": "Year 12",
    }
    payload.update(overrides)
    return payload


def _tutor_payload(**overrides) -> dict:
    payload = {
        "name": "Amara Okonkwo",
        "subjects": ["Calculus", "Statistics", "Algebra"],
        "style": "I work through examples slowly and let the student steer",
        "mode": "both",
        "budget": 46,
        "availability": [True, False, True] + [False] * 18,
        "goal": "Fill a few steady evenings a week",
        "birthdate": "1991-06-02",
        "area_id": "manchester-northern-quarter",
        "location_privacy": "city_only",
        "status_text": "Open for sessions",
        "presence": "available",
        "bio": "Nine years of teaching mathematics.",
        "gender": "Female",
        "languages": ["English", "Igbo"],
        "years": 9,
        "education": "MSc Mathematics, Manchester",
        "grade": "",
    }
    payload.update(overrides)
    return payload


def test_profile_endpoints_require_authentication(client: TestClient) -> None:
    assert client.get("/profile").status_code == 401
    assert client.put("/profile", json={}).status_code == 401
    assert client.put("/profile/subjects", json={"subjects": []}).status_code == 401
    assert (
        client.put(
            "/profile/availability",
            json={"availability": [False] * 21},
        ).status_code
        == 401
    )
    assert (
        client.post(
            "/profile/photo",
            files={"file": ("photo.png", b"not-an-image", "image/png")},
        ).status_code
        == 401
    )


def test_get_profile_returns_defaults_for_a_new_account(
    client: TestClient,
) -> None:
    tokens = _register(client)

    response = client.get("/profile", headers=_headers(tokens))

    assert response.status_code == 200
    body = response.json()
    assert body["user_id"] == tokens["user"]["id"]
    assert body["role"] == "student"
    assert body["name"] == "Maya Chen"
    assert body["subjects"] == []
    assert body["style"] == ""
    assert body["mode"] == "both"
    assert body["budget"] == 0
    assert body["availability"] == [False] * 21
    assert body["goal"] == ""
    assert body["age"] is None
    assert body["birthdate"] is None
    assert body["lives_in"] == ""
    assert body["area_id"] == ""
    assert body["location_privacy"] == "city_only"
    assert body["public_location"] is None
    assert body["photo_url"] is None
    assert body["gender"] == "Prefer not to say"
    assert body["onboarding_complete"] is False
    assert body["completeness"]["filled"] == 1
    assert body["completeness"]["total"] == 12
    assert "a picture" in body["completeness"]["missing"]
    assert "email" not in body
    assert "password_hash" not in body


def test_put_profile_updates_answers_and_derived_fields(
    client: TestClient,
) -> None:
    tokens = _register(client)

    response = client.put(
        "/profile",
        json=_student_payload(),
        headers=_headers(tokens),
    )

    assert response.status_code == 200
    body = response.json()
    assert body["name"] == "Maya Chen"
    assert body["subjects"] == ["Calculus", "Physics"]
    assert body["style"] == (
        "Watch one worked example, then do the next one myself"
    )
    assert body["mode"] == "both"
    assert body["budget"] == 50
    assert body["availability"] == [True] + [False] * 20
    assert body["goal"] == "Move up a grade or two this year"
    assert body["age"] == age_on(date(2009, 3, 14), date.today())
    assert body["birthdate"] == "2009-03-14"
    assert body["lives_in"] == "Highbury, London"
    assert body["area_id"] == "london-highbury"
    assert body["location_privacy"] == "city_only"
    assert body["public_location"] == {
        "label": "London",
        "city": "London",
        "region": "Greater London",
        "latitude": 51.5072,
        "longitude": -0.1276,
        "city_only": True,
    }
    assert body["status_text"] == "Mocks in eleven weeks"
    assert body["presence"] == "available"
    assert body["bio"] == "I like to work through examples."
    assert body["gender"] == "Female"
    assert body["languages"] == ["English", "Mandarin"]
    assert body["years"] is None
    assert body["education"] == ""
    assert body["grade"] == "Year 12"
    assert body["completeness"] == {
        "filled": 11,
        "total": 12,
        "fraction": 0.9167,
        "missing": ["a picture"],
    }
    assert body["onboarding_complete"] is True

    me = client.get("/auth/me", headers=_headers(tokens))
    assert me.status_code == 200
    assert me.json()["display_name"] == "Maya Chen"
    assert me.json()["onboarding_complete"] is True

    again = client.get("/profile", headers=_headers(tokens))
    assert again.status_code == 200
    assert again.json()["subjects"] == ["Calculus", "Physics"]


def test_put_profile_is_partial_and_preserves_omitted_fields(
    client: TestClient,
) -> None:
    tokens = _register(client)

    first = client.put(
        "/profile",
        json={"subjects": ["Calculus"]},
        headers=_headers(tokens),
    )
    assert first.status_code == 200
    body = first.json()
    assert body["name"] == "Maya Chen"
    assert body["subjects"] == ["Calculus"]
    assert body["budget"] == 0
    assert body["availability"] == [False] * 21
    assert body["onboarding_complete"] is False

    second = client.put(
        "/profile",
        json={"name": "  Maya C  "},
        headers=_headers(tokens),
    )
    assert second.status_code == 200
    assert second.json()["name"] == "Maya C"
    assert second.json()["subjects"] == ["Calculus"]

    me = client.get("/auth/me", headers=_headers(tokens))
    assert me.json()["display_name"] == "Maya C"


def test_explicit_null_clears_nullable_profile_fields(
    client: TestClient,
) -> None:
    tokens = _register(client)
    headers = _headers(tokens)
    payload = _student_payload(years=5)
    assert client.put("/profile", json=payload, headers=headers).status_code == 200

    response = client.put(
        "/profile",
        json={"birthdate": None, "area_id": None, "years": None},
        headers=headers,
    )

    assert response.status_code == 200
    body = response.json()
    assert body["birthdate"] is None
    assert body["age"] is None
    assert body["area_id"] == ""
    assert body["lives_in"] == ""
    assert body["public_location"] is None
    assert body["years"] is None


def test_subjects_endpoint_validates_the_catalogue(
    client: TestClient,
) -> None:
    tokens = _register(client)
    headers = _headers(tokens)

    valid = client.put(
        "/profile/subjects",
        json={"subjects": ["calculus", "PHYSICS"]},
        headers=headers,
    )
    assert valid.status_code == 200
    assert valid.json()["subjects"] == ["Calculus", "Physics"]

    unknown = client.put(
        "/profile/subjects",
        json={"subjects": ["Underwater Basket Weaving"]},
        headers=headers,
    )
    assert unknown.status_code == 422

    duplicate = client.put(
        "/profile/subjects",
        json={"subjects": ["Calculus", "calculus"]},
        headers=headers,
    )
    assert duplicate.status_code == 422

    too_many = client.put(
        "/profile/subjects",
        json={
            "subjects": [
                "Algebra",
                "Geometry",
                "Calculus",
                "Physics",
                "Chemistry",
            ]
        },
        headers=headers,
    )
    assert too_many.status_code == 422


def test_availability_endpoint_requires_twenty_one_slots(
    client: TestClient,
) -> None:
    tokens = _register(client)
    headers = _headers(tokens)

    too_short = client.put(
        "/profile/availability",
        json={"availability": [True] * 20},
        headers=headers,
    )
    assert too_short.status_code == 422

    week = [False] * 21
    week[2] = True
    valid = client.put(
        "/profile/availability",
        json={"availability": week},
        headers=headers,
    )
    assert valid.status_code == 200
    assert valid.json()["availability"] == week


def test_style_and_goal_are_validated_against_the_role(
    client: TestClient,
) -> None:
    tokens = _register(
        client,
        email="tutor@example.com",
        role="tutor",
        display_name="Amara Okonkwo",
    )
    headers = _headers(tokens)

    assert (
        client.put(
            "/profile",
            json={
                "style": "I work through examples slowly and let the student steer",
                "goal": "Fill a few steady evenings a week",
            },
            headers=headers,
        ).status_code
        == 200
    )

    student_style = client.put(
        "/profile",
        json={"style": "Watch one worked example, then do the next one myself"},
        headers=headers,
    )
    assert student_style.status_code == 422

    student_goal = client.put(
        "/profile",
        json={"goal": "Move up a grade or two this year"},
        headers=headers,
    )
    assert student_goal.status_code == 422


def test_profile_rejects_invalid_values(client: TestClient) -> None:
    tokens = _register(client)
    headers = _headers(tokens)

    assert (
        client.put(
            "/profile",
            json={"area_id": "not-a-real-area"},
            headers=headers,
        ).status_code
        == 422
    )
    assert (
        client.put(
            "/profile",
            json={"birthdate": "2999-01-01"},
            headers=headers,
        ).status_code
        == 422
    )
    assert (
        client.put(
            "/profile",
            json={"birthdate": "1800-01-01"},
            headers=headers,
        ).status_code
        == 422
    )
    assert (
        client.put(
            "/profile",
            json={"languages": ["Klingon"]},
            headers=headers,
        ).status_code
        == 422
    )
    assert (
        client.put(
            "/profile",
            json={"gender": "Unknown"},
            headers=headers,
        ).status_code
        == 422
    )
    assert (
        client.put(
            "/profile",
            json={"budget": 81},
            headers=headers,
        ).status_code
        == 422
    )
    assert (
        client.put(
            "/profile",
            json={"not_a_profile_field": True},
            headers=headers,
        ).status_code
        == 422
    )


def test_public_profile_is_privacy_safe_and_derives_age_and_distance(
    client: TestClient,
) -> None:
    viewer = _register(
        client,
        email="viewer@example.com",
        display_name="Viewer Student",
    )
    target = _register(
        client,
        email="target@example.com",
        role="tutor",
        display_name="Amara Okonkwo",
    )
    viewer_headers = _headers(viewer)
    target_headers = _headers(target)

    assert (
        client.put(
            "/profile",
            json={"area_id": "london-camden", "location_privacy": "area"},
            headers=viewer_headers,
        ).status_code
        == 200
    )
    assert (
        client.put(
            "/profile",
            json=_tutor_payload(
                area_id="london-highbury",
                location_privacy="city_only",
            ),
            headers=target_headers,
        ).status_code
        == 200
    )

    response = client.get(
        f"/users/{target['user']['id']}",
        headers=viewer_headers,
    )

    assert response.status_code == 200
    body = response.json()
    assert body["id"] == target["user"]["id"]
    assert body["role"] == "tutor"
    assert body["display_name"] == "Amara Okonkwo"
    assert body["name"] == "Amara Okonkwo"
    assert body["age"] == age_on(date(1991, 6, 2), date.today())
    assert body["public_location"]["label"] == "London"
    assert body["public_location"]["city_only"] is True
    assert body["public_location"]["latitude"] == 51.5072
    assert body["distance_km"] is not None
    assert 1 < body["distance_km"] < 10
    assert body["distance_text"].endswith("km away")
    assert body["subjects"] == ["Calculus", "Statistics", "Algebra"]
    assert body["style"] == (
        "I work through examples slowly and let the student steer"
    )
    assert body["mode"] == "both"
    assert body["budget"] == 46
    assert body["availability"] == [True, False, True] + [False] * 18
    assert body["years"] == 9
    assert body["education"] == "MSc Mathematics, Manchester"

    for private in (
        "email",
        "password_hash",
        "birthdate",
        "area_id",
        "lives_in",
        "onboarding_complete",
        "completeness",
    ):
        assert private not in body


def test_area_privacy_shows_the_neighbourhood_not_just_the_city(
    client: TestClient,
) -> None:
    viewer = _register(client, email="viewer@example.com")
    target = _register(
        client,
        email="target@example.com",
        role="tutor",
        display_name="Amara Okonkwo",
    )
    assert (
        client.put(
            "/profile",
            json=_tutor_payload(location_privacy="area"),
            headers=_headers(target),
        ).status_code
        == 200
    )

    response = client.get(
        f"/users/{target['user']['id']}",
        headers=_headers(viewer),
    )

    assert response.status_code == 200
    location = response.json()["public_location"]
    assert location["label"] == "Northern Quarter, Manchester"
    assert location["city"] == "Manchester"
    assert location["city_only"] is False
    assert location["latitude"] == 53.4837
    assert location["longitude"] == -2.2346


def test_hidden_location_removes_public_location_and_distance(
    client: TestClient,
) -> None:
    viewer = _register(client, email="viewer@example.com")
    target = _register(
        client,
        email="target@example.com",
        role="tutor",
        display_name="Amara Okonkwo",
    )
    assert (
        client.put(
            "/profile",
            json=_tutor_payload(location_privacy="hidden"),
            headers=_headers(target),
        ).status_code
        == 200
    )

    response = client.get(
        f"/users/{target['user']['id']}",
        headers=_headers(viewer),
    )

    assert response.status_code == 200
    assert response.json()["public_location"] is None
    assert response.json()["distance_km"] is None
    assert response.json()["distance_text"] is None


def test_a_hidden_viewer_gets_no_distance_but_still_sees_the_public_area(
    client: TestClient,
) -> None:
    viewer = _register(client, email="viewer@example.com")
    target = _register(
        client,
        email="target@example.com",
        role="tutor",
        display_name="Amara Okonkwo",
    )
    assert (
        client.put(
            "/profile",
            json={"area_id": "london-camden", "location_privacy": "hidden"},
            headers=_headers(viewer),
        ).status_code
        == 200
    )
    assert (
        client.put(
            "/profile",
            json=_tutor_payload(location_privacy="area"),
            headers=_headers(target),
        ).status_code
        == 200
    )

    response = client.get(
        f"/users/{target['user']['id']}",
        headers=_headers(viewer),
    )

    assert response.status_code == 200
    body = response.json()
    assert body["public_location"]["label"] == "Northern Quarter, Manchester"
    assert body["distance_km"] is None
    assert body["distance_text"] is None


def test_a_viewer_without_an_area_gets_no_distance(
    client: TestClient,
) -> None:
    viewer = _register(client, email="viewer@example.com")
    target = _register(
        client,
        email="target@example.com",
        role="tutor",
        display_name="Amara Okonkwo",
    )
    assert (
        client.put(
            "/profile",
            json=_tutor_payload(location_privacy="area"),
            headers=_headers(target),
        ).status_code
        == 200
    )

    response = client.get(
        f"/users/{target['user']['id']}",
        headers=_headers(viewer),
    )

    assert response.status_code == 200
    assert response.json()["distance_km"] is None
