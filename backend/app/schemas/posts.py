"""Community post schemas."""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field

from app.schemas.common import ORMModel, UserPublic


class PostImageOut(ORMModel):
    id: UUID
    file_path: str
    thumb_path: str
    sort_order: int
    width: int | None = None
    height: int | None = None


class CommentOut(ORMModel):
    id: UUID
    post_id: UUID
    user_id: UUID
    body: str
    created_at: datetime
    user: UserPublic | None = None


class CommentIn(BaseModel):
    body: str = Field(..., min_length=1, max_length=2000)


class PostOut(ORMModel):
    id: UUID
    author_id: UUID
    caption: str | None = None
    ride_id: UUID | None = None
    distance_km: float | None = None
    duration_s: int | None = None
    like_count: int
    comment_count: int
    created_at: datetime
    author: UserPublic | None = None
    images: list[PostImageOut] = []
    liked_by_me: bool = False


class PostFeedOut(BaseModel):
    posts: list[PostOut]
    next_cursor: str | None = None


class LikeOut(BaseModel):
    liked: bool
    like_count: int
