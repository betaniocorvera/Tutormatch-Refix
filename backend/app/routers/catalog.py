"""Static area and subject lookup."""

from __future__ import annotations

from fastapi import APIRouter

from ..dependencies import CatalogDep
from ..models.catalog import (
    AreaCatalogue,
    SecurityQuestionCatalogue,
    SubjectCatalogue,
)

router = APIRouter(tags=["catalog"])


@router.get("/areas", response_model=AreaCatalogue)
def get_areas(catalog: CatalogDep) -> AreaCatalogue:
    return catalog.area_catalogue()


@router.get("/subjects", response_model=SubjectCatalogue)
def get_subjects(catalog: CatalogDep) -> SubjectCatalogue:
    return catalog.subject_catalogue()


@router.get(
    "/security-questions",
    response_model=SecurityQuestionCatalogue,
)
def get_security_questions(
    catalog: CatalogDep,
) -> SecurityQuestionCatalogue:
    """The public question list. Answers are never part of this response."""

    return catalog.security_question_catalogue()
