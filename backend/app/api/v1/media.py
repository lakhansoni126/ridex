"""Serve local media files."""

from fastapi import APIRouter, Depends
from fastapi.responses import FileResponse

from app.core.deps import get_current_user
from app.models.user import User
from app.services.media import resolve_media_path

router = APIRouter(prefix="/media", tags=["media"])


@router.get("/{path:path}")
def get_media(path: str, _: User = Depends(get_current_user)) -> FileResponse:
    full = resolve_media_path(path)
    return FileResponse(full)
