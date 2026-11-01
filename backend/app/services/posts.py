"""Community posts service."""

from __future__ import annotations

from base64 import urlsafe_b64decode, urlsafe_b64encode
from datetime import datetime
from uuid import UUID

from fastapi import HTTPException, UploadFile
from sqlalchemy import select
from sqlalchemy.orm import Session, joinedload

from app.models.post import Comment, Like, Post, PostImage
from app.models.user import User
from app.schemas.common import UserPublic
from app.schemas.posts import CommentOut, PostImageOut, PostOut
from app.services.media import save_image


def _post_out(post: Post, *, liked_by_me: bool = False) -> PostOut:
    return PostOut(
        id=post.id,
        author_id=post.author_id,
        caption=post.caption,
        ride_id=post.ride_id,
        distance_km=post.distance_km,
        duration_s=post.duration_s,
        like_count=post.like_count,
        comment_count=post.comment_count,
        created_at=post.created_at,
        author=UserPublic.model_validate(post.author) if post.author else None,
        images=[PostImageOut.model_validate(i) for i in (post.images or [])],
        liked_by_me=liked_by_me,
    )


def _encode_cursor(created_at: datetime, post_id: UUID) -> str:
    raw = f"{created_at.isoformat()}|{post_id}"
    return urlsafe_b64encode(raw.encode()).decode()


def _decode_cursor(cursor: str) -> tuple[datetime, UUID]:
    try:
        raw = urlsafe_b64decode(cursor.encode()).decode()
        ts, pid = raw.split("|", 1)
        return datetime.fromisoformat(ts), UUID(pid)
    except Exception as exc:
        raise HTTPException(status_code=400, detail="Invalid cursor") from exc


async def create_post_async(
    db: Session,
    me: User,
    *,
    caption: str | None,
    ride_id: UUID | None,
    distance_km: float | None,
    duration_s: int | None,
    images: list[UploadFile],
) -> PostOut:
    if not images:
        raise HTTPException(status_code=400, detail="At least one image required")
    if len(images) > 8:
        raise HTTPException(status_code=400, detail="Max 8 images")

    saved: list[tuple[str, str, int | None, int | None]] = []
    for upload in images:
        saved.append(await save_image(upload, kind="posts"))

    post = Post(
        author_id=me.id,
        caption=caption,
        ride_id=ride_id,
        distance_km=distance_km,
        duration_s=duration_s,
    )
    db.add(post)
    db.flush()
    for idx, (file_path, thumb_path, width, height) in enumerate(saved):
        db.add(
            PostImage(
                post_id=post.id,
                file_path=file_path,
                thumb_path=thumb_path,
                sort_order=idx,
                width=width,
                height=height,
            )
        )
    db.commit()
    return get_post(db, post.id, me)


def get_post(db: Session, post_id: UUID, me: User | None = None) -> PostOut:
    post = db.scalar(
        select(Post)
        .options(joinedload(Post.author), joinedload(Post.images))
        .where(Post.id == post_id)
    )
    if post is None:
        raise HTTPException(status_code=404, detail="Post not found")
    liked = False
    if me:
        liked = (
            db.scalar(
                select(Like.id).where(Like.post_id == post_id, Like.user_id == me.id)
            )
            is not None
        )
    return _post_out(post, liked_by_me=liked)


def feed(
    db: Session,
    me: User,
    *,
    cursor: str | None = None,
    limit: int = 20,
) -> tuple[list[PostOut], str | None]:
    limit = max(1, min(limit, 50))
    q = (
        select(Post)
        .options(joinedload(Post.author), joinedload(Post.images))
        .order_by(Post.created_at.desc(), Post.id.desc())
    )
    if cursor:
        ts, pid = _decode_cursor(cursor)
        q = q.where(
            (Post.created_at < ts) | ((Post.created_at == ts) & (Post.id < pid))
        )
    rows = db.scalars(q.limit(limit + 1)).unique().all()
    has_more = len(rows) > limit
    rows = rows[:limit]
    liked_ids: set[UUID] = set()
    if rows:
        ids = [r.id for r in rows]
        liked_ids = set(
            db.scalars(
                select(Like.post_id).where(Like.user_id == me.id, Like.post_id.in_(ids))
            ).all()
        )
    posts = [_post_out(r, liked_by_me=r.id in liked_ids) for r in rows]
    next_cursor = None
    if has_more and rows:
        last = rows[-1]
        next_cursor = _encode_cursor(last.created_at, last.id)
    return posts, next_cursor


def toggle_like(db: Session, me: User, post_id: UUID) -> tuple[bool, int]:
    post = db.get(Post, post_id)
    if post is None:
        raise HTTPException(status_code=404, detail="Post not found")
    existing = db.scalar(
        select(Like).where(Like.post_id == post_id, Like.user_id == me.id)
    )
    if existing:
        db.delete(existing)
        post.like_count = max(0, post.like_count - 1)
        db.commit()
        return False, post.like_count
    db.add(Like(post_id=post_id, user_id=me.id))
    post.like_count += 1
    db.commit()
    return True, post.like_count


def add_comment(db: Session, me: User, post_id: UUID, body: str) -> CommentOut:
    post = db.get(Post, post_id)
    if post is None:
        raise HTTPException(status_code=404, detail="Post not found")
    c = Comment(post_id=post_id, user_id=me.id, body=body.strip())
    db.add(c)
    post.comment_count += 1
    db.commit()
    db.refresh(c)
    c = db.scalar(
        select(Comment).options(joinedload(Comment.user)).where(Comment.id == c.id)
    )
    assert c is not None
    return CommentOut(
        id=c.id,
        post_id=c.post_id,
        user_id=c.user_id,
        body=c.body,
        created_at=c.created_at,
        user=UserPublic.model_validate(c.user) if c.user else None,
    )


def list_comments(db: Session, post_id: UUID) -> list[CommentOut]:
    if db.get(Post, post_id) is None:
        raise HTTPException(status_code=404, detail="Post not found")
    rows = db.scalars(
        select(Comment)
        .options(joinedload(Comment.user))
        .where(Comment.post_id == post_id)
        .order_by(Comment.created_at.asc())
    ).all()
    return [
        CommentOut(
            id=c.id,
            post_id=c.post_id,
            user_id=c.user_id,
            body=c.body,
            created_at=c.created_at,
            user=UserPublic.model_validate(c.user) if c.user else None,
        )
        for c in rows
    ]
