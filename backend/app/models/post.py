"""Community posts, images, comments, likes."""

from __future__ import annotations

import uuid
from datetime import datetime

from geoalchemy2 import Geography
from sqlalchemy import (
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class Post(Base):
    __tablename__ = "posts"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    author_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    caption: Mapped[str | None] = mapped_column(Text, nullable=True)
    ride_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("rides.id", ondelete="SET NULL"), nullable=True
    )
    distance_km: Mapped[float | None] = mapped_column(Float, nullable=True)
    duration_s: Mapped[int | None] = mapped_column(Integer, nullable=True)
    route_snapshot = mapped_column(
        Geography(geometry_type="LINESTRING", srid=4326), nullable=True
    )
    like_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    comment_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False, index=True
    )

    author = relationship("User")
    images: Mapped[list[PostImage]] = relationship(
        back_populates="post", cascade="all, delete-orphan", order_by="PostImage.sort_order"
    )
    comments: Mapped[list[Comment]] = relationship(
        back_populates="post", cascade="all, delete-orphan"
    )
    likes: Mapped[list[Like]] = relationship(
        back_populates="post", cascade="all, delete-orphan"
    )


class PostImage(Base):
    __tablename__ = "post_images"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    post_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("posts.id", ondelete="CASCADE"), nullable=False, index=True
    )
    file_path: Mapped[str] = mapped_column(String(512), nullable=False)
    thumb_path: Mapped[str] = mapped_column(String(512), nullable=False)
    sort_order: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    width: Mapped[int | None] = mapped_column(Integer, nullable=True)
    height: Mapped[int | None] = mapped_column(Integer, nullable=True)

    post: Mapped[Post] = relationship(back_populates="images")


class Comment(Base):
    __tablename__ = "comments"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    post_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("posts.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    body: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    post: Mapped[Post] = relationship(back_populates="comments")
    user = relationship("User")


class Like(Base):
    __tablename__ = "likes"
    __table_args__ = (UniqueConstraint("post_id", "user_id", name="uq_post_like"),)

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    post_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("posts.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    post: Mapped[Post] = relationship(back_populates="likes")
    user = relationship("User")
