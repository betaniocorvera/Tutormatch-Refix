"""Weighted KNN matching.

The five feature groups and their weights are product constants, not tuning
knobs: subjects 40, available time 25, style 15, format 10, budget 10. Each
group is scored as an integer number of points, and the total is their sum.

KNN uses a five-dimensional disagreement embedding. A candidate's coordinate
for a group is ``sqrt(weight - group_score)``; the viewer is the origin. The
squared Euclidean distance is therefore exactly the number of points the
candidate failed to earn, which makes the distance-to-score conversion exact:

    distance^2 = sum(weight - group_score) = 100 - total
    score      = round(100 - distance^2)  = total

NearestNeighbors is used over the already-filtered candidate pool. Hard filters
are applied before the KNN query so the ranking never contains a person the
caller asked to exclude.
"""

from __future__ import annotations

import math
from collections.abc import Iterable, Sequence
from dataclasses import dataclass, replace

import numpy as np
from sklearn.neighbors import NearestNeighbors

from ..catalog import Catalog
from ..errors import InvalidMatchFilters
from ..models.matching import (
    TIER_LABELS,
    ColdStart,
    DimensionScore,
    MatchDimension,
    MatchDimensions,
    MatchList,
    MatchReason,
    MatchResult,
    MatchTier,
)
from ..models.profile import (
    AVAILABILITY_CELLS,
    Profile,
    PublicProfile,
    SessionMode,
)
from ..models.user import Role, User
from ..repositories.interfaces import ProfileRepository, UserRepository
from .profile import ProfileService

DIMENSION_ORDER: tuple[MatchDimension, ...] = (
    MatchDimension.subjects,
    MatchDimension.time,
    MatchDimension.style,
    MatchDimension.format,
    MatchDimension.budget,
)

DIMENSION_WEIGHTS: dict[MatchDimension, int] = {
    MatchDimension.subjects: 40,
    MatchDimension.time: 25,
    MatchDimension.style: 15,
    MatchDimension.format: 10,
    MatchDimension.budget: 10,
}

DIMENSION_LABELS: dict[MatchDimension, str] = {
    MatchDimension.subjects: "Subjects",
    MatchDimension.time: "Available time",
    MatchDimension.style: "Style",
    MatchDimension.format: "Online or in person",
    MatchDimension.budget: "Budget",
}

# The style catalogues are ordered from structured to exploratory. That order
# is the only similarity axis available, so adjacent approaches receive more
# credit than opposite ones.
STYLE_LABELS: tuple[str, ...] = (
    "Worked examples",
    "First principles",
    "Discussion",
    "Timed practice",
    "Building",
)

BUDGET_TOLERANCE = 20
NEARBY_DISTANCE_KM = 5.0
_DAY_NAMES = (
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
    "Sunday",
)
_PART_NAMES = ("mornings", "afternoons", "evenings")


@dataclass(frozen=True)
class MatchFilters:
    """Hard filters applied before KNN.

    The defaults mean "do not narrow": no subject, any mode, any rate, any
    time, any distance, and any score. The router maps absent query parameters
    to these defaults.
    """

    subjects: tuple[str, ...] = ()
    mode: SessionMode | None = None
    max_rate: int | None = None
    required_parts: frozenset[int] = frozenset()
    must_be_free_when_i_am: bool = False
    max_distance_km: int | None = None
    min_score: int | None = None


@dataclass(frozen=True)
class CandidateProfile:
    """A counterpart and the profile answers the ranker needs."""

    id: str
    role: Role
    profile: Profile
    distance_km: float | None = None


@dataclass(frozen=True)
class ScoredCandidate:
    candidate: CandidateProfile
    dimensions: dict[MatchDimension, int]
    overlap: list[bool]
    total: int
    distance_km: float | None

    @property
    def overlap_slots(self) -> int:
        return sum(1 for cell in self.overlap if cell)


def _round_half_up(value: float) -> int:
    """Round non-negative scores the way the product copy expects."""

    return int(math.floor(value + 0.5))


def _natural_join(items: Sequence[str]) -> str:
    values = [item for item in items if item]
    if not values:
        return ""
    if len(values) == 1:
        return values[0]
    if len(values) == 2:
        return f"{values[0]} and {values[1]}"
    return f"{', '.join(values[:-1])} and {values[-1]}"


