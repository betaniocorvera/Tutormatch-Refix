"""Profile reads/writes, public projections, privacy, and photo uploads."""

from __future__ import annotations

import math
import threading
from datetime import date, datetime, timezone

from ..catalog import Catalog
from ..errors import InvalidProfile, PhotoNotFound, UserNotFound
from ..models.profile import (
    NO_ANSWER,
    AvailabilityUpdate,
    LocationPrivacy,
    OwnProfile,
    Profile,
    ProfileCompleteness,
    ProfileUpdate,
    PublicLocation,
    PublicProfile,
    SubjectsUpdate,
)
from ..models.user import Role, User
from ..repositories.interfaces import ProfileRepository, UserRepository
from ..storage.photos import PhotoStorage, StoredPhoto
from ..transactions import TransactionFactory, no_transaction
from .photo_processing import OUTPUT_CONTENT_TYPE, reencode_photo


def age_on(birthdate: date, on: date) -> int:
    """Whole years on a date, matching the UI's birthdate reading."""

    years = on.year - birthdate.year
    if (on.month, on.day) < (birthdate.month, birthdate.day):
        years -= 1
    return years


def _haversine_km(
    lat1: float,
    lon1: float,
    lat2: float,
    lon2: float,
) -> float:
    earth_radius_km = 6371.0088
    d_lat = math.radians(lat2 - lat1)
    d_lon = math.radians(lon2 - lon1)
    a = (
        math.sin(d_lat / 2) ** 2
        + math.cos(math.radians(lat1))
        * math.cos(math.radians(lat2))
        * math.sin(d_lon / 2) ** 2
    )
    return 2 * earth_radius_km * math.asin(
        math.sqrt(max(0.0, min(1.0, a)))
    )


def _distance_text(km: float) -> str:
    if km < 1:
        return "less than 1 km away"
    return f"about {km:.0f} km away"


