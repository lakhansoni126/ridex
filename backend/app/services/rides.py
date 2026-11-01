"""Group ride service."""

from __future__ import annotations

import secrets
import string
from datetime import datetime, timezone
from uuid import UUID

from fastapi import HTTPException, status
from geoalchemy2 import functions as geo_func
from sqlalchemy import select
from sqlalchemy.orm import Session, joinedload

from app.core.config import get_settings
from app.core.rate_limit import location_rate_limiter
from app.models.enums import ParticipantRole, ParticipantStatus, RideStatus, RideVisibility
from app.models.location import LocationPoint
from app.models.ride import Ride, RideParticipant
from app.models.user import User
from app.schemas.common import LocationBatchIn, UserPublic
from app.schemas.rides import (
    ParticipantOut,
    RideCreateIn,
    RideJoinIn,
    RideOut,
    RideUpdateIn,
)
from app.services.geo import geom_to_latlon, point_wkt

settings = get_settings()


def _gen_join_code(db: Session) -> str:
    alphabet = string.ascii_uppercase + string.digits
    for _ in range(20):
        code = "".join(secrets.choice(alphabet) for _ in range(settings.join_code_length))
        exists = db.scalar(select(Ride.id).where(Ride.join_code == code))
        if not exists:
            return code
    raise HTTPException(status_code=500, detail="Could not generate join code")


def _participant_out(p: RideParticipant) -> ParticipantOut:
    lat, lon = geom_to_latlon(p.last_location)
    return ParticipantOut(
        id=p.id,
        ride_id=p.ride_id,
        user_id=p.user_id,
        role=p.role,
        status=p.status,
        last_seen_at=p.last_seen_at,
        distance_to_host_m=p.distance_to_host_m,
        distance_to_destination_m=p.distance_to_destination_m,
        joined_at=p.joined_at,
        user=UserPublic.model_validate(p.user) if p.user else None,
        lat=lat,
        lon=lon,
    )


def ride_to_out(ride: Ride, *, include_participants: bool = True) -> RideOut:
    slat, slon = geom_to_latlon(ride.start_point)
    dlat, dlon = geom_to_latlon(ride.destination)
    participants = []
    if include_participants and ride.participants is not None:
        participants = [
            _participant_out(p)
            for p in ride.participants
            if p.status not in (ParticipantStatus.removed,)
        ]
    return RideOut(
        id=ride.id,
        host_id=ride.host_id,
        title=ride.title,
        description=ride.description,
        visibility=ride.visibility,
        status=ride.status,
        join_code=ride.join_code,
        invite_token=ride.invite_token,
        scheduled_at=ride.scheduled_at,
        started_at=ride.started_at,
        ended_at=ride.ended_at,
        waypoints=ride.waypoints,
        created_at=ride.created_at,
        updated_at=ride.updated_at,
        start_lat=slat,
        start_lon=slon,
        dest_lat=dlat,
        dest_lon=dlon,
        participants=participants,
    )


def _load_ride(db: Session, ride_id: UUID) -> Ride:
    ride = db.scalar(
        select(Ride)
        .options(
            joinedload(Ride.participants).joinedload(RideParticipant.user),
            joinedload(Ride.host),
        )
        .where(Ride.id == ride_id)
    )
    if ride is None:
        raise HTTPException(status_code=404, detail="Ride not found")
    return ride


def create_ride(db: Session, host: User, data: RideCreateIn) -> RideOut:
    ride = Ride(
        host_id=host.id,
        title=data.title.strip(),
        description=data.description,
        visibility=data.visibility,
        status=RideStatus.scheduled,
        join_code=_gen_join_code(db),
        scheduled_at=data.scheduled_at,
        start_point=point_wkt(data.start.lon, data.start.lat) if data.start else None,
        destination=point_wkt(data.destination.lon, data.destination.lat)
        if data.destination
        else None,
        waypoints=[w.model_dump() for w in data.waypoints] if data.waypoints else None,
    )
    db.add(ride)
    db.flush()
    db.add(
        RideParticipant(
            ride_id=ride.id,
            user_id=host.id,
            role=ParticipantRole.host,
            status=ParticipantStatus.joined,
        )
    )
    db.commit()
    return ride_to_out(_load_ride(db, ride.id))


