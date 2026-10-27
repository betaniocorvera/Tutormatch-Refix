"""Response models for the ranked match list.

The shape is deliberately close to the Flutter ``MatchResult``: a public
candidate profile, one integer score, the five dimension contributions, the
21-cell overlap grid, and three plain-language reasons. Public profile data is
nested rather than flattened so the privacy-safe projection in Phase 2 remains
the single source of candidate fields.
"""

from __future__ import annotations

from enum import Enum
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

from .profile import AVAILABILITY_CELLS, PublicProfile
from .user import Role


class MatchDimension(str, Enum):
    subjects = "subjects"
    time = "time"
    style = "style"
    format = "format"
    budget = "budget"


class MatchTier(str, Enum):
    strong = "strong"
    good = "good"
    possible = "possible"
    weak = "weak"


TIER_LABELS: dict[MatchTier, str] = {
    MatchTier.strong: "Strong match",
    MatchTier.good: "Good match",
    MatchTier.possible: "Worth a look",
    MatchTier.weak: "Long shot",
}


class DimensionScore(BaseModel):
    model_config = ConfigDict(extra="forbid")

    score: int = Field(ge=0, le=100)
    max: int = Field(gt=0, le=100)


class MatchDimensions(BaseModel):
    model_config = ConfigDict(extra="forbid")

    subjects: DimensionScore
    time: DimensionScore
    style: DimensionScore
    format: DimensionScore
    budget: DimensionScore


class MatchReason(BaseModel):
    """One explanation, attached to the dimension that produced it.

    ``label`` is normally the dimension label. A nearby note uses the format
    dimension for its icon but overrides the label to "Nearby", matching the
    existing Flutter presentation.
    """

    model_config = ConfigDict(extra="forbid")

    dimension: MatchDimension
    label: str = Field(min_length=1, max_length=80)
    signal: str = Field(min_length=1, max_length=240)
    detail: str = Field(min_length=1, max_length=500)


class MatchResult(BaseModel):
    model_config = ConfigDict(extra="forbid")

    rank: int = Field(ge=1)
    profile: PublicProfile
    score: int = Field(ge=0, le=100)
    tier: MatchTier
    tier_label: str = Field(min_length=1, max_length=40)
    dimensions: MatchDimensions
    overlap: list[bool] = Field(
        min_length=AVAILABILITY_CELLS,
        max_length=AVAILABILITY_CELLS,
    )
    overlap_slots: int = Field(ge=0, le=AVAILABILITY_CELLS)
    reasons: list[MatchReason] = Field(min_length=3, max_length=3)


class ColdStart(BaseModel):
    model_config = ConfigDict(extra="forbid")

    reason: Literal["profile_incomplete", "no_candidates"]
    message: str = Field(min_length=1, max_length=300)
    missing: list[str] = Field(default_factory=list)


class MatchList(BaseModel):
    """The ranked list plus enough counts to draw the pool meter.

    ``pool_size`` is the number of eligible counterparts before filters.
    ``ranked_count`` is the number left after filters, before ``limit``.
    """

    model_config = ConfigDict(extra="forbid")

    viewer_id: str
    viewer_role: Role
    pool_size: int = Field(ge=0)
    ranked_count: int = Field(ge=0)
    returned: int = Field(ge=0)
    matches: list[MatchResult]
    cold_start: ColdStart | None = None
