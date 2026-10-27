"""The ranked match list.

Filters narrow the ranking; they never change its order. Candidate eligibility
(opposite role, completed answers, not yourself) is a hard filter inside the
service, before KNN runs.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Query

from ..dependencies import CurrentUser, MatchingServiceDep
from ..models.matching import MatchList
from ..models.profile import SessionMode
from ..services.matching import MatchFilters

router = APIRouter(prefix="/matches", tags=["matches"])


@router.get("", response_model=MatchList)
def get_matches(
    user: CurrentUser,
    matching: MatchingServiceDep,
    subjects: Annotated[list[str] | None, Query()] = None,
    mode: SessionMode | None = None,
    max_rate: Annotated[int | None, Query(ge=0, le=80)] = None,
    required_parts: Annotated[list[int] | None, Query()] = None,
    must_be_free_when_i_am: bool = False,
    max_distance_km: Annotated[int | None, Query(ge=0, le=20000)] = None,
    min_score: Annotated[int | None, Query(ge=0, le=100)] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
) -> MatchList:
    filters = MatchFilters(
        subjects=tuple(subjects or ()),
        mode=mode,
        max_rate=max_rate,
        required_parts=frozenset(required_parts or ()),
        must_be_free_when_i_am=must_be_free_when_i_am,
        max_distance_km=max_distance_km,
        min_score=min_score,
    )
    return matching.get_matches(user, filters, limit=limit)