def subject_fit(needs: Sequence[str], offers: Sequence[str]) -> int:
    """Points for how much of the student's need the tutor covers.

    Extra subjects on the tutor's side do not hurt: a tutor who teaches the one
    subject a student needs is a full subject match. The denominator is the
    student's requested set, not the union.
    """

    need_set = {subject.casefold() for subject in needs}
    offer_set = {subject.casefold() for subject in offers}
    if not need_set or not offer_set:
        return 0
    overlap = len(need_set & offer_set)
    if overlap == 0:
        return 0
    return min(40, _round_half_up(40 * overlap / len(need_set)))


def time_fit(overlap: Sequence[bool]) -> int:
    """The Flutter formula: five shared cells is full marks, then linear."""

    slots = sum(1 for cell in overlap if cell)
    return min(25, (slots * 25) // 5)


def style_fit(viewer_index: int, candidate_index: int) -> int:
    """Style credit falls off with distance along the ordered catalogue."""

    if not (0 <= viewer_index < len(STYLE_LABELS)):
        return 0
    if not (0 <= candidate_index < len(STYLE_LABELS)):
        return 0
    distance = abs(viewer_index - candidate_index)
    return max(0, _round_half_up(15 * (1 - distance / 4)))


def format_fit(viewer_mode: SessionMode, candidate_mode: SessionMode) -> int:
    """Either side choosing "both" accepts the other's format."""

    if (
        viewer_mode == candidate_mode
        or viewer_mode == SessionMode.both
        or candidate_mode == SessionMode.both
    ):
        return 10
    return 0


def budget_fit(
    viewer_role: Role,
    viewer_budget: int,
    candidate_budget: int,
) -> int:
    """Affordability, with a $20 overage losing all budget points.

    A student's ``budget`` is a ceiling; a tutor's ``budget`` is an hourly
    rate. The rate is whichever side is the tutor.
    """

    if viewer_budget <= 0 or candidate_budget <= 0:
        return 0

    if viewer_role == Role.student:
        rate, ceiling = candidate_budget, viewer_budget
    else:
        rate, ceiling = viewer_budget, candidate_budget

    if rate <= ceiling:
        return 10
    gap = rate - ceiling
    return max(0, _round_half_up(10 * (1 - gap / BUDGET_TOLERANCE)))


def overlap_of(
    viewer_availability: Sequence[bool],
    candidate_availability: Sequence[bool],
) -> list[bool]:
    return [
        bool(left and right)
        for left, right in zip(viewer_availability, candidate_availability)
    ]


def describe_overlap(overlap: Sequence[bool]) -> str | None:
    """Human sentence for an overlap grid, or None when there is no overlap."""

    if len(overlap) < AVAILABILITY_CELLS or not any(overlap):
        return None

    days: list[str] = []
    parts: set[str] = set()
    for day in range(7):
        hits = [
            part
            for part in range(3)
            if overlap[day * 3 + part]
        ]
        if not hits:
            continue
        days.append(_DAY_NAMES[day])
        parts.update(_PART_NAMES[part] for part in hits)

    if len(days) == 1:
        days_text = days[0]
    elif len(days) == 2:
        days_text = f"{days[0]} and {days[1]}"
    else:
        days_text = f"{', '.join(days[:-1])} and {days[-1]}"
    parts_text = next(iter(parts)) if len(parts) == 1 else "at various times"
    return f"{days_text} {parts_text}"


def describe_distance(km: float) -> str:
    if km < 1:
        return "less than 1 km away"
    return f"about {_round_half_up(km)} km away"


def tier_for(score: int) -> MatchTier:
    if score >= 80:
        return MatchTier.strong
    if score >= 60:
        return MatchTier.good
    if score >= 40:
        return MatchTier.possible
    return MatchTier.weak


def disagreement_vector(
    dimensions: dict[MatchDimension, int],
) -> list[float]:
    """The five coordinates whose squared length is the points lost."""

    return [
        math.sqrt(max(0.0, float(DIMENSION_WEIGHTS[dimension] - dimensions[dimension])))
        for dimension in DIMENSION_ORDER
    ]


def score_from_distance(distance: float) -> int:
    """Convert a KNN Euclidean distance back to the 0-100 match score.

    A distance is a length, so negative input is clamped to zero rather than
    being squared into a positive value. Distances above 10 lose every point.
    """

    bounded = min(10.0, max(0.0, distance))
    return max(0, min(100, _round_half_up(100.0 - bounded * bounded)))


def _mode_accepts(
    requested: SessionMode,
    offered: SessionMode,
) -> bool:
    return (
        requested == offered
        or requested == SessionMode.both
        or offered == SessionMode.both
    )


class MatchEngine:
    """Pure scoring and ranking, independent of repositories and HTTP."""

    def __init__(self, catalog: Catalog) -> None:
        self._catalog = catalog

    def style_index(self, role: Role, style: str) -> int:
        try:
            return self._catalog.style_options(role).index(style)
        except ValueError:
            return -1

    def missing_answers(self, profile: Profile) -> list[str]:
        missing: list[str] = []
        if not profile.subjects:
            missing.append("subjects")
        if not profile.style.strip():
            missing.append("style")
        if not any(profile.availability):
            missing.append("availability")
        if not profile.goal.strip():
            missing.append("goal")
        if profile.budget <= 0:
            missing.append("budget")
        return missing

    def is_matchable(self, profile: Profile) -> bool:
        return not self.missing_answers(profile)

    def score(
        self,
        viewer_role: Role,
        viewer_profile: Profile,
        candidate: CandidateProfile,
    ) -> ScoredCandidate:
        overlap = overlap_of(
            viewer_profile.availability,
            candidate.profile.availability,
        )

        if viewer_role == Role.student:
            needs = viewer_profile.subjects
            offers = candidate.profile.subjects
        else:
            needs = candidate.profile.subjects
            offers = viewer_profile.subjects

        dimensions = {
            MatchDimension.subjects: subject_fit(needs, offers),
            MatchDimension.time: time_fit(overlap),
            MatchDimension.style: style_fit(
                self.style_index(viewer_role, viewer_profile.style),
                self.style_index(candidate.role, candidate.profile.style),
            ),
            MatchDimension.format: format_fit(
                viewer_profile.mode,
                candidate.profile.mode,
            ),
            MatchDimension.budget: budget_fit(
                viewer_role,
                viewer_profile.budget,
                candidate.profile.budget,
            ),
        }
        return ScoredCandidate(
            candidate=candidate,
            dimensions=dimensions,
            overlap=overlap,
            total=sum(dimensions.values()),
            distance_km=candidate.distance_km,
        )

    def rank(
        self,
        viewer_role: Role,
        viewer_profile: Profile,
        candidates: Iterable[CandidateProfile],
        filters: MatchFilters | None = None,
    ) -> list[ScoredCandidate]:
        resolved_filters = filters or MatchFilters()
        scored = [
            self.score(viewer_role, viewer_profile, candidate)
            for candidate in candidates
        ]
        filtered = [
            candidate
            for candidate in scored
            if self._passes(candidate, resolved_filters)
        ]
        if not filtered:
            return []
        return self._knn_order(filtered)

    def _passes(
        self,
        scored: ScoredCandidate,
        filters: MatchFilters,
    ) -> bool:
        candidate = scored.candidate

        if filters.subjects:
            candidate_subjects = {
                subject.casefold()
                for subject in candidate.profile.subjects
            }
            if not any(
                subject.casefold() in candidate_subjects
                for subject in filters.subjects
            ):
                return False

        if (
            filters.mode is not None
            and not _mode_accepts(filters.mode, candidate.profile.mode)
        ):
            return False

        if (
            filters.max_rate is not None
            and candidate.profile.budget > filters.max_rate
        ):
            return False

        if filters.required_parts:
            has_required_part = any(
                scored.overlap[day * 3 + part]
                for part in filters.required_parts
                for day in range(7)
            )
            if not has_required_part:
                return False

        if filters.must_be_free_when_i_am and scored.overlap_slots == 0:
            return False

        if filters.max_distance_km is not None:
            if (
                scored.distance_km is None
                or scored.distance_km > filters.max_distance_km
            ):
                return False

        if (
            filters.min_score is not None
            and scored.total < filters.min_score
        ):
            return False

        return True

    def _knn_order(
        self,
        scored: list[ScoredCandidate],
    ) -> list[ScoredCandidate]:
        vectors = np.asarray(
            [
                disagreement_vector(candidate.dimensions)
                for candidate in scored
            ],
            dtype=float,
        )
        viewer_vector = np.zeros(
            (1, len(DIMENSION_ORDER)),
            dtype=float,
        )
        nearest = NearestNeighbors(
            n_neighbors=len(scored),
            algorithm="brute",
            metric="euclidean",
            n_jobs=1,
        )
        nearest.fit(vectors)
        distances, indices = nearest.kneighbors(viewer_vector)

        ordered: list[ScoredCandidate] = []
        for distance, index in zip(
            distances[0].tolist(),
            indices[0].tolist(),
        ):
            converted = replace(
                scored[int(index)],
                total=score_from_distance(float(distance)),
            )
            ordered.append(converted)

        # KNN gives the score order. Name and id only settle exact ties so the
        # list is deterministic between requests.
        ordered.sort(
            key=lambda candidate: (
                -candidate.total,
                candidate.candidate.profile.name.casefold(),
                candidate.candidate.id,
            )
        )
        return ordered


class MatchingService:
    """Repository-backed matching with privacy-safe candidate projections."""

    def __init__(
        self,
        *,
        users: UserRepository,
        profiles: ProfileRepository,
        catalog: Catalog,
        profile_service: ProfileService,
    ) -> None:
        self._users = users
        self._profiles = profiles
        self._catalog = catalog
        self._profile_service = profile_service
        self._engine = MatchEngine(catalog)

    def get_matches(
        self,
        viewer: User,
        filters: MatchFilters | None = None,
        *,
        limit: int = 20,
    ) -> MatchList:
        if not 1 <= limit <= 100:
            raise InvalidMatchFilters("limit must be between 1 and 100.")

        resolved_filters = self._canonical_filters(filters or MatchFilters())
        viewer_profile = self._profile_service.get_stored(viewer)
        candidates, users_by_id = self._eligible_candidates(viewer)
        pool_size = len(candidates)

        missing = self._engine.missing_answers(viewer_profile)
        if missing:
            return self._empty_response(
                viewer,
                pool_size=pool_size,
                cold_start=ColdStart(
                    reason="profile_incomplete",
                    message=(
                        "Finish your matching answers to see people ranked "
                        "for you."
                    ),
                    missing=missing,
                ),
            )

        if not candidates:
            counterpart = (
                "tutor" if viewer.role == Role.student else "student"
            )
            return self._empty_response(
                viewer,
                pool_size=0,
                cold_start=ColdStart(
                    reason="no_candidates",
                    message=(
                        f"There are no completed {counterpart} profiles to "
                        "rank yet."
                    ),
                ),
            )

        public_by_id = {}
        with_distance: list[CandidateProfile] = []
        for candidate in candidates:
            target = users_by_id[candidate.id]
            public = self._profile_service.public_profile_for(
                target=target,
                target_profile=candidate.profile,
                viewer_profile=viewer_profile,
            )
            public_by_id[candidate.id] = public
            with_distance.append(
                replace(candidate, distance_km=public.distance_km)
            )

        ranked = self._engine.rank(
            viewer.role,
            viewer_profile,
            with_distance,
            resolved_filters,
        )
        selected = ranked[:limit]
        matches = [
            self._result_view(
                rank=index + 1,
                scored=scored,
                public=public_by_id[scored.candidate.id],
                viewer_role=viewer.role,
                viewer_profile=viewer_profile,
            )
            for index, scored in enumerate(selected)
        ]

        return MatchList(
            viewer_id=viewer.id,
            viewer_role=viewer.role,
            pool_size=pool_size,
            ranked_count=len(ranked),
            returned=len(matches),
            matches=matches,
        )

    def pair_score(
        self,
        viewer: User,
        counterpart: User,
    ) -> int | None:
        """The same weighted score used by ``GET /matches`` for one pair.

        Returns ``None`` when either person still has missing matching answers;
        request creation treats that as a validation failure. Distance is not
        part of the score and is deliberately not needed here.
        """

        viewer_profile = self._profile_service.get_stored(viewer)
        counterpart_profile = self._profile_service.get_stored(counterpart)
        if (
            self._engine.missing_answers(viewer_profile)
            or self._engine.missing_answers(counterpart_profile)
        ):
            return None
        candidate = CandidateProfile(
            id=counterpart.id,
            role=counterpart.role,
            profile=counterpart_profile,
        )
        return self._engine.score(
            viewer.role,
            viewer_profile,
            candidate,
        ).total

    def _eligible_candidates(
        self,
        viewer: User,
    ) -> tuple[list[CandidateProfile], dict[str, User]]:
        users_by_id = {user.id: user for user in self._users.list_all()}
        profiles_by_id = {
            profile.user_id: profile
            for profile in self._profiles.list_all()
        }

        candidates: list[CandidateProfile] = []
        for user in users_by_id.values():
            if user.id == viewer.id or user.role == viewer.role:
                continue
            profile = profiles_by_id.get(user.id)
            if profile is None or not self._engine.is_matchable(profile):
                continue
            candidates.append(
                CandidateProfile(
                    id=user.id,
                    role=user.role,
                    profile=profile,
                )
            )

        candidates.sort(key=lambda candidate: candidate.id)
        return candidates, users_by_id

    def _canonical_filters(self, filters: MatchFilters) -> MatchFilters:
        subjects: list[str] = []
        seen: set[str] = set()
        for value in filters.subjects:
            canonical = self._catalog.canonical_subject(value)
            if canonical is None:
                raise InvalidMatchFilters(
                    "Choose subjects from the subject catalogue."
                )
            key = canonical.casefold()
            if key not in seen:
                seen.add(key)
                subjects.append(canonical)

        required_parts: set[int] = set()
        for part in filters.required_parts:
            if part not in (0, 1, 2):
                raise InvalidMatchFilters(
                    "required_parts must be 0, 1, or 2."
                )
            required_parts.add(part)

        if filters.max_rate is not None and not 0 <= filters.max_rate <= 80:
            raise InvalidMatchFilters(
                "max_rate must be between 0 and 80."
            )
        if filters.min_score is not None and not 0 <= filters.min_score <= 100:
            raise InvalidMatchFilters(
                "min_score must be between 0 and 100."
            )
        if (
            filters.max_distance_km is not None
            and filters.max_distance_km < 0
        ):
            raise InvalidMatchFilters(
                "max_distance_km cannot be negative."
            )

        return replace(
            filters,
            subjects=tuple(subjects),
            required_parts=frozenset(required_parts),
        )

    def _empty_response(
        self,
        viewer: User,
        *,
        pool_size: int,
        cold_start: ColdStart,
    ) -> MatchList:
        return MatchList(
            viewer_id=viewer.id,
            viewer_role=viewer.role,
            pool_size=pool_size,
            ranked_count=0,
            returned=0,
            matches=[],
            cold_start=cold_start,
        )

    def _result_view(
        self,
        *,
        rank: int,
        scored: ScoredCandidate,
        public: PublicProfile,
        viewer_role: Role,
        viewer_profile: Profile,
    ) -> MatchResult:
        tier = tier_for(scored.total)
        return MatchResult(
            rank=rank,
            profile=public,
            score=scored.total,
            tier=tier,
            tier_label=TIER_LABELS[tier],
            dimensions=MatchDimensions(
                subjects=self._dimension_score(
                    scored,
                    MatchDimension.subjects,
                ),
                time=self._dimension_score(
                    scored,
                    MatchDimension.time,
                ),
                style=self._dimension_score(
                    scored,
                    MatchDimension.style,
                ),
                format=self._dimension_score(
                    scored,
                    MatchDimension.format,
                ),
                budget=self._dimension_score(
                    scored,
                    MatchDimension.budget,
                ),
            ),
            overlap=scored.overlap,
            overlap_slots=scored.overlap_slots,
            reasons=self._reasons(
                scored,
                viewer_role=viewer_role,
                viewer_profile=viewer_profile,
            ),
        )

    @staticmethod
    def _dimension_score(
        scored: ScoredCandidate,
        dimension: MatchDimension,
    ) -> DimensionScore:
        return DimensionScore(
            score=scored.dimensions[dimension],
            max=DIMENSION_WEIGHTS[dimension],
        )

    def _reasons(
        self,
        scored: ScoredCandidate,
        *,
        viewer_role: Role,
        viewer_profile: Profile,
    ) -> list[MatchReason]:
        notes = [
            self._subject_reason(scored, viewer_role, viewer_profile),
            self._time_reason(scored),
            self._style_reason(scored, viewer_role, viewer_profile),
            self._format_reason(scored, viewer_profile),
            self._budget_reason(scored, viewer_role, viewer_profile),
        ]
        order = {
            dimension: index
            for index, dimension in enumerate(DIMENSION_ORDER)
        }
        notes.sort(
            key=lambda note: (
                -scored.dimensions[note.dimension],
                order[note.dimension],
            )
        )
        top = notes[:3]

        if (
            scored.distance_km is not None
            and scored.distance_km <= NEARBY_DISTANCE_KM
        ):
            nearby = MatchReason(
                dimension=MatchDimension.format,
                label="Nearby",
                signal=describe_distance(scored.distance_km),
                detail=(
                    "Close enough that an in-person session would not turn "
                    "into a journey."
                ),
            )
            top.insert(min(2, len(top)), nearby)
            if len(top) > 3:
                top.pop()
        return top

    def _subject_reason(
        self,
        scored: ScoredCandidate,
        viewer_role: Role,
        viewer_profile: Profile,
    ) -> MatchReason:
        candidate_profile = scored.candidate.profile
        if viewer_role == Role.student:
            needs = viewer_profile.subjects
            offers = candidate_profile.subjects
            perspective = "student"
        else:
            needs = candidate_profile.subjects
            offers = viewer_profile.subjects
            perspective = "tutor"

        offer_set = {subject.casefold() for subject in offers}
        shared = [
            subject
            for subject in needs
            if subject.casefold() in offer_set
        ]

        if not shared:
            return MatchReason(
                dimension=MatchDimension.subjects,
                label=DIMENSION_LABELS[MatchDimension.subjects],
                signal="No shared subjects",
                detail=(
                    "Your subjects and theirs do not overlap, so this "
                    "dimension earns nothing."
                    if perspective == "student"
                    else "The subjects they need are not on your list."
                ),
            )

        if len(shared) == len(needs):
            detail = (
                "They cover every subject you asked for."
                if perspective == "student"
                else "They need every subject you teach."
            )
        else:
            missing = [
                subject
                for subject in needs
                if subject.casefold() not in offer_set
            ]
            detail = (
                f"That is {len(shared)} of {len(needs)} subjects you asked "
                f"for; {_natural_join(missing)} is the gap."
                if perspective == "student"
                else (
                    f"That is {len(shared)} of {len(needs)} subjects they "
                    f"need from you; {_natural_join(missing)} is the gap."
                )
            )

        return MatchReason(
            dimension=MatchDimension.subjects,
            label=DIMENSION_LABELS[MatchDimension.subjects],
            signal=_natural_join(shared),
            detail=detail,
        )

    @staticmethod
    def _time_reason(scored: ScoredCandidate) -> MatchReason:
        when = describe_overlap(scored.overlap)
        if when is None:
            return MatchReason(
                dimension=MatchDimension.time,
                label=DIMENSION_LABELS[MatchDimension.time],
                signal="No shared hours",
                detail=(
                    "You are never free at the same time in a normal week - "
                    "the one hard blocker here."
                ),
            )
        blocks = scored.overlap_slots
        noun = "hour-block" if blocks == 1 else "hour-blocks"
        return MatchReason(
            dimension=MatchDimension.time,
            label=DIMENSION_LABELS[MatchDimension.time],
            signal=when,
            detail=(
                f"Both of you are free then, {blocks} {noun} that line up "
                "in a normal week."
            ),
        )

    def _style_reason(
        self,
        scored: ScoredCandidate,
        viewer_role: Role,
        viewer_profile: Profile,
    ) -> MatchReason:
        viewer_index = self._engine.style_index(
            viewer_role,
            viewer_profile.style,
        )
        candidate_index = self._engine.style_index(
            scored.candidate.role,
            scored.candidate.profile.style,
        )
        viewer_label = (
            STYLE_LABELS[viewer_index]
            if 0 <= viewer_index < len(STYLE_LABELS)
            else "Your approach"
        )
        candidate_label = (
            STYLE_LABELS[candidate_index]
            if 0 <= candidate_index < len(STYLE_LABELS)
            else "their approach"
        )

        if viewer_index < 0 or candidate_index < 0:
            signal = f"{viewer_label} vs {candidate_label}"
            detail = "One of these styles is not in the catalogue."
        else:
            distance = abs(viewer_index - candidate_index)
            if distance == 0:
                signal = f"Both prefer {viewer_label.lower()}"
                detail = "You both chose the same way of working."
            elif distance == 1:
                signal = (
                    f"{viewer_label}, close to {candidate_label.lower()}"
                )
                detail = (
                    "The two approaches sit next to each other on the style "
                    "list; expect a small adjustment."
                )
            else:
                signal = f"{viewer_label} vs {candidate_label.lower()}"
                detail = (
                    f"These approaches are {distance} places apart on the "
                    "style list; this is a real compromise."
                )

        return MatchReason(
            dimension=MatchDimension.style,
            label=DIMENSION_LABELS[MatchDimension.style],
            signal=signal,
            detail=detail,
        )

    def _format_reason(
        self,
        scored: ScoredCandidate,
        viewer_profile: Profile,
    ) -> MatchReason:
        viewer_mode = viewer_profile.mode
        candidate_mode = scored.candidate.profile.mode
        labels = {
            SessionMode.online: "Online",
            SessionMode.in_person: "In person",
            SessionMode.both: "Either format",
        }
        if scored.dimensions[MatchDimension.format] > 0:
            if (
                viewer_mode == SessionMode.both
                and candidate_mode == SessionMode.both
            ):
                signal = "Either format"
                detail = (
                    "Both of you are flexible about online or in person."
                )
            elif viewer_mode == candidate_mode:
                signal = labels[viewer_mode]
                detail = "You both chose the same format."
            elif candidate_mode == SessionMode.both:
                signal = "They offer both formats"
                detail = "Their flexibility covers your choice."
            else:
                signal = "You offer both formats"
                detail = "Your flexibility covers their choice."
        else:
            signal = "Format mismatch"
            detail = (
                f"You chose {labels[viewer_mode].lower()}; they chose "
                f"{labels[candidate_mode].lower()}. Neither side is flexible."
            )

        return MatchReason(
            dimension=MatchDimension.format,
            label=DIMENSION_LABELS[MatchDimension.format],
            signal=signal,
            detail=detail,
        )

    @staticmethod
    def _budget_reason(
        scored: ScoredCandidate,
        viewer_role: Role,
        viewer_profile: Profile,
    ) -> MatchReason:
        candidate_budget = scored.candidate.profile.budget
        if viewer_role == Role.student:
            rate, ceiling = candidate_budget, viewer_profile.budget
            if rate <= ceiling:
                signal = (
                    f"${rate}/hr, within your ${ceiling} ceiling"
                )
                detail = "No budget compromise."
            else:
                gap = rate - ceiling
                signal = (
                    f"${rate}/hr, ${gap} over your ${ceiling} ceiling"
                )
                detail = (
                    "That is the only place this match costs you money."
                    if gap < BUDGET_TOLERANCE
                    else "A gap this size is unlikely to close."
                )
        else:
            rate, ceiling = viewer_profile.budget, candidate_budget
            if rate <= ceiling:
                signal = f"Your ${rate}/hr fits their ${ceiling} ceiling"
                detail = "No budget compromise."
            else:
                gap = rate - ceiling
                signal = (
                    f"Your ${rate}/hr is ${gap} above their ${ceiling} "
                    "ceiling"
                )
                detail = (
                    "They would need to stretch their budget, or you would "
                    "need to come down."
                    if gap < BUDGET_TOLERANCE
                    else "A gap this size is unlikely to close."
                )

        return MatchReason(
            dimension=MatchDimension.budget,
            label=DIMENSION_LABELS[MatchDimension.budget],
            signal=signal,
            detail=detail,
        )