def list_rides(
    db: Session,
    *,
    status_filter: RideStatus | None = None,
    near_lon: float | None = None,
    near_lat: float | None = None,
    radius_m: float = 50000,
) -> list[RideOut]:
    q = (
        select(Ride)
        .options(joinedload(Ride.participants).joinedload(RideParticipant.user))
        .where(Ride.visibility == RideVisibility.public)
        .where(Ride.status.in_([RideStatus.scheduled, RideStatus.live]))
    )
    if status_filter:
        q = q.where(Ride.status == status_filter)
    if near_lon is not None and near_lat is not None:
        origin = point_wkt(near_lon, near_lat)
        q = q.where(
            geo_func.ST_DWithin(Ride.start_point, origin, radius_m)
        )
    rides = db.scalars(q.order_by(Ride.scheduled_at.nulls_last(), Ride.created_at.desc())).unique().all()
    return [ride_to_out(r) for r in rides]


def get_ride(db: Session, ride_id: UUID, me: User) -> RideOut:
    ride = _load_ride(db, ride_id)
    if ride.visibility == RideVisibility.private:
        is_participant = any(p.user_id == me.id for p in ride.participants)
        if not is_participant:
            raise HTTPException(status_code=403, detail="Private ride")
    return ride_to_out(ride)


def join_ride(db: Session, me: User, data: RideJoinIn) -> RideOut:
    if not data.join_code and not data.invite_token:
        raise HTTPException(status_code=400, detail="join_code or invite_token required")
    q = select(Ride)
    if data.join_code:
        q = q.where(Ride.join_code == data.join_code.strip().upper().replace(" ", ""))
    else:
        q = q.where(Ride.invite_token == data.invite_token)
    ride = db.scalar(q)
    if ride is None:
        raise HTTPException(status_code=404, detail="Ride not found")
    if ride.status in (RideStatus.ended, RideStatus.cancelled):
        raise HTTPException(status_code=400, detail="Ride is not joinable")

    existing = db.scalar(
        select(RideParticipant).where(
            RideParticipant.ride_id == ride.id,
            RideParticipant.user_id == me.id,
        )
    )
    if existing:
        if existing.status == ParticipantStatus.removed:
            existing.status = ParticipantStatus.joined
            db.commit()
        return ride_to_out(_load_ride(db, ride.id))

    db.add(
        RideParticipant(
            ride_id=ride.id,
            user_id=me.id,
            role=ParticipantRole.participant,
            status=ParticipantStatus.joined,
        )
    )
    db.commit()
    return ride_to_out(_load_ride(db, ride.id))


def start_ride(db: Session, me: User, ride_id: UUID) -> RideOut:
    ride = _load_ride(db, ride_id)
    if ride.host_id != me.id:
        raise HTTPException(status_code=403, detail="Host only")
    if ride.status not in (RideStatus.scheduled, RideStatus.live):
        raise HTTPException(status_code=400, detail="Cannot start ride")
    ride.status = RideStatus.live
    ride.started_at = datetime.now(timezone.utc)
    db.commit()
    return ride_to_out(_load_ride(db, ride_id))


def end_ride(db: Session, me: User, ride_id: UUID) -> RideOut:
    ride = _load_ride(db, ride_id)
    if ride.host_id != me.id:
        raise HTTPException(status_code=403, detail="Host only")
    ride.status = RideStatus.ended
    ride.ended_at = datetime.now(timezone.utc)
    db.commit()
    return ride_to_out(_load_ride(db, ride_id))


def update_ride(db: Session, me: User, ride_id: UUID, data: RideUpdateIn) -> RideOut:
    ride = _load_ride(db, ride_id)
    if ride.host_id != me.id:
        raise HTTPException(status_code=403, detail="Host only")
    if data.title is not None:
        ride.title = data.title
    if data.description is not None:
        ride.description = data.description
    if data.visibility is not None:
        ride.visibility = data.visibility
    if data.status is not None:
        ride.status = data.status
        if data.status == RideStatus.cancelled:
            ride.ended_at = datetime.now(timezone.utc)
    if data.scheduled_at is not None:
        ride.scheduled_at = data.scheduled_at
    db.commit()
    return ride_to_out(_load_ride(db, ride_id))


