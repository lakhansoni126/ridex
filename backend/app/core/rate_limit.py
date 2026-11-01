"""Simple in-memory location update rate limiter."""

from __future__ import annotations

import time
from threading import Lock
from uuid import UUID

from app.core.config import get_settings

settings = get_settings()


class LocationRateLimiter:
    """Per-user rate limit: faster when moving, slower when stationary."""

    def __init__(self) -> None:
        self._last: dict[UUID, float] = {}
        self._lock = Lock()

    def allow(self, user_id: UUID, *, speed_mps: float | None = None) -> bool:
        now = time.monotonic()
        stationary = (speed_mps is None) or (
            speed_mps <= settings.location_stationary_speed_mps
        )
        min_interval = (
            settings.location_rate_limit_stationary_seconds
            if stationary
            else settings.location_rate_limit_moving_seconds
        )
        with self._lock:
            last = self._last.get(user_id)
            if last is not None and (now - last) < min_interval:
                return False
            self._last[user_id] = now
            return True

    def clear(self, user_id: UUID | None = None) -> None:
        with self._lock:
            if user_id is None:
                self._last.clear()
            else:
                self._last.pop(user_id, None)


location_rate_limiter = LocationRateLimiter()
