"""Friends routes."""

from uuid import UUID

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.user import User
from app.schemas.common import MessageOut
from app.schemas.friends import (
    FriendListOut,
    FriendRequestIn,
    FriendRequestsOut,
    FriendshipOut,
)
from app.services import friends as friends_service

router = APIRouter(prefix="/friends", tags=["friends"])


@router.get("", response_model=FriendListOut)
def list_friends(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> FriendListOut:
    return FriendListOut(friends=friends_service.list_friends(db, user))


@router.get("/requests", response_model=FriendRequestsOut)
def list_requests(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> FriendRequestsOut:
    incoming, outgoing = friends_service.list_requests(db, user)
    return FriendRequestsOut(incoming=incoming, outgoing=outgoing)


@router.post("/requests", response_model=FriendshipOut)
def send_request(
    body: FriendRequestIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> FriendshipOut:
    return friends_service.send_request(db, user, body.username)


@router.post("/requests/{request_id}/accept", response_model=FriendshipOut)
def accept(
    request_id: UUID,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> FriendshipOut:
    return friends_service.accept_request(db, user, request_id)


@router.post("/requests/{request_id}/decline", response_model=FriendshipOut)
def decline(
    request_id: UUID,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> FriendshipOut:
    return friends_service.decline_request(db, user, request_id)


@router.delete("/{user_id}", response_model=MessageOut)
def unfriend(
    user_id: UUID,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> MessageOut:
    friends_service.unfriend(db, user, user_id)
    return MessageOut(detail="unfriended")
