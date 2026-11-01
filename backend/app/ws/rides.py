"""WebSocket hub for live group rides."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from sqlalchemy.orm import Session

from app.core.database import SessionLocal
from app.core.security import verify_access_token
from app.models.enums import ParticipantStatus
from app.models.ride import Ride
from app.schemas.common import LocationBatchIn, LocationPointIn
from app.services.rides import assert_participant, ingest_locations
from app.ws.manager import ws_manager

router = APIRouter()


def _auth_user(token: str | None) -> UUID:
    if not token:
        raise ValueError("missing token")
    return verify_access_token(token)


@router.websocket("/ws/rides/{ride_id}")
async def ride_ws(websocket: WebSocket, ride_id: UUID, token: str | None = None) -> None:
    try:
        user_id = _auth_user(token)
    except ValueError:
        await websocket.close(code=4401)
        return

    db: Session = SessionLocal()
    try:
        ride = db.get(Ride, ride_id)
        if ride is None:
            await websocket.close(code=4404)
            return
        try:
            assert_participant(db, ride_id, user_id)
        except Exception:
            await websocket.close(code=4403)
            return
    finally:
        db.close()

    await ws_manager.connect_ride(ride_id, user_id, websocket)
    try:
        while True:
            raw = await websocket.receive_text()
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                await websocket.send_json({"type": "error", "detail": "invalid json"})
                continue

            mtype = msg.get("type")
            if mtype == "ping":
                await websocket.send_json({"type": "pong"})
                continue

            if mtype == "status":
                status_val = msg.get("status")
                db = SessionLocal()
                try:
                    from app.services.rides import update_my_status
                    from app.models.user import User

                    user = db.get(User, user_id)
                    if user and status_val:
                        p = update_my_status(db, user, ride_id, ParticipantStatus(status_val))
                        await ws_manager.broadcast_ride(
                            ride_id,
                            {
                                "type": "participant_update",
                                "user_id": str(user_id),
                                "status": p.status.value,
                                "last_seen_at": datetime.now(timezone.utc).isoformat(),
                            },
                        )
                except Exception as exc:
                    await websocket.send_json({"type": "error", "detail": str(exc)})
                finally:
                    db.close()
                continue

            if mtype == "location":
                db = SessionLocal()
                try:
                    from app.models.user import User

                    user = db.get(User, user_id)
                    if user is None:
                        continue
                    point = LocationPointIn(
                        lat=float(msg["lat"]),
                        lon=float(msg["lon"]),
                        recorded_at=datetime.fromisoformat(
                            msg.get("recorded_at") or datetime.now(timezone.utc).isoformat()
                        ),
                        speed_mps=msg.get("speed") or msg.get("speed_mps"),
                        heading=msg.get("heading"),
                        accuracy_m=msg.get("accuracy") or msg.get("accuracy_m"),
                        status=msg.get("status"),
                    )
                    result = ingest_locations(
                        db, user, ride_id, LocationBatchIn(points=[point])
                    )
                    await ws_manager.broadcast_ride(
                        ride_id,
                        {
                            "type": "participant_update",
                            "user_id": str(user_id),
                            "lat": result["lat"],
                            "lon": result["lon"],
                            "status": result["status"],
                            "last_seen_at": result["last_seen_at"],
                            "distance_to_host_m": result.get("distance_to_host_m"),
                            "distance_to_destination_m": result.get(
                                "distance_to_destination_m"
                            ),
                        },
                    )
                except Exception as exc:
                    detail = getattr(exc, "detail", str(exc))
                    await websocket.send_json({"type": "error", "detail": detail})
                finally:
                    db.close()
                continue

            await websocket.send_json({"type": "error", "detail": f"unknown type {mtype}"})
    except WebSocketDisconnect:
        pass
    finally:
        await ws_manager.disconnect_ride(ride_id, user_id)
