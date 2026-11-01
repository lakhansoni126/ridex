"""Location retention helpers."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from sqlalchemy import delete
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.models.location import LocationPoint

settings = get_settings()


def purge_old_location_points(db: Session, *, days: int | None = None) -> int:
    """Delete location_points older than retention window. Returns deleted count."""
    cutoff = datetime.now(timezone.utc) - timedelta(
        days=days if days is not None else settings.location_retention_days
    )
    result = db.execute(
        delete(LocationPoint).where(LocationPoint.recorded_at < cutoff)
    )
    db.commit()
    return result.rowcount or 0
