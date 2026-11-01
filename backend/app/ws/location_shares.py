"""WebSocket hub for friend location shares."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.database import SessionLocal
from app.core.security import verify_access_token
from app.models.location import LocationShare, LocationShareGrant
from app.models.user import User
from app.schemas.common import LocationBatchIn, LocationPointIn
from app.services.shares import ingest_share_locations
from app.ws.manager import ws_manager

router = APIRouter()


@router.websocket("/ws/location-shares")
async def location_shares_ws(websocket: WebSocket, token: str | None = None) -> None:
    try:
        if not token:
            raise ValueError("missing token")
        user_id = verify_access_token(token)
    except ValueError:
        await websocket.close(code=4401)
        return

    await ws_manager.connect_shares(user_id, websocket)
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

            if mtype == "location":
                share_id_raw = msg.get("share_id")
                if not share_id_raw:
                    await websocket.send_json({"type": "error", "detail": "share_id required"})
                    continue
                share_id = UUID(str(share_id_raw))
                db: Session = SessionLocal()
                try:
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
                    )
                    result = ingest_share_locations(
                        db, user, share_id, LocationBatchIn(points=[point])
                    )
                    share = db.get(LocationShare, share_id)
                    viewers = []
                    if share:
                        viewers = list(
                            db.scalars(
                                select(LocationShareGrant.friend_user_id).where(
                                    LocationShareGrant.share_id == share_id,
                                    LocationShareGrant.revoked_at.is_(None),
                                )
                            ).all()
                        )
                    await ws_manager.broadcast_share_viewers(
                        user_id,
                        viewers,
                        {
                            "type": "friend_location",
                            "share_id": str(share_id),
                            "user_id": str(user_id),
                            "lat": result["lat"],
                            "lon": result["lon"],
                            "last_seen_at": result["last_seen_at"],
                            "online": True,
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
        await ws_manager.disconnect_shares(user_id)
