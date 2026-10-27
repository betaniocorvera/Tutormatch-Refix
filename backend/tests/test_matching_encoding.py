from __future__ import annotations

import math

import pytest

from app.models.matching import MatchDimension, MatchTier
from app.models.profile import SessionMode
from app.models.user import Role
from app.services.matching import (
    DIMENSION_ORDER,
    DIMENSION_WEIGHTS,
    describe_overlap,
    disagreement_vector,
    budget_fit,
    format_fit,
    score_from_distance,
    style_fit,
    subject_fit,
    tier_for,
    time_fit,
)


def _overlap(*slots: int) -> list[bool]:
    grid = [False] * 21
    for slot in slots:
        grid[slot] = True
    return grid


def test_subject_fit_measures_student_coverage_not_tutor_catalogue_size() -> None:
    assert subject_fit(["Calculus"], ["Calculus", "Physics", "Algebra"]) == 40
    assert subject_fit(["Calculus", "Physics"], ["Calculus", "Physics"]) == 40
    assert subject_fit(
        ["Calculus", "Physics", "Algebra"],
        ["Calculus", "Physics"],
    ) == 27
    assert subject_fit(["Calculus", "Physics"], ["Chemistry"]) == 0
    assert subject_fit([], ["Calculus"]) == 0


def test_time_fit_matches_the_flutter_five_block_ceiling() -> None:
    assert time_fit(_overlap()) == 0
    assert time_fit(_overlap(0)) == 5
    assert time_fit(_overlap(0, 1)) == 10
    assert time_fit(_overlap(0, 1, 2)) == 15
    assert time_fit(_overlap(0, 1, 2, 3)) == 20
    assert time_fit(_overlap(0, 1, 2, 3, 4)) == 25
    assert time_fit(_overlap(0, 1, 2, 3, 4, 5, 6)) == 25


def test_style_fit_falls_off_along_the_ordered_catalogue() -> None:
    assert style_fit(0, 0) == 15
    assert style_fit(0, 1) == 11
    assert style_fit(0, 2) == 8
    assert style_fit(0, 3) == 4
    assert style_fit(0, 4) == 0
    assert style_fit(-1, 2) == 0
    assert style_fit(0, 9) == 0


def test_format_fit_allows_either_side_to_be_flexible() -> None:
    assert format_fit(SessionMode.online, SessionMode.online) == 10
    assert format_fit(SessionMode.in_person, SessionMode.in_person) == 10
    assert format_fit(SessionMode.both, SessionMode.both) == 10
    assert format_fit(SessionMode.online, SessionMode.both) == 10
    assert format_fit(SessionMode.both, SessionMode.in_person) == 10
    assert format_fit(SessionMode.online, SessionMode.in_person) == 0


def test_budget_fit_reads_the_students_ceiling_and_the_tutors_rate() -> None:
    assert budget_fit(Role.student, 50, 46) == 10
    assert budget_fit(Role.student, 50, 50) == 10
    assert budget_fit(Role.student, 50, 52) == 9
    assert budget_fit(Role.student, 50, 58) == 6
    assert budget_fit(Role.student, 50, 60) == 5
    assert budget_fit(Role.student, 50, 70) == 0
    assert budget_fit(Role.tutor, 46, 50) == 10
    assert budget_fit(Role.tutor, 52, 50) == 9
    assert budget_fit(Role.tutor, 70, 50) == 0


def test_tier_thresholds_are_the_product_copy_thresholds() -> None:
    assert tier_for(100) is MatchTier.strong
    assert tier_for(80) is MatchTier.strong
    assert tier_for(79) is MatchTier.good
    assert tier_for(60) is MatchTier.good
    assert tier_for(59) is MatchTier.possible
    assert tier_for(40) is MatchTier.possible
    assert tier_for(39) is MatchTier.weak
    assert tier_for(0) is MatchTier.weak


def test_describe_overlap_names_days_and_parts() -> None:
    assert describe_overlap(_overlap()) is None
    assert describe_overlap(_overlap(2)) == "Monday evenings"
    assert describe_overlap(_overlap(0, 2)) == "Monday at various times"
    assert describe_overlap(_overlap(2, 5)) == "Monday and Tuesday evenings"
    assert (
        describe_overlap(_overlap(0, 3, 6))
        == "Monday, Tuesday and Wednesday mornings"
    )
    assert (
        describe_overlap(_overlap(0, 3, 6, 8))
        == "Monday, Tuesday and Wednesday at various times"
    )


def test_disagreement_embedding_loses_exactly_the_missing_points() -> None:
    dimensions = {
        MatchDimension.subjects: 40,
        MatchDimension.time: 20,
        MatchDimension.style: 15,
        MatchDimension.format: 10,
        MatchDimension.budget: 10,
    }
    vector = disagreement_vector(dimensions)
    distance = math.sqrt(sum(component * component for component in vector))
    assert distance == pytest.approx(math.sqrt(5.0))
    assert score_from_distance(distance) == sum(dimensions.values())

    perfect = {dimension: DIMENSION_WEIGHTS[dimension] for dimension in DIMENSION_ORDER}
    perfect_vector = disagreement_vector(perfect)
    assert perfect_vector == [0.0] * len(DIMENSION_ORDER)
    assert score_from_distance(0.0) == 100


def test_score_conversion_is_clamped_to_the_product_range() -> None:
    assert score_from_distance(0.0) == 100
    assert score_from_distance(10.0) == 0
    assert score_from_distance(20.0) == 0
    assert score_from_distance(-1.0) == 100
