"""Reference data exposed to the app: areas, cities, and subjects."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field


class CityOption(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    name: str
    region: str
    latitude: float
    longitude: float


class AreaOption(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    name: str
    city_id: str
    city: str
    region: str
    label: str
    latitude: float
    longitude: float


class AreaCatalogue(BaseModel):
    model_config = ConfigDict(extra="forbid")

    regions: list[str]
    cities: list[CityOption]
    areas: list[AreaOption]


class SubjectOption(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    name: str


class SubjectCatalogue(BaseModel):
    model_config = ConfigDict(extra="forbid")

    subjects: list[SubjectOption]


class SecurityQuestion(BaseModel):
    """A question a person may choose at registration.

    The text is public; the answer is never part of this model.
    """

    model_config = ConfigDict(extra="forbid")

    id: str
    text: str


class SecurityQuestionCatalogue(BaseModel):
    model_config = ConfigDict(extra="forbid")

    questions: list[SecurityQuestion]


class ProfileOptions(BaseModel):
    """The non-location answer sets the profile editor can offer."""

    model_config = ConfigDict(extra="forbid")

    student_styles: list[str]
    tutor_styles: list[str]
    student_goals: list[str]
    tutor_goals: list[str]
    languages: list[str] = Field(min_length=1)
    genders: list[str] = Field(min_length=1)
