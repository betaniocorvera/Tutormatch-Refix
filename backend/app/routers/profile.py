"""The signed-in user's profile and photo endpoints."""

from __future__ import annotations

from fastapi import APIRouter, File, Response, UploadFile, status

from ..dependencies import CurrentUser, ProfileServiceDep
from ..models.profile import (
    AvailabilityUpdate,
    OwnProfile,
    ProfileUpdate,
    SubjectsUpdate,
)
from ..services.photo_processing import MAX_UPLOAD_BYTES

router = APIRouter(prefix="/profile", tags=["profile"])


@router.get("", response_model=OwnProfile)
def get_profile(
    user: CurrentUser,
    profiles: ProfileServiceDep,
) -> OwnProfile:
    return profiles.get_own(user)


@router.put("", response_model=OwnProfile)
def update_profile(
    payload: ProfileUpdate,
    user: CurrentUser,
    profiles: ProfileServiceDep,
) -> OwnProfile:
    return profiles.update_profile(user, payload)


@router.put("/subjects", response_model=OwnProfile)
def update_subjects(
    payload: SubjectsUpdate,
    user: CurrentUser,
    profiles: ProfileServiceDep,
) -> OwnProfile:
    return profiles.update_subjects(user, payload)


@router.put("/availability", response_model=OwnProfile)
def update_availability(
    payload: AvailabilityUpdate,
    user: CurrentUser,
    profiles: ProfileServiceDep,
) -> OwnProfile:
    return profiles.update_availability(user, payload)


@router.post("/photo", response_model=OwnProfile)
async def upload_photo(
    user: CurrentUser,
    profiles: ProfileServiceDep,
    file: UploadFile = File(...),
) -> OwnProfile:
    # Read one byte past the limit so an oversized upload is rejected without
    # pulling an unbounded request body into memory.
    data = await file.read(MAX_UPLOAD_BYTES + 1)
    return profiles.upload_photo(user, data)


@router.delete("/photo", status_code=status.HTTP_204_NO_CONTENT)
def delete_photo(
    user: CurrentUser,
    profiles: ProfileServiceDep,
) -> Response:
    profiles.delete_photo(user)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
