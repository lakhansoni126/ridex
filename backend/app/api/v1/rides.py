"""Group rides routes."""

from uuid import UUID

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.enums import RideStatus
from app.models.user import User
from app.schemas.common import LocationBatchIn
from app.schemas.rides import (
    ParticipantOut,
    ParticipantStatusIn,
    RideCreateIn,
    RideJoinIn,
    RideListOut,
    RideOut,
    RideUpdateIn,
)
from app.services import rides as rides_service
from app.ws.manager import ws_manager

router = APIRouter(prefix="/rides", tags=["rides"])


@router.get("", response_model=RideListOut)
def list_rides(
    status: RideStatus | None = None,
    near: str | None = Query(None, description="lon,lat"),
    radius_m: float = 50000,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
) -> RideListOut:
    lon = lat = None
    if near:
        parts = near.split(",")
        if len(parts) == 2:
            lon, lat = float(parts[0]), float(parts[1])
    rides = rides_service.list_rides(
        db, status_filter=status, near_lon=lon, near_lat=lat, radius_m=radius_m
    )
    return RideListOut(rides=rides)


@router.post("", response_model=RideOut)
def create_ride(
    body: RideCreateIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> RideOut:
    return rides_service.create_ride(db, user, body)


@router.post("/join", response_model=RideOut)
def join_ride(
    body: RideJoinIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> RideOut:
    return rides_service.join_ride(db, user, body)


@router.get("/{ride_id}", response_model=RideOut)
def get_ride(
    ride_id: UUID,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> RideOut:
    return rides_service.get_ride(db, ride_id, user)


@router.patch("/{ride_id}", response_model=RideOut)
async def patch_ride(
    ride_id: UUID,
    body: RideUpdateIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> RideOut:
    out = rides_service.update_ride(db, user, ride_id, body)
    if body.status is not None:
        await ws_manager.broadcast_ride(
            ride_id, {"type": "ride_status", "status": body.status.value}
        )
    return out


@router.post("/{ride_id}/start", response_model=RideOut)
async def start_ride(
    ride_id: UUID,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> RideOut:
    out = rides_service.start_ride(db, user, ride_id)
    await ws_manager.broadcast_ride(ride_id, {"type": "ride_status", "status": "live"})
    return out


@router.post("/{ride_id}/end", response_model=RideOut)
async def end_ride(
    ride_id: UUID,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> RideOut:
    out = rides_service.end_ride(db, user, ride_id)
    await ws_manager.broadcast_ride(ride_id, {"type": "ride_status", "status": "ended"})
    return out


@router.post("/{ride_id}/participants/{user_id}/remove", response_model=RideOut)
async def remove_participant(
    ride_id: UUID,
    user_id: UUID,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> RideOut:
    out = rides_service.remove_participant(db, user, ride_id, user_id)
    await ws_manager.broadcast_ride(
        ride_id, {"type": "participant_removed", "user_id": str(user_id)}
    )
    return out


@router.patch("/{ride_id}/me/status", response_model=ParticipantOut)
async def patch_my_status(
    ride_id: UUID,
    body: ParticipantStatusIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> ParticipantOut:
    out = rides_service.update_my_status(db, user, ride_id, body.status)
    await ws_manager.broadcast_ride(
        ride_id,
        {
            "type": "participant_update",
            "user_id": str(user.id),
            "status": out.status.value,
            "last_seen_at": out.last_seen_at.isoformat() if out.last_seen_at else None,
        },
    )
    return out


@router.post("/{ride_id}/locations")
async def post_locations(
    ride_id: UUID,
    body: LocationBatchIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    result = rides_service.ingest_locations(db, user, ride_id, body)
    await ws_manager.broadcast_ride(
        ride_id,
        {
            "type": "participant_update",
            "user_id": str(user.id),
            "lat": result["lat"],
            "lon": result["lon"],
            "status": result["status"],
            "last_seen_at": result["last_seen_at"],
            "distance_to_host_m": result.get("distance_to_host_m"),
            "distance_to_destination_m": result.get("distance_to_destination_m"),
        },
        exclude=user.id,
    )
    return result
