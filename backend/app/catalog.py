"""Static catalogue loader.

Areas, subjects, and the profile answer sets are data files rather than rows
derived from sample users. The service layer validates every submitted value
against this catalogue, so a profile can only refer to a real area or subject.
"""

from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path

from pydantic import BaseModel, ConfigDict, Field

from .models.catalog import (
    AreaCatalogue,
    AreaOption,
    CityOption,
    ProfileOptions,
    SubjectCatalogue,
    SubjectOption,
)
from .models.user import Role

_DATA_DIR = Path(__file__).resolve().parent / "data"


class _CitySeed(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str = Field(min_length=1, max_length=80)
    name: str = Field(min_length=1, max_length=120)
    region: str = Field(min_length=1, max_length=120)
    latitude: float
    longitude: float


class _AreaSeed(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str = Field(min_length=1, max_length=120)
    name: str = Field(min_length=1, max_length=120)
    city_id: str = Field(min_length=1, max_length=80)
    latitude: float
    longitude: float


class _AreasFile(BaseModel):
    model_config = ConfigDict(extra="forbid")

    regions: list[str] = Field(min_length=1)
    cities: list[_CitySeed] = Field(min_length=1)
    areas: list[_AreaSeed] = Field(min_length=1)


class _SubjectSeed(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str = Field(min_length=1, max_length=80)
    name: str = Field(min_length=1, max_length=120)


class _SubjectsFile(BaseModel):
    model_config = ConfigDict(extra="forbid")

    subjects: list[_SubjectSeed] = Field(min_length=1)


class Catalog:
    """Validated, read-only reference data."""

    def __init__(
        self,
        *,
        regions: list[str],
        cities: list[CityOption],
        areas: list[AreaOption],
        subjects: list[SubjectOption],
        options: ProfileOptions,
    ) -> None:
        self.regions = list(regions)
        self.cities = list(cities)
        self.areas = list(areas)
        self.subjects = list(subjects)
        self.options = options

        self._cities_by_id = {city.id: city for city in self.cities}
        self._areas_by_id = {area.id: area for area in self.areas}
        self._subjects_by_key = {
            subject.name.casefold(): subject.name for subject in self.subjects
        }
        self._subjects_by_id = {
            subject.id: subject.name for subject in self.subjects
        }
        self._languages_by_key = {
            language.casefold(): language for language in options.languages
        }
        self._genders_by_key = {
            gender.casefold(): gender for gender in options.genders
        }
        self._styles_by_role = {
            Role.student: self._keyed(options.student_styles),
            Role.tutor: self._keyed(options.tutor_styles),
        }
        self._goals_by_role = {
            Role.student: self._keyed(options.student_goals),
            Role.tutor: self._keyed(options.tutor_goals),
        }
        self._area_catalogue = AreaCatalogue(
            regions=self.regions,
            cities=self.cities,
            areas=self.areas,
        )
        self._subject_catalogue = SubjectCatalogue(subjects=self.subjects)

    @staticmethod
    def _keyed(values: list[str]) -> dict[str, str]:
        return {value.casefold(): value for value in values}

    def area(self, area_id: str | None) -> AreaOption | None:
        if not area_id:
            return None
        return self._areas_by_id.get(area_id)

    def city(self, city_id: str) -> CityOption | None:
        return self._cities_by_id.get(city_id)

    def area_catalogue(self) -> AreaCatalogue:
        return self._area_catalogue

    def subject_catalogue(self) -> SubjectCatalogue:
        return self._subject_catalogue

    def canonical_subject(self, value: str) -> str | None:
        cleaned = value.strip()
        return self._subjects_by_key.get(
            cleaned.casefold()
        ) or self._subjects_by_id.get(cleaned)

    def canonical_language(self, value: str) -> str | None:
        return self._languages_by_key.get(value.strip().casefold())

    def canonical_gender(self, value: str) -> str | None:
        return self._genders_by_key.get(value.strip().casefold())

    def canonical_style(self, role: Role, value: str) -> str | None:
        return self._styles_by_role[role].get(value.strip().casefold())

    def canonical_goal(self, role: Role, value: str) -> str | None:
        return self._goals_by_role[role].get(value.strip().casefold())

    def style_options(self, role: Role) -> list[str]:
        return list(self._styles_by_role[role].values())

    def goal_options(self, role: Role) -> list[str]:
        return list(self._goals_by_role[role].values())


def _read_json(path: Path) -> object:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"Could not read catalogue data at {path}.") from exc


def _validate_coordinate(value: float, *, minimum: float, maximum: float) -> None:
    if value < minimum or value > maximum:
        raise RuntimeError("Catalogue coordinates are outside their valid range.")


def _load_catalog() -> Catalog:
    areas_raw = _AreasFile.model_validate(
        _read_json(_DATA_DIR / "areas.json")
    )
    subjects_raw = _SubjectsFile.model_validate(
        _read_json(_DATA_DIR / "subjects.json")
    )
    options = ProfileOptions.model_validate(
        _read_json(_DATA_DIR / "profile_options.json")
    )

    if len(set(areas_raw.regions)) != len(areas_raw.regions):
        raise RuntimeError("Catalogue regions must be unique.")

    city_ids: set[str] = set()
    city_names: set[str] = set()
    cities: list[CityOption] = []
    for seed in areas_raw.cities:
        if seed.id in city_ids:
            raise RuntimeError(f"Duplicate city id: {seed.id}")
        if seed.region not in areas_raw.regions:
            raise RuntimeError(
                f"City {seed.name} refers to an unknown region {seed.region}."
            )
        if seed.name.casefold() in city_names:
            raise RuntimeError(f"Duplicate city name: {seed.name}")
        _validate_coordinate(seed.latitude, minimum=-90, maximum=90)
        _validate_coordinate(seed.longitude, minimum=-180, maximum=180)
        city_ids.add(seed.id)
        city_names.add(seed.name.casefold())
        cities.append(
            CityOption(
                id=seed.id,
                name=seed.name,
                region=seed.region,
                latitude=seed.latitude,
                longitude=seed.longitude,
            )
        )

    cities_by_id = {city.id: city for city in cities}
    area_ids: set[str] = set()
    areas: list[AreaOption] = []
    for seed in areas_raw.areas:
        if seed.id in area_ids:
            raise RuntimeError(f"Duplicate area id: {seed.id}")
        city = cities_by_id.get(seed.city_id)
        if city is None:
            raise RuntimeError(
                f"Area {seed.name} refers to an unknown city {seed.city_id}."
            )
        _validate_coordinate(seed.latitude, minimum=-90, maximum=90)
        _validate_coordinate(seed.longitude, minimum=-180, maximum=180)
        area_ids.add(seed.id)
        areas.append(
            AreaOption(
                id=seed.id,
                name=seed.name,
                city_id=city.id,
                city=city.name,
                region=city.region,
                label=f"{seed.name}, {city.name}",
                latitude=seed.latitude,
                longitude=seed.longitude,
            )
        )

    subject_ids: set[str] = set()
    subject_names: set[str] = set()
    subjects: list[SubjectOption] = []
    for seed in subjects_raw.subjects:
        if seed.id in subject_ids:
            raise RuntimeError(f"Duplicate subject id: {seed.id}")
        key = seed.name.casefold()
        if key in subject_names:
            raise RuntimeError(f"Duplicate subject name: {seed.name}")
        subject_ids.add(seed.id)
        subject_names.add(key)
        subjects.append(SubjectOption(id=seed.id, name=seed.name))

    for label, values in (
        ("student style", options.student_styles),
        ("tutor style", options.tutor_styles),
        ("student goal", options.student_goals),
        ("tutor goal", options.tutor_goals),
        ("language", options.languages),
        ("gender", options.genders),
    ):
        keys = [value.casefold() for value in values]
        if len(keys) != len(set(keys)):
            raise RuntimeError(f"Catalogue {label} options must be unique.")

    return Catalog(
        regions=areas_raw.regions,
        cities=cities,
        areas=areas,
        subjects=subjects,
        options=options,
    )


@lru_cache(maxsize=1)
def get_catalog() -> Catalog:
    """Load and validate the static catalogue once per process."""

    return _load_catalog()
