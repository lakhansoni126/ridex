"""Friends service."""

from __future__ import annotations

from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import and_, or_, select
from sqlalchemy.orm import Session, joinedload

from app.models.enums import FriendshipStatus
from app.models.friendship import Friendship
from app.models.user import User
from app.schemas.common import UserPublic
from app.schemas.friends import FriendshipOut


def _pair_filter(a: UUID, b: UUID):
    return or_(
        and_(Friendship.requester_id == a, Friendship.addressee_id == b),
        and_(Friendship.requester_id == b, Friendship.addressee_id == a),
    )


def send_request(db: Session, me: User, username: str) -> FriendshipOut:
    target = db.scalar(select(User).where(User.username == username.strip().lower()))
    if target is None:
        raise HTTPException(status_code=404, detail="User not found")
    if target.id == me.id:
        raise HTTPException(status_code=400, detail="Cannot friend yourself")

    existing = db.scalar(select(Friendship).where(_pair_filter(me.id, target.id)))
    if existing:
        if existing.status == FriendshipStatus.accepted:
            raise HTTPException(status_code=409, detail="Already friends")
        if existing.status == FriendshipStatus.pending:
            raise HTTPException(status_code=409, detail="Request already pending")
        if existing.status == FriendshipStatus.blocked:
            raise HTTPException(status_code=403, detail="Cannot send request")
        existing.requester_id = me.id
        existing.addressee_id = target.id
        existing.status = FriendshipStatus.pending
        db.commit()
        db.refresh(existing)
        return _friendship_out(existing)

    fr = Friendship(requester_id=me.id, addressee_id=target.id, status=FriendshipStatus.pending)
    db.add(fr)
    db.commit()
    db.refresh(fr)
    fr = db.scalar(
        select(Friendship)
        .options(joinedload(Friendship.requester), joinedload(Friendship.addressee))
        .where(Friendship.id == fr.id)
    )
    return _friendship_out(fr)


def list_friends(db: Session, me: User) -> list[UserPublic]:
    rows = db.scalars(
        select(Friendship)
        .options(joinedload(Friendship.requester), joinedload(Friendship.addressee))
        .where(
            Friendship.status == FriendshipStatus.accepted,
            or_(Friendship.requester_id == me.id, Friendship.addressee_id == me.id),
        )
    ).all()
    result: list[UserPublic] = []
    for fr in rows:
        other = fr.addressee if fr.requester_id == me.id else fr.requester
        result.append(UserPublic.model_validate(other))
    return result


def list_requests(db: Session, me: User) -> tuple[list[FriendshipOut], list[FriendshipOut]]:
    rows = db.scalars(
        select(Friendship)
        .options(joinedload(Friendship.requester), joinedload(Friendship.addressee))
        .where(
            Friendship.status == FriendshipStatus.pending,
            or_(Friendship.requester_id == me.id, Friendship.addressee_id == me.id),
        )
    ).all()
    incoming, outgoing = [], []
    for fr in rows:
        out = _friendship_out(fr)
        if fr.addressee_id == me.id:
            incoming.append(out)
        else:
            outgoing.append(out)
    return incoming, outgoing


def accept_request(db: Session, me: User, request_id: UUID) -> FriendshipOut:
    fr = db.get(Friendship, request_id)
    if fr is None or fr.addressee_id != me.id:
        raise HTTPException(status_code=404, detail="Request not found")
    if fr.status != FriendshipStatus.pending:
        raise HTTPException(status_code=400, detail="Request is not pending")
    fr.status = FriendshipStatus.accepted
    db.commit()
    db.refresh(fr)
    fr = db.scalar(
        select(Friendship)
        .options(joinedload(Friendship.requester), joinedload(Friendship.addressee))
        .where(Friendship.id == fr.id)
    )
    return _friendship_out(fr)


def decline_request(db: Session, me: User, request_id: UUID) -> FriendshipOut:
    fr = db.get(Friendship, request_id)
    if fr is None or fr.addressee_id != me.id:
        raise HTTPException(status_code=404, detail="Request not found")
    if fr.status != FriendshipStatus.pending:
        raise HTTPException(status_code=400, detail="Request is not pending")
    fr.status = FriendshipStatus.declined
    db.commit()
    db.refresh(fr)
    return _friendship_out(fr)


def unfriend(db: Session, me: User, user_id: UUID) -> None:
    fr = db.scalar(
        select(Friendship).where(
            Friendship.status == FriendshipStatus.accepted,
            _pair_filter(me.id, user_id),
        )
    )
    if fr is None:
        raise HTTPException(status_code=404, detail="Friendship not found")
    db.delete(fr)
    db.commit()


def are_friends(db: Session, a: UUID, b: UUID) -> bool:
    fr = db.scalar(
        select(Friendship).where(
            Friendship.status == FriendshipStatus.accepted,
            _pair_filter(a, b),
        )
    )
    return fr is not None


def _friendship_out(fr: Friendship) -> FriendshipOut:
    return FriendshipOut(
        id=fr.id,
        requester_id=fr.requester_id,
        addressee_id=fr.addressee_id,
        status=fr.status,
        created_at=fr.created_at,
        updated_at=fr.updated_at,
        requester=UserPublic.model_validate(fr.requester) if fr.requester else None,
        addressee=UserPublic.model_validate(fr.addressee) if fr.addressee else None,
    )
