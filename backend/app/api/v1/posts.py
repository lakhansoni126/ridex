"""Community feed routes."""

from uuid import UUID

from fastapi import APIRouter, Depends, File, Form, UploadFile
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.user import User
from app.schemas.posts import CommentIn, CommentOut, LikeOut, PostFeedOut, PostOut
from app.services import posts as posts_service

router = APIRouter(prefix="/posts", tags=["posts"])


@router.get("", response_model=PostFeedOut)
def get_feed(
    cursor: str | None = None,
    limit: int = 20,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> PostFeedOut:
    posts, next_cursor = posts_service.feed(db, user, cursor=cursor, limit=limit)
    return PostFeedOut(posts=posts, next_cursor=next_cursor)


@router.post("", response_model=PostOut)
async def create_post(
    caption: str | None = Form(None),
    ride_id: UUID | None = Form(None),
    distance_km: float | None = Form(None),
    duration_s: int | None = Form(None),
    images: list[UploadFile] = File(...),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> PostOut:
    return await posts_service.create_post_async(
        db,
        user,
        caption=caption,
        ride_id=ride_id,
        distance_km=distance_km,
        duration_s=duration_s,
        images=images,
    )


@router.get("/{post_id}", response_model=PostOut)
def get_post(
    post_id: UUID,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> PostOut:
    return posts_service.get_post(db, post_id, user)


@router.post("/{post_id}/like", response_model=LikeOut)
def like_post(
    post_id: UUID,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> LikeOut:
    liked, count = posts_service.toggle_like(db, user, post_id)
    return LikeOut(liked=liked, like_count=count)


@router.get("/{post_id}/comments", response_model=list[CommentOut])
def get_comments(
    post_id: UUID,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
) -> list[CommentOut]:
    return posts_service.list_comments(db, post_id)


@router.post("/{post_id}/comments", response_model=CommentOut)
def post_comment(
    post_id: UUID,
    body: CommentIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> CommentOut:
    return posts_service.add_comment(db, user, post_id, body.body)
