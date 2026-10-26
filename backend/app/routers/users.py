"""Public user views and profile photos.

A public view contains the fields another signed-in person may read. It never
contains an email, password hash, birthdate, raw area id, or onboarding flag.
"""

from __future__ import annotations

from fastapi import APIRouter, Response

from ..dependencies import CurrentUser, ProfileServiceDep
from ..models.profile import PublicProfile

router = APIRouter(prefix="/users", tags=["users"])


@router.get("/{user_id}/photo")
def get_user_photo(
    user_id: str,
    _viewer: CurrentUser,
    profiles: ProfileServiceDep,
) -> Response:
    photo = profiles.get_photo(user_id)
    return Response(
        content=photo.data,
        media_type=photo.content_type,
        headers={"Cache-Control": "private, max-age=60"},
    )


@router.get("/{user_id}", response_model=PublicProfile)
def get_user(
    user_id: str,
    viewer: CurrentUser,
    profiles: ProfileServiceDep,
) -> PublicProfile:
    return profiles.public_profile(viewer, user_id)
