"""Ride schemas."""

from datetime import datetime
from typing import Any
from uuid import UUID

from pydantic import BaseModel, Field

from app.models.enums import ParticipantRole, ParticipantStatus, RideStatus, RideVisibility
from app.schemas.common import GeoPoint, LocationBatchIn, ORMModel, UserPublic


class WaypointIn(BaseModel):
    lat: float = Field(..., ge=-90, le=90)
    lon: float = Field(..., ge=-180, le=180)
    name: str | None = None


class RideCreateIn(BaseModel):
    title: str = Field(..., min_length=1, max_length=200)
    description: str | None = None
    visibility: RideVisibility = RideVisibility.public
    scheduled_at: datetime | None = None
    start: GeoPoint | None = None
    destination: GeoPoint | None = None
    waypoints: list[WaypointIn] | None = None


class RideUpdateIn(BaseModel):
    title: str | None = Field(None, min_length=1, max_length=200)
    description: str | None = None
    visibility: RideVisibility | None = None
    status: RideStatus | None = None
    scheduled_at: datetime | None = None


class RideJoinIn(BaseModel):
    join_code: str | None = None
    invite_token: UUID | None = None


class ParticipantStatusIn(BaseModel):
    status: ParticipantStatus


class ParticipantOut(ORMModel):
    id: UUID
    ride_id: UUID
    user_id: UUID
    role: ParticipantRole
    status: ParticipantStatus
    last_seen_at: datetime | None = None
    distance_to_host_m: float | None = None
    distance_to_destination_m: float | None = None
    joined_at: datetime
    user: UserPublic | None = None
    lat: float | None = None
    lon: float | None = None


class RideOut(ORMModel):
    id: UUID
    host_id: UUID
    title: str
    description: str | None = None
    visibility: RideVisibility
    status: RideStatus
    join_code: str
    invite_token: UUID
    scheduled_at: datetime | None = None
    started_at: datetime | None = None
    ended_at: datetime | None = None
    waypoints: list[dict[str, Any]] | None = None
    created_at: datetime
    updated_at: datetime
    start_lat: float | None = None
    start_lon: float | None = None
    dest_lat: float | None = None
    dest_lon: float | None = None
    participants: list[ParticipantOut] = []


class RideListOut(BaseModel):
    rides: list[RideOut]


# Re-export for API
LocationBatchIn = LocationBatchIn
