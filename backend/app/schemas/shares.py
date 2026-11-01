"""Location share schemas."""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field

from app.models.enums import ShareDuration
from app.schemas.common import LocationBatchIn, ORMModel, UserPublic


class LocationShareCreateIn(BaseModel):
    duration: ShareDuration
    friend_ids: list[UUID] = Field(..., min_length=1)


class LocationShareGrantOut(ORMModel):
    id: UUID
    share_id: UUID
    friend_user_id: UUID
    revoked_at: datetime | None = None
    friend: UserPublic | None = None


class LocationShareOut(ORMModel):
    id: UUID
    owner_id: UUID
    duration: ShareDuration
    expires_at: datetime | None = None
    is_active: bool
    last_seen_at: datetime | None = None
    created_at: datetime
    lat: float | None = None
    lon: float | None = None
    owner: UserPublic | None = None
    grants: list[LocationShareGrantOut] = []


class LocationSharesListOut(BaseModel):
    mine: list[LocationShareOut]
    shared_with_me: list[LocationShareOut]


LocationBatchIn = LocationBatchIn
