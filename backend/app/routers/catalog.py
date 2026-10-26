"""Static area and subject lookup."""

from __future__ import annotations

from fastapi import APIRouter

from ..dependencies import CatalogDep
from ..models.catalog import AreaCatalogue, SubjectCatalogue

router = APIRouter(tags=["catalog"])


@router.get("/areas", response_model=AreaCatalogue)
def get_areas(catalog: CatalogDep) -> AreaCatalogue:
    return catalog.area_catalogue()


@router.get("/subjects", response_model=SubjectCatalogue)
def get_subjects(catalog: CatalogDep) -> SubjectCatalogue:
    return catalog.subject_catalogue()
