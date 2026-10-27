from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

from app.catalog import get_catalog
from app.models.profile import LocationPrivacy, Profile, SessionMode
from app.models.user import Role
from app.services.matching import (
    CandidateProfile,
    MatchEngine,
    MatchFilters,
)

_DATA_PATH = Path(__file__).parent / "data" / "matching_eval.json"
_FIXED_TIME = datetime(2026, 1, 1, tzinfo=timezone.utc)
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


def _availability(slots: list[str]) -> list[bool]:
    grid = [False] * 21
    for slot in slots:
        day, part = slot.split("-")
        grid[_DAYS[day] * 3 + _PARTS[part]] = True
    return grid


def _profile(seed: dict, catalog) -> Profile:
    role = Role(seed["role"])
    styles = catalog.style_options(role)
    return Profile(
        user_id=seed["id"],
        name=seed["name"],
        subjects=list(seed["subjects"]),
        style=styles[int(seed["style_index"])],
        mode=SessionMode(seed["mode"]),
        budget=int(seed["budget"]),
        availability=_availability(seed["availability"]),
        goal=seed["goal"],
        area_id=seed["area_id"],
        location_privacy=LocationPrivacy.city_only,
        updated_at=_FIXED_TIME,
    )


def _load_evaluation() -> dict:
    return json.loads(_DATA_PATH.read_text(encoding="utf-8"))


def test_labeled_precision_at_five_meets_the_matching_bar() -> None:
    """A small hand-labelled evaluation of the ranking, not a popularity test.

    A tutor is labelled relevant for a student when the tutor covers every
    requested subject, the format is compatible, the rate is at or under the
    ceiling, and the two share at least two weekly slots. Style is deliberately
    left out of the label so it can still cost a relevant person points and
    make the metric less than perfect.
    """

    data = _load_evaluation()
    catalog = get_catalog()
    engine = MatchEngine(catalog)

    candidates = [
        CandidateProfile(
            id=seed["id"],
            role=Role(seed["role"]),
            profile=_profile(seed, catalog),
        )
        for seed in data["candidates"]
    ]
    candidate_ids = {candidate.id for candidate in candidates}

    precisions: list[float] = []
    details: list[str] = []
    for viewer_seed in data["viewers"]:
        viewer_id = viewer_seed["id"]
        relevant = set(data["labels"][viewer_id])
        assert len(relevant) >= 5
        assert relevant <= candidate_ids

        viewer_profile = _profile(viewer_seed, catalog)
        ranked = engine.rank(
            Role(viewer_seed["role"]),
            viewer_profile,
            candidates,
            MatchFilters(),
        )
        top_five = [candidate.candidate.id for candidate in ranked[:5]]
        assert len(top_five) == 5
        hits = len(set(top_five) & relevant)
        precision = hits / 5
        precisions.append(precision)
        details.append(
            f"{viewer_id}: {hits}/5 relevant; top five {top_five}"
        )

    average = sum(precisions) / len(precisions)
    assert average >= 0.8, "\n".join(details)
    assert min(precisions) >= 0.8, "\n".join(details)
