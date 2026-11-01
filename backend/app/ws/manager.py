"""In-memory WebSocket connection manager."""

from __future__ import annotations

import asyncio
from collections import defaultdict
from typing import Any
from uuid import UUID

from fastapi import WebSocket


class ConnectionManager:
    def __init__(self) -> None:
        self._ride_rooms: dict[UUID, dict[UUID, WebSocket]] = defaultdict(dict)
        self._share_subs: dict[UUID, WebSocket] = {}
        self._lock = asyncio.Lock()

    async def connect_ride(self, ride_id: UUID, user_id: UUID, ws: WebSocket) -> None:
        await ws.accept()
        async with self._lock:
            self._ride_rooms[ride_id][user_id] = ws

    async def disconnect_ride(self, ride_id: UUID, user_id: UUID) -> None:
        async with self._lock:
            room = self._ride_rooms.get(ride_id)
            if room:
                room.pop(user_id, None)
                if not room:
                    self._ride_rooms.pop(ride_id, None)

    async def broadcast_ride(
        self, ride_id: UUID, message: dict[str, Any], *, exclude: UUID | None = None
    ) -> None:
        async with self._lock:
            targets = list(self._ride_rooms.get(ride_id, {}).items())
        for uid, ws in targets:
            if exclude is not None and uid == exclude:
                continue
            try:
                await ws.send_json(message)
            except Exception:
                await self.disconnect_ride(ride_id, uid)

    async def connect_shares(self, user_id: UUID, ws: WebSocket) -> None:
        await ws.accept()
        async with self._lock:
            old = self._share_subs.get(user_id)
            if old is not None:
                try:
                    await old.close()
                except Exception:
                    pass
            self._share_subs[user_id] = ws

    async def disconnect_shares(self, user_id: UUID) -> None:
        async with self._lock:
            self._share_subs.pop(user_id, None)

    async def send_to_user(self, user_id: UUID, message: dict[str, Any]) -> None:
        async with self._lock:
            ws = self._share_subs.get(user_id)
        if ws is None:
            return
        try:
            await ws.send_json(message)
        except Exception:
            await self.disconnect_shares(user_id)

    async def broadcast_share_viewers(
        self, owner_id: UUID, viewer_ids: list[UUID], message: dict[str, Any]
    ) -> None:
        recipients = set(viewer_ids) | {owner_id}
        for uid in recipients:
            await self.send_to_user(uid, message)


ws_manager = ConnectionManager()