def remove_participant(db: Session, me: User, ride_id: UUID, user_id: UUID) -> RideOut:
    ride = _load_ride(db, ride_id)
    if ride.host_id != me.id:
        raise HTTPException(status_code=403, detail="Host only")
    if user_id == ride.host_id:
        raise HTTPException(status_code=400, detail="Cannot remove host")
    p = db.scalar(
        select(RideParticipant).where(
            RideParticipant.ride_id == ride_id,
            RideParticipant.user_id == user_id,
        )
    )
    if p is None:
        raise HTTPException(status_code=404, detail="Participant not found")
    p.status = ParticipantStatus.removed
    db.commit()
    return ride_to_out(_load_ride(db, ride_id))


def update_my_status(
    db: Session, me: User, ride_id: UUID, new_status: ParticipantStatus
) -> ParticipantOut:
    if new_status == ParticipantStatus.removed:
        raise HTTPException(status_code=400, detail="Invalid status")
    p = db.scalar(
        select(RideParticipant)
        .options(joinedload(RideParticipant.user))
        .where(RideParticipant.ride_id == ride_id, RideParticipant.user_id == me.id)
    )
    if p is None or p.status == ParticipantStatus.removed:
        raise HTTPException(status_code=404, detail="Not a participant")
    if new_status == ParticipantStatus.left:
        p.status = ParticipantStatus.left
    else:
        p.status = new_status
    db.commit()
    db.refresh(p)
    return _participant_out(p)


def _get_active_participant(db: Session, ride_id: UUID, user_id: UUID) -> RideParticipant:
    p = db.scalar(
        select(RideParticipant).where(
            RideParticipant.ride_id == ride_id,
            RideParticipant.user_id == user_id,
        )
    )
    if p is None or p.status in (ParticipantStatus.removed, ParticipantStatus.left):
        raise HTTPException(status_code=403, detail="Not an active participant")
    return p


def ingest_locations(
    db: Session, me: User, ride_id: UUID, batch: LocationBatchIn
) -> dict:
    ride = db.get(Ride, ride_id)
    if ride is None:
        raise HTTPException(status_code=404, detail="Ride not found")
    if ride.status != RideStatus.live:
        raise HTTPException(status_code=400, detail="Ride is not live")
    p = _get_active_participant(db, ride_id, me.id)

    latest_speed = batch.points[-1].speed_mps
    if not location_rate_limiter.allow(me.id, speed_mps=latest_speed):
        raise HTTPException(status_code=429, detail="Location rate limit exceeded")

    now = datetime.now(timezone.utc)
    last = batch.points[-1]
    for pt in batch.points:
        db.add(
            LocationPoint(
                user_id=me.id,
                ride_id=ride_id,
                geom=point_wkt(pt.lon, pt.lat),
                speed_mps=pt.speed_mps,
                heading=pt.heading,
                accuracy_m=pt.accuracy_m,
                recorded_at=pt.recorded_at,
            )
        )
    p.last_location = point_wkt(last.lon, last.lat)
    p.last_seen_at = now
    if last.status:
        try:
            p.status = ParticipantStatus(last.status)
        except ValueError:
            pass

    # Distances via PostGIS
    if ride.start_point is not None or True:
        host_p = db.scalar(
            select(RideParticipant).where(
                RideParticipant.ride_id == ride_id,
                RideParticipant.user_id == ride.host_id,
            )
        )
        if host_p and host_p.last_location is not None:
            p.distance_to_host_m = db.scalar(
                select(
                    geo_func.ST_Distance(p.last_location, host_p.last_location)
                )
            )
        if ride.destination is not None:
            p.distance_to_destination_m = db.scalar(
                select(geo_func.ST_Distance(p.last_location, ride.destination))
            )

    db.commit()
    return {
        "accepted": len(batch.points),
        "lat": last.lat,
        "lon": last.lon,
        "status": p.status.value,
        "distance_to_host_m": p.distance_to_host_m,
        "distance_to_destination_m": p.distance_to_destination_m,
        "last_seen_at": now.isoformat(),
    }


def assert_participant(db: Session, ride_id: UUID, user_id: UUID) -> RideParticipant:
    return _get_active_participant(db, ride_id, user_id)
