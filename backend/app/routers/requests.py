"""Lesson requests and their accept/decline decisions."""

from __future__ import annotations

from fastapi import APIRouter, status

from ..dependencies import ChatServiceDep, CurrentUser
from ..models.chat import (
    AcceptRequest,
    CreateRequest,
    DeclineRequest,
    RequestDirection,
    RequestStatus,
    RequestSummary,
)

router = APIRouter(prefix="/requests", tags=["requests"])


@router.post(
    "",
    response_model=RequestSummary,
    status_code=status.HTTP_201_CREATED,
)
def create_request(
    payload: CreateRequest,
    user: CurrentUser,
    chat: ChatServiceDep,
) -> RequestSummary:
    return chat.create_request(user, payload)


@router.get("", response_model=list[RequestSummary])
def list_requests(
    user: CurrentUser,
    chat: ChatServiceDep,
    direction: RequestDirection = RequestDirection.all,
    status: RequestStatus | None = None,
) -> list[RequestSummary]:
    return chat.list_requests(
        user,
        direction=direction,
        status=status,
    )


@router.get("/{request_id}", response_model=RequestSummary)
def get_request(
    request_id: str,
    user: CurrentUser,
    chat: ChatServiceDep,
) -> RequestSummary:
    return chat.get_request(user, request_id)


@router.post("/{request_id}/accept", response_model=RequestSummary)
def accept_request(
    request_id: str,
    user: CurrentUser,
    chat: ChatServiceDep,
    payload: AcceptRequest | None = None,
) -> RequestSummary:
    return chat.accept_request(user, request_id, payload)


@router.post("/{request_id}/decline", response_model=RequestSummary)
def decline_request(
    request_id: str,
    payload: DeclineRequest,
    user: CurrentUser,
    chat: ChatServiceDep,
) -> RequestSummary:
    return chat.decline_request(user, request_id, payload)
