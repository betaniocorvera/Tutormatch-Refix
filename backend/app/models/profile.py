"""Profile models shared by the API, services, and repositories.

The field set mirrors the existing Flutter profile rather than inventing a
second shape: the five ranking answers, the public details, and the structured
area + privacy choice. Birthdate and the raw area are stored; age, the public
location, distance, and completeness are derived for responses.
"""

from __future__ import annotations

from datetime import date, datetime
from enum import Enum

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    field_validator,
)

from .user import Role

NO_ANSWER = "Prefer not to say"
AVAILABILITY_CELLS = 21


class LocationPrivacy(str, Enum):
    area = "area"
    city_only = "city_only"
    hidden = "hidden"


class PresenceStatus(str, Enum):
    available = "available"
    busy = "busy"
    away = "away"


class SessionMode(str, Enum):
    online = "online"
    in_person = "in_person"
    both = "both"


def _hundred_years_before(today: date) -> date:
    try:
        return today.replace(year=today.year - 100)
    except ValueError:
        # 29 February in a non-leap target year.
        return today.replace(year=today.year - 100, day=28)


def _validate_birthdate(value: date | None) -> date | None:
    if value is None:
        return value
    today = date.today()
    if value > today:
        raise ValueError("birthdate cannot be in the future")
    if value < _hundred_years_before(today):
        raise ValueError("birthdate is too far in the past")
    return value


def _validate_availability(value: list[bool]) -> list[bool]:
    if len(value) != AVAILABILITY_CELLS:
        raise ValueError(
            f"availability must contain exactly {AVAILABILITY_CELLS} slots"
        )
    return value


def _empty_availability() -> list[bool]:
    return [False] * AVAILABILITY_CELLS


class Profile(BaseModel):
    """Internal stored profile. Never returned directly by an endpoint."""

    model_config = ConfigDict(extra="forbid")

    user_id: str
    name: str = Field(default="", max_length=80)
    subjects: list[str] = Field(default_factory=list, max_length=4)
    style: str = Field(default="", max_length=200)
    mode: SessionMode = SessionMode.both
    budget: int = Field(default=0, ge=0, le=80)
    availability: list[bool] = Field(default_factory=_empty_availability)
    goal: str = Field(default="", max_length=300)
    birthdate: date | None = None
    area_id: str = Field(default="", max_length=120)
    location_privacy: LocationPrivacy = LocationPrivacy.city_only
    status_text: str = Field(default="", max_length=160)
    presence: PresenceStatus = PresenceStatus.available
    bio: str = Field(default="", max_length=1000)
    gender: str = Field(default=NO_ANSWER, max_length=40)
    languages: list[str] = Field(default_factory=list, max_length=15)
    years: int | None = Field(default=None, ge=0, le=80)
    education: str = Field(default="", max_length=200)
    grade: str = Field(default="", max_length=80)
    updated_at: datetime

    @field_validator("birthdate")
    @classmethod
    def _birthdate_valid(cls, value: date | None) -> date | None:
        return _validate_birthdate(value)

    @field_validator("availability")
    @classmethod
    def _availability_valid(cls, value: list[bool]) -> list[bool]:
        return _validate_availability(value)


class ProfileUpdate(BaseModel):
    """A partial profile update.

    Every field is optional at the transport layer. ``model_fields_set`` is what
    tells the service which fields the caller actually sent, so a missing field
    is left alone while an explicit ``null`` clears a nullable one.
    """

    model_config = ConfigDict(extra="forbid")

    name: str = Field(default="", max_length=80)
    subjects: list[str] = Field(default_factory=list, max_length=4)
    style: str = Field(default="", max_length=200)
    mode: SessionMode = SessionMode.both
    budget: int = Field(default=0, ge=0, le=80)
    availability: list[bool] = Field(default_factory=_empty_availability)
    goal: str = Field(default="", max_length=300)
    birthdate: date | None = None
    area_id: str | None = Field(default=None, max_length=120)
    location_privacy: LocationPrivacy = LocationPrivacy.city_only
    status_text: str = Field(default="", max_length=160)
    presence: PresenceStatus = PresenceStatus.available
    bio: str = Field(default="", max_length=1000)
    gender: str = Field(default=NO_ANSWER, max_length=40)
    languages: list[str] = Field(default_factory=list, max_length=15)
    years: int | None = Field(default=None, ge=0, le=80)
    education: str = Field(default="", max_length=200)
    grade: str = Field(default="", max_length=80)

    @field_validator("birthdate")
    @classmethod
    def _birthdate_valid(cls, value: date | None) -> date | None:
        return _validate_birthdate(value)

    @field_validator("availability")
    @classmethod
    def _availability_valid(cls, value: list[bool]) -> list[bool]:
        return _validate_availability(value)


class SubjectsUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    subjects: list[str] = Field(max_length=4)


class AvailabilityUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    availability: list[bool]

    @field_validator("availability")
    @classmethod
    def _availability_valid(cls, value: list[bool]) -> list[bool]:
        return _validate_availability(value)


class PublicLocation(BaseModel):
    """The most another person may read about a profile's area."""

    model_config = ConfigDict(extra="forbid")

    label: str
    city: str
    region: str
    latitude: float
    longitude: float
    city_only: bool


class ProfileCompleteness(BaseModel):
    model_config = ConfigDict(extra="forbid")

    filled: int
    total: int
    fraction: float
    missing: list[str]


class OwnProfile(BaseModel):
    """The signed-in user's editable profile plus derived readings."""

    model_config = ConfigDict(extra="forbid")

    user_id: str
    role: Role
    name: str
    subjects: list[str]
    style: str
    mode: SessionMode
    budget: int
    availability: list[bool]
    goal: str
    age: int | None
    birthdate: date | None
    lives_in: str
    area_id: str
    location_privacy: LocationPrivacy
    public_location: PublicLocation | None
    status_text: str
    presence: PresenceStatus
    bio: str
    gender: str
    languages: list[str]
    years: int | None
    education: str
    grade: str
    photo_url: str | None
    completeness: ProfileCompleteness
    onboarding_complete: bool
    updated_at: datetime


class PublicProfile(BaseModel):
    """Fields another signed-in user may see.

    No email, password hash, birthdate, raw area id, separate raw location
    fields, or onboarding flag. ``public_location`` and ``distance_km`` have
    already had both people's privacy settings applied.
    """

    model_config = ConfigDict(extra="forbid")

    id: str
    role: Role
    display_name: str
    name: str
    created_at: datetime
    age: int | None
    photo_url: str | None
    public_location: PublicLocation | None
    distance_km: float | None
    distance_text: str | None
    subjects: list[str]
    style: str
    mode: SessionMode
    budget: int
    availability: list[bool]
    goal: str
    status_text: str
    presence: PresenceStatus
    bio: str
    gender: str
    languages: list[str]
    years: int | None
    education: str
    grade: str
