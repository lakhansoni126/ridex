"""Friends schemas."""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field

from app.models.enums import FriendshipStatus
from app.schemas.common import ORMModel, UserPublic


class FriendRequestIn(BaseModel):
    username: str = Field(..., min_length=3, max_length=64)


class FriendshipOut(ORMModel):
    id: UUID
    requester_id: UUID
    addressee_id: UUID
    status: FriendshipStatus
    created_at: datetime
    updated_at: datetime
    requester: UserPublic | None = None
    addressee: UserPublic | None = None


class FriendListOut(BaseModel):
    friends: list[UserPublic]


class FriendRequestsOut(BaseModel):
    incoming: list[FriendshipOut]
    outgoing: list[FriendshipOut]