class ProfileService:
    def __init__(
        self,
        *,
        users: UserRepository,
        profiles: ProfileRepository,
        catalog: Catalog,
        photos: PhotoStorage,
        transaction: TransactionFactory | None = None,
    ) -> None:
        self._users = users
        self._profiles = profiles
        self._catalog = catalog
        self._photos = photos
        self._transaction = transaction or no_transaction
        # A profile update is a read-modify-write operation. Serialise it so
        # two simultaneous edits cannot silently discard one another.
        self._lock = threading.RLock()

    def get_own(self, user: User) -> OwnProfile:
        with self._lock:
            with self._transaction():
                profile = self._get_or_create(user)
                return self._own_view(user, profile)

    def update_profile(
        self,
        user: User,
        payload: ProfileUpdate,
    ) -> OwnProfile:
        updates = payload.model_dump(exclude_unset=True)
        with self._lock:
            with self._transaction():
                profile = self._get_or_create(user)
                normalized = self._normalize_updates(user, updates)
                updated = profile.model_copy(
                    update={
                        **normalized,
                        "updated_at": datetime.now(timezone.utc),
                    }
                )
                self._profiles.update(updated)
                user = self._sync_user(
                    user,
                    updated,
                    name_changed="name" in normalized,
                )
                return self._own_view(user, updated)

    def update_subjects(
        self,
        user: User,
        payload: SubjectsUpdate,
    ) -> OwnProfile:
        return self.update_profile(
            user,
            ProfileUpdate(subjects=payload.subjects),
        )

    def update_availability(
        self,
        user: User,
        payload: AvailabilityUpdate,
    ) -> OwnProfile:
        return self.update_profile(
            user,
            ProfileUpdate(availability=payload.availability),
        )

    def upload_photo(self, user: User, data: bytes) -> OwnProfile:
        encoded = reencode_photo(data)
        with self._lock:
            with self._transaction():
                profile = self._get_or_create(user)
                self._photos.save(
                    user.id,
                    encoded,
                    content_type=OUTPUT_CONTENT_TYPE,
                )
                return self._own_view(user, profile)

    def delete_photo(self, user: User) -> None:
        with self._lock:
            self._photos.delete(user.id)

    def get_photo(self, user_id: str) -> StoredPhoto:
        user = self._users.get_by_id(user_id)
        if user is None:
            raise UserNotFound()
        photo = self._photos.get(user_id)
        if photo is None:
            raise PhotoNotFound()
        return photo

    def get_stored(self, user: User) -> Profile:
        """The stored profile, or a non-persisted default for a new account.

        Matching needs the internal shape, not the editable API view. The
        default is deliberately not added to the repository: reading matches
        must not create a profile as a side effect.
        """

        return self._profile_or_default(user)

    def public_profile(
        self,
        viewer: User,
        user_id: str,
    ) -> PublicProfile:
        target = self._users.get_by_id(user_id)
        if target is None:
            raise UserNotFound()

        return self.public_profile_for(
            target=target,
            target_profile=self._profile_or_default(target),
            viewer_profile=self._profile_or_default(viewer),
        )

    def public_profile_for(
        self,
        *,
        target: User,
        target_profile: Profile,
        viewer_profile: Profile,
    ) -> PublicProfile:
        """Build a public view from already-loaded profiles.

        Batch callers such as matching already hold the user and profile rows;
        this avoids a second repository round trip while keeping the privacy
        projection in one place.
        """

        public_location = self._public_location(target_profile)
        viewer_location = self._public_location(viewer_profile)
        distance_km, distance_text = self._distance(
            viewer_location,
            public_location,
        )

        return PublicProfile(
            id=target.id,
            role=target.role,
            display_name=target_profile.name,
            name=target_profile.name,
            created_at=target.created_at,
            age=self._age(target_profile),
            photo_url=self._photo_url(target.id),
            public_location=public_location,
            distance_km=distance_km,
            distance_text=distance_text,
            subjects=target_profile.subjects,
            style=target_profile.style,
            mode=target_profile.mode,
            budget=target_profile.budget,
            availability=target_profile.availability,
            goal=target_profile.goal,
            status_text=target_profile.status_text,
            presence=target_profile.presence,
            bio=target_profile.bio,
            gender=target_profile.gender,
            languages=target_profile.languages,
            years=target_profile.years,
            education=target_profile.education,
            grade=target_profile.grade,
        )

    def _get_or_create(self, user: User) -> Profile:
        existing = self._profiles.get_by_user_id(user.id)
        if existing is not None:
            return existing
        profile = self._default_profile(user)
        self._profiles.add(profile)
        return profile

    def _profile_or_default(self, user: User) -> Profile:
        return (
            self._profiles.get_by_user_id(user.id)
            or self._default_profile(user)
        )

    @staticmethod
    def _default_profile(user: User) -> Profile:
        return Profile(
            user_id=user.id,
            name=user.display_name,
            updated_at=datetime.now(timezone.utc),
        )

    def _own_view(self, user: User, profile: Profile) -> OwnProfile:
        area = self._catalog.area(profile.area_id)
        has_photo = self._photos.exists(user.id)
        return OwnProfile(
            user_id=user.id,
            role=user.role,
            name=profile.name,
            subjects=profile.subjects,
            style=profile.style,
            mode=profile.mode,
            budget=profile.budget,
            availability=profile.availability,
            goal=profile.goal,
            age=self._age(profile),
            birthdate=profile.birthdate,
            lives_in=area.label if area else "",
            area_id=profile.area_id,
            location_privacy=profile.location_privacy,
            public_location=self._public_location(profile),
            status_text=profile.status_text,
            presence=profile.presence,
            bio=profile.bio,
            gender=profile.gender,
            languages=profile.languages,
            years=profile.years,
            education=profile.education,
            grade=profile.grade,
            photo_url=self._photo_url(user.id) if has_photo else None,
            completeness=self._completeness(
                profile,
                user.role,
                has_photo=has_photo,
            ),
            onboarding_complete=user.onboarding_complete,
            updated_at=profile.updated_at,
        )

    def _normalize_updates(
        self,
        user: User,
        updates: dict[str, object],
    ) -> dict[str, object]:
        normalized: dict[str, object] = {}
        for field, value in updates.items():
            if field == "name":
                normalized[field] = str(value).strip()
            elif field == "subjects":
                normalized[field] = self._normalize_subjects(value)
            elif field == "style":
                normalized[field] = self._normalize_style(
                    user.role,
                    str(value),
                )
            elif field == "goal":
                normalized[field] = self._normalize_goal(
                    user.role,
                    str(value),
                )
            elif field == "languages":
                normalized[field] = self._normalize_languages(value)
            elif field == "gender":
                normalized[field] = self._normalize_gender(str(value))
            elif field == "area_id":
                normalized[field] = self._normalize_area(value)
            elif field == "birthdate":
                normalized[field] = value
            elif field == "availability":
                normalized[field] = list(value)  # type: ignore[arg-type]
            elif field in {
                "mode",
                "budget",
                "location_privacy",
                "presence",
                "years",
            }:
                normalized[field] = value
            elif field in {
                "status_text",
                "bio",
                "education",
                "grade",
            }:
                normalized[field] = str(value).strip()
            else:
                raise InvalidProfile("That profile field is not editable.")
        return normalized

    def _normalize_subjects(self, value: object) -> list[str]:
        if not isinstance(value, list):
            raise InvalidProfile("Subjects must be a list.")
        if len(value) > 4:
            raise InvalidProfile("Choose up to four subjects.")
        subjects: list[str] = []
        seen: set[str] = set()
        for item in value:
            canonical = self._catalog.canonical_subject(str(item))
            if canonical is None:
                raise InvalidProfile(
                    "Choose subjects from the subject catalogue."
                )
            key = canonical.casefold()
            if key in seen:
                raise InvalidProfile("A subject can only appear once.")
            seen.add(key)
            subjects.append(canonical)
        return subjects

    def _normalize_style(self, role: Role, value: str) -> str:
        if not value.strip():
            return ""
        canonical = self._catalog.canonical_style(role, value)
        if canonical is None:
            raise InvalidProfile(
                "Choose a style from the list for your role."
            )
        return canonical

    def _normalize_goal(self, role: Role, value: str) -> str:
        if not value.strip():
            return ""
        canonical = self._catalog.canonical_goal(role, value)
        if canonical is None:
            raise InvalidProfile(
                "Choose a goal from the list for your role."
            )
        return canonical

    def _normalize_languages(self, value: object) -> list[str]:
        if not isinstance(value, list):
            raise InvalidProfile("Languages must be a list.")
        if len(value) > 15:
            raise InvalidProfile("Choose up to fifteen languages.")
        languages: list[str] = []
        seen: set[str] = set()
        for item in value:
            canonical = self._catalog.canonical_language(str(item))
            if canonical is None:
                raise InvalidProfile(
                    "Choose languages from the language catalogue."
                )
            key = canonical.casefold()
            if key in seen:
                raise InvalidProfile("A language can only appear once.")
            seen.add(key)
            languages.append(canonical)
        return languages

    def _normalize_gender(self, value: str) -> str:
        if not value.strip():
            return NO_ANSWER
        canonical = self._catalog.canonical_gender(value)
        if canonical is None:
            raise InvalidProfile("Choose a gender from the list.")
        return canonical

    def _normalize_area(self, value: object) -> str:
        if value is None:
            return ""
        area_id = str(value).strip()
        if not area_id:
            return ""
        if self._catalog.area(area_id) is None:
            raise InvalidProfile("Choose an area from the catalogue.")
        return area_id

    def _sync_user(
        self,
        user: User,
        profile: Profile,
        *,
        name_changed: bool,
    ) -> User:
        updates: dict[str, object] = {}
        if name_changed and profile.name != user.display_name:
            updates["display_name"] = profile.name
        if not user.onboarding_complete and self._answers_complete(profile):
            updates["onboarding_complete"] = True
        if not updates:
            return user

        updates["updated_at"] = datetime.now(timezone.utc)
        updated_user = user.model_copy(update=updates)
        self._users.update(updated_user)
        return updated_user

    @staticmethod
    def _answers_complete(profile: Profile) -> bool:
        return (
            bool(profile.subjects)
            and bool(profile.style.strip())
            and any(profile.availability)
            and bool(profile.goal.strip())
            and profile.budget > 0
        )

    def _public_location(
        self,
        profile: Profile,
    ) -> PublicLocation | None:
        if profile.location_privacy is LocationPrivacy.hidden:
            return None
        area = self._catalog.area(profile.area_id)
        if area is None:
            return None
        if profile.location_privacy is LocationPrivacy.city_only:
            city = self._catalog.city(area.city_id)
            if city is None:
                return None
            return PublicLocation(
                label=city.name,
                city=city.name,
                region=city.region,
                latitude=city.latitude,
                longitude=city.longitude,
                city_only=True,
            )
        return PublicLocation(
            label=area.label,
            city=area.city,
            region=area.region,
            latitude=area.latitude,
            longitude=area.longitude,
            city_only=False,
        )

    @staticmethod
    def _distance(
        viewer: PublicLocation | None,
        target: PublicLocation | None,
    ) -> tuple[float | None, str | None]:
        if viewer is None or target is None:
            return None, None
        km = _haversine_km(
            viewer.latitude,
            viewer.longitude,
            target.latitude,
            target.longitude,
        )
        return round(km, 1), _distance_text(km)

    @staticmethod
    def _age(profile: Profile) -> int | None:
        if profile.birthdate is None:
            return None
        return age_on(profile.birthdate, date.today())

    def _photo_url(self, user_id: str) -> str | None:
        if not self._photos.exists(user_id):
            return None
        return f"/users/{user_id}/photo"

    @staticmethod
    def _completeness(
        profile: Profile,
        role: Role,
        *,
        has_photo: bool,
    ) -> ProfileCompleteness:
        gaps: list[tuple[str, bool]] = [
            ("a picture", has_photo),
            ("a display name", bool(profile.name.strip())),
            ("a birthdate", profile.birthdate is not None),
            ("where you live", bool(profile.area_id)),
            ("a status line", bool(profile.status_text.strip())),
            ("a bio", bool(profile.bio.strip())),
            ("your gender", profile.gender != NO_ANSWER),
            ("the languages you speak", bool(profile.languages)),
        ]
        if role is Role.student:
            gaps.extend(
                [
                    ("your year level", bool(profile.grade.strip())),
                    ("what you need help with", bool(profile.subjects)),
                    ("a budget", profile.budget > 0),
                    ("what you are aiming at", bool(profile.goal.strip())),
                ]
            )
        else:
            gaps.extend(
                [
                    ("the subjects you teach", bool(profile.subjects)),
                    ("your hourly rate", profile.budget > 0),
                    ("your years of experience", profile.years is not None),
                    ("your education", bool(profile.education.strip())),
                ]
            )

        filled = sum(1 for _, present in gaps if present)
        total = len(gaps)
        return ProfileCompleteness(
            filled=filled,
            total=total,
            fraction=round(filled / total, 4) if total else 0.0,
            missing=[label for label, present in gaps if not present],
        )
