"""Location points and friend location shares."""

from __future__ import annotations

import uuid
from datetime import datetime

from geoalchemy2 import Geography
from sqlalchemy import (
    BigInteger,
    Boolean,
    DateTime,
    Enum,
    Float,
    ForeignKey,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.models.enums import ShareDuration


class LocationPoint(Base):
    __tablename__ = "location_points"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    ride_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("rides.id", ondelete="SET NULL"), nullable=True, index=True
    )
    location_share_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("location_shares.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    geom = mapped_column(Geography(geometry_type="POINT", srid=4326), nullable=False)
    speed_mps: Mapped[float | None] = mapped_column(Float, nullable=True)
    heading: Mapped[float | None] = mapped_column(Float, nullable=True)
    accuracy_m: Mapped[float | None] = mapped_column(Float, nullable=True)
    recorded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    received_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


class LocationShare(Base):
    __tablename__ = "location_shares"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    owner_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    duration: Mapped[ShareDuration] = mapped_column(
        Enum(ShareDuration, name="share_duration", native_enum=False),
        nullable=False,
    )
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    last_location = mapped_column(Geography(geometry_type="POINT", srid=4326), nullable=True)
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    owner = relationship("User")
    grants: Mapped[list[LocationShareGrant]] = relationship(
        back_populates="share", cascade="all, delete-orphan"
    )


class LocationShareGrant(Base):
    __tablename__ = "location_share_grants"
    __table_args__ = (
        UniqueConstraint("share_id", "friend_user_id", name="uq_share_grant"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    share_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("location_shares.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    friend_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    share: Mapped[LocationShare] = relationship(back_populates="grants")
    friend = relationship("User")
