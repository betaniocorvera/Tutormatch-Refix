from __future__ import annotations

from fastapi.testclient import TestClient

from app.catalog import get_catalog
from app.models.user import Role


def test_catalogue_comes_from_static_data_files() -> None:
    catalog = get_catalog()

    assert len(catalog.regions) == 18
    assert len(catalog.cities) == 18
    assert len(catalog.areas) == 22
    assert len(catalog.subjects) == 14

    highbury = catalog.area("london-highbury")
    assert highbury is not None
    assert highbury.label == "Highbury, London"
    assert highbury.city == "London"
    assert highbury.region == "Greater London"
    assert catalog.canonical_subject(" calculus ") == "Calculus"
    assert catalog.canonical_subject("sat-prep") == "SAT Prep"
    assert catalog.canonical_language("english") == "English"
    assert catalog.canonical_style(Role.student, "not a style") is None


def test_area_lookup_has_the_region_city_area_picker_shape(
    client: TestClient,
) -> None:
    response = client.get("/areas")

    assert response.status_code == 200
    body = response.json()
    assert "Greater London" in body["regions"]
    london = next(city for city in body["cities"] if city["id"] == "london")
    assert london["name"] == "London"
    assert london["region"] == "Greater London"
    highbury = next(
        area for area in body["areas"] if area["id"] == "london-highbury"
    )
    assert highbury["label"] == "Highbury, London"
    assert highbury["city_id"] == "london"


def test_subject_lookup_returns_the_canonical_names(
    client: TestClient,
) -> None:
    response = client.get("/subjects")

    assert response.status_code == 200
    names = [subject["name"] for subject in response.json()["subjects"]]
    assert names == [
        "Algebra",
        "Geometry",
        "Calculus",
        "Statistics",
        "Physics",
        "Chemistry",
        "Biology",
        "English Literature",
        "Essay Writing",
        "History",
        "Spanish",
        "Computer Science",
        "Music Theory",
        "SAT Prep",
    ]
