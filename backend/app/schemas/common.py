"""Shared schema helpers."""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class ORMModel(BaseModel):
    model_config = ConfigDict(from_attributes=True)


class GeoPoint(BaseModel):
    lat: float = Field(..., ge=-90, le=90)
    lon: float = Field(..., ge=-180, le=180)


class MessageOut(BaseModel):
    detail: str


class CursorPage(BaseModel):
    next_cursor: str | None = None


class LocationPointIn(BaseModel):
    lat: float = Field(..., ge=-90, le=90)
    lon: float = Field(..., ge=-180, le=180)
    recorded_at: datetime
    speed_mps: float | None = None
    heading: float | None = None
    accuracy_m: float | None = None
    status: str | None = None


class LocationBatchIn(BaseModel):
    points: list[LocationPointIn] = Field(..., min_length=1, max_length=100)


class UserPublic(ORMModel):
    id: UUID
    username: str
    display_name: str
    avatar_path: str | None = None
    bio: str | None = None
