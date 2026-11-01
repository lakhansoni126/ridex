"""Location sharing service."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import UUID

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session, joinedload

from app.core.rate_limit import location_rate_limiter
from app.models.enums import ShareDuration
from app.models.location import LocationPoint, LocationShare, LocationShareGrant
from app.models.user import User
from app.schemas.common import LocationBatchIn, UserPublic
from app.schemas.shares import LocationShareCreateIn, LocationShareGrantOut, LocationShareOut
from app.services.friends import are_friends
from app.services.geo import geom_to_latlon, point_wkt


def _expires_for(duration: ShareDuration, now: datetime) -> datetime | None:
    if duration == ShareDuration.one_hour:
        return now + timedelta(hours=1)
    if duration == ShareDuration.eight_hours:
        return now + timedelta(hours=8)
    return None


def _share_out(share: LocationShare) -> LocationShareOut:
    lat, lon = geom_to_latlon(share.last_location)
    grants = []
    for g in share.grants or []:
        grants.append(
            LocationShareGrantOut(
                id=g.id,
                share_id=g.share_id,
                friend_user_id=g.friend_user_id,
                revoked_at=g.revoked_at,
                friend=UserPublic.model_validate(g.friend) if g.friend else None,
            )
        )
    return LocationShareOut(
        id=share.id,
        owner_id=share.owner_id,
        duration=share.duration,
        expires_at=share.expires_at,
        is_active=share.is_active,
        last_seen_at=share.last_seen_at,
        created_at=share.created_at,
        lat=lat,
        lon=lon,
        owner=UserPublic.model_validate(share.owner) if share.owner else None,
        grants=grants,
    )


def _load_share(db: Session, share_id: UUID) -> LocationShare:
    share = db.scalar(
        select(LocationShare)
        .options(
            joinedload(LocationShare.owner),
            joinedload(LocationShare.grants).joinedload(LocationShareGrant.friend),
        )
        .where(LocationShare.id == share_id)
    )
    if share is None:
        raise HTTPException(status_code=404, detail="Share not found")
    return share


def create_share(db: Session, me: User, data: LocationShareCreateIn) -> LocationShareOut:
    now = datetime.now(timezone.utc)
    for fid in data.friend_ids:
        if not are_friends(db, me.id, fid):
            raise HTTPException(status_code=400, detail=f"Not friends with {fid}")
    share = LocationShare(
        owner_id=me.id,
        duration=data.duration,
        expires_at=_expires_for(data.duration, now),
        is_active=True,
    )
    db.add(share)
    db.flush()
    for fid in data.friend_ids:
        db.add(LocationShareGrant(share_id=share.id, friend_user_id=fid))
    db.commit()
    return _share_out(_load_share(db, share.id))


def list_shares(db: Session, me: User) -> tuple[list[LocationShareOut], list[LocationShareOut]]:
    now = datetime.now(timezone.utc)
    # deactivate expired
    expired = db.scalars(
        select(LocationShare).where(
            LocationShare.is_active.is_(True),
            LocationShare.expires_at.is_not(None),
            LocationShare.expires_at < now,
        )
    ).all()
    for s in expired:
        s.is_active = False
    if expired:
        db.commit()

    mine = db.scalars(
        select(LocationShare)
        .options(
            joinedload(LocationShare.owner),
            joinedload(LocationShare.grants).joinedload(LocationShareGrant.friend),
        )
        .where(LocationShare.owner_id == me.id, LocationShare.is_active.is_(True))
    ).unique().all()

    shared_ids = db.scalars(
        select(LocationShareGrant.share_id).where(
            LocationShareGrant.friend_user_id == me.id,
            LocationShareGrant.revoked_at.is_(None),
        )
    ).all()
    shared = []
    if shared_ids:
        shared = db.scalars(
            select(LocationShare)
            .options(
                joinedload(LocationShare.owner),
                joinedload(LocationShare.grants).joinedload(LocationShareGrant.friend),
            )
            .where(
                LocationShare.id.in_(shared_ids),
                LocationShare.is_active.is_(True),
            )
        ).unique().all()

    return [_share_out(s) for s in mine], [_share_out(s) for s in shared]


def stop_share(db: Session, me: User, share_id: UUID) -> LocationShareOut:
    share = _load_share(db, share_id)
    if share.owner_id != me.id:
        raise HTTPException(status_code=403, detail="Only owner can stop")
    share.is_active = False
    db.commit()
    return _share_out(_load_share(db, share_id))


def revoke_grant(db: Session, me: User, share_id: UUID, friend_id: UUID) -> LocationShareOut:
    share = _load_share(db, share_id)
    if share.owner_id != me.id:
        raise HTTPException(status_code=403, detail="Only owner can revoke")
    grant = db.scalar(
        select(LocationShareGrant).where(
            LocationShareGrant.share_id == share_id,
            LocationShareGrant.friend_user_id == friend_id,
        )
    )
    if grant is None:
        raise HTTPException(status_code=404, detail="Grant not found")
    grant.revoked_at = datetime.now(timezone.utc)
    db.commit()
    return _share_out(_load_share(db, share_id))


def ingest_share_locations(
    db: Session, me: User, share_id: UUID, batch: LocationBatchIn
) -> dict:
    share = db.get(LocationShare, share_id)
    if share is None or share.owner_id != me.id:
        raise HTTPException(status_code=404, detail="Share not found")
    now = datetime.now(timezone.utc)
    if not share.is_active:
        raise HTTPException(status_code=400, detail="Share inactive")
    if share.expires_at and share.expires_at < now:
        share.is_active = False
        db.commit()
        raise HTTPException(status_code=400, detail="Share expired")

    latest_speed = batch.points[-1].speed_mps
    if not location_rate_limiter.allow(me.id, speed_mps=latest_speed):
        raise HTTPException(status_code=429, detail="Location rate limit exceeded")

    last = batch.points[-1]
    for pt in batch.points:
        db.add(
            LocationPoint(
                user_id=me.id,
                location_share_id=share_id,
                geom=point_wkt(pt.lon, pt.lat),
                speed_mps=pt.speed_mps,
                heading=pt.heading,
                accuracy_m=pt.accuracy_m,
                recorded_at=pt.recorded_at,
            )
        )
    share.last_location = point_wkt(last.lon, last.lat)
    share.last_seen_at = now
    db.commit()
    return {
        "accepted": len(batch.points),
        "lat": last.lat,
        "lon": last.lon,
        "last_seen_at": now.isoformat(),
    }


def user_can_view_share(db: Session, share: LocationShare, user_id: UUID) -> bool:
    if share.owner_id == user_id and share.is_active:
        return True
    grant = db.scalar(
        select(LocationShareGrant).where(
            LocationShareGrant.share_id == share.id,
            LocationShareGrant.friend_user_id == user_id,
            LocationShareGrant.revoked_at.is_(None),
        )
    )
    return grant is not None and share.is_active
