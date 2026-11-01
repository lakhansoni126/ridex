"""Location share routes."""

from uuid import UUID

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.location import LocationShareGrant
from app.models.user import User
from app.schemas.common import LocationBatchIn
from app.schemas.shares import (
    LocationShareCreateIn,
    LocationShareOut,
    LocationSharesListOut,
)
from app.services import shares as shares_service
from app.ws.manager import ws_manager

router = APIRouter(prefix="/location-shares", tags=["location-shares"])


@router.post("", response_model=LocationShareOut)
def create_share(
    body: LocationShareCreateIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> LocationShareOut:
    return shares_service.create_share(db, user, body)


@router.get("", response_model=LocationSharesListOut)
def list_shares(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> LocationSharesListOut:
    mine, shared = shares_service.list_shares(db, user)
    return LocationSharesListOut(mine=mine, shared_with_me=shared)


@router.post("/{share_id}/stop", response_model=LocationShareOut)
async def stop_share(
    share_id: UUID,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> LocationShareOut:
    out = shares_service.stop_share(db, user, share_id)
    viewers = list(
        db.scalars(
            select(LocationShareGrant.friend_user_id).where(
                LocationShareGrant.share_id == share_id
            )
        ).all()
    )
    await ws_manager.broadcast_share_viewers(
        user.id, viewers, {"type": "share_ended", "share_id": str(share_id)}
    )
    return out


@router.delete("/{share_id}/grants/{friend_id}", response_model=LocationShareOut)
async def revoke_grant(
    share_id: UUID,
    friend_id: UUID,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> LocationShareOut:
    out = shares_service.revoke_grant(db, user, share_id, friend_id)
    await ws_manager.send_to_user(
        friend_id, {"type": "share_ended", "share_id": str(share_id)}
    )
    return out


@router.post("/{share_id}/locations")
async def post_locations(
    share_id: UUID,
    body: LocationBatchIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    result = shares_service.ingest_share_locations(db, user, share_id, body)
    viewers = list(
        db.scalars(
            select(LocationShareGrant.friend_user_id).where(
                LocationShareGrant.share_id == share_id,
                LocationShareGrant.revoked_at.is_(None),
            )
        ).all()
    )
    await ws_manager.broadcast_share_viewers(
        user.id,
        viewers,
        {
            "type": "friend_location",
            "share_id": str(share_id),
            "user_id": str(user.id),
            "lat": result["lat"],
            "lon": result["lon"],
            "last_seen_at": result["last_seen_at"],
            "online": True,
        },
    )
    return result
