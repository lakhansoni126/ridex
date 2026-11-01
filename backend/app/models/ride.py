"""Ride and participant models with PostGIS geography."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

from geoalchemy2 import Geography
from sqlalchemy import (
    DateTime,
    Enum,
    Float,
    ForeignKey,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.models.enums import ParticipantRole, ParticipantStatus, RideStatus, RideVisibility


class Ride(Base):
    __tablename__ = "rides"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    host_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    visibility: Mapped[RideVisibility] = mapped_column(
        Enum(RideVisibility, name="ride_visibility", native_enum=False),
        default=RideVisibility.public,
        nullable=False,
    )
    status: Mapped[RideStatus] = mapped_column(
        Enum(RideStatus, name="ride_status", native_enum=False),
        default=RideStatus.scheduled,
        nullable=False,
        index=True,
    )
    join_code: Mapped[str] = mapped_column(String(16), unique=True, nullable=False, index=True)
    invite_token: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), unique=True, default=uuid.uuid4, nullable=False
    )
    scheduled_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, index=True
    )
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    ended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    start_point = mapped_column(Geography(geometry_type="POINT", srid=4326), nullable=True)
    destination = mapped_column(Geography(geometry_type="POINT", srid=4326), nullable=True)
    route = mapped_column(Geography(geometry_type="LINESTRING", srid=4326), nullable=True)
    waypoints: Mapped[list[dict[str, Any]] | None] = mapped_column(JSONB, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    host = relationship("User", foreign_keys=[host_id])
    participants: Mapped[list[RideParticipant]] = relationship(
        back_populates="ride", cascade="all, delete-orphan"
    )


class RideParticipant(Base):
    __tablename__ = "ride_participants"
    __table_args__ = (
        UniqueConstraint("ride_id", "user_id", name="uq_ride_participant"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    ride_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("rides.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    role: Mapped[ParticipantRole] = mapped_column(
        Enum(ParticipantRole, name="participant_role", native_enum=False),
        default=ParticipantRole.participant,
        nullable=False,
    )
    status: Mapped[ParticipantStatus] = mapped_column(
        Enum(ParticipantStatus, name="participant_status", native_enum=False),
        default=ParticipantStatus.joined,
        nullable=False,
    )
    last_location = mapped_column(Geography(geometry_type="POINT", srid=4326), nullable=True)
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    distance_to_host_m: Mapped[float | None] = mapped_column(Float, nullable=True)
    distance_to_destination_m: Mapped[float | None] = mapped_column(Float, nullable=True)
    joined_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    ride: Mapped[Ride] = relationship(back_populates="participants")
    user = relationship("User")
