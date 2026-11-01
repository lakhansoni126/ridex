"""Local filesystem media storage with thumbnails."""

from __future__ import annotations

import re
import uuid
from pathlib import Path

from fastapi import HTTPException, UploadFile
from PIL import Image

from app.core.config import get_settings

settings = get_settings()

_SAFE_NAME = re.compile(r"[^a-zA-Z0-9._-]+")


def ensure_storage_dirs() -> None:
    root = Path(settings.storage_root)
    for sub in ("posts", "avatars", "thumbnails"):
        (root / sub).mkdir(parents=True, exist_ok=True)


def sanitize_filename(name: str) -> str:
    base = Path(name).name
    cleaned = _SAFE_NAME.sub("_", base).strip("._")
    if not cleaned:
        cleaned = "file"
    return cleaned[:180]


def _ext_for_content_type(content_type: str | None) -> str:
    mapping = {
        "image/jpeg": ".jpg",
        "image/png": ".png",
        "image/webp": ".webp",
        "image/gif": ".gif",
    }
    return mapping.get(content_type or "", ".bin")


async def save_image(
    upload: UploadFile,
    *,
    kind: str = "posts",
) -> tuple[str, str, int | None, int | None]:
    """Save image + thumbnail. Returns (file_path, thumb_path, width, height) relative to storage root."""
    ensure_storage_dirs()
    content_type = upload.content_type or ""
    if content_type not in settings.allowed_media_types:
        raise HTTPException(status_code=400, detail=f"Unsupported media type: {content_type}")

    data = await upload.read()
    if len(data) > settings.media_max_bytes:
        raise HTTPException(status_code=400, detail="File too large")
    if not data:
        raise HTTPException(status_code=400, detail="Empty file")

    safe = sanitize_filename(upload.filename or "image")
    stem = f"{uuid.uuid4().hex}_{Path(safe).stem}"
    ext = Path(safe).suffix.lower() or _ext_for_content_type(content_type)
    if ext not in {".jpg", ".jpeg", ".png", ".webp", ".gif"}:
        ext = _ext_for_content_type(content_type)

    root = Path(settings.storage_root)
    rel_file = f"{kind}/{stem}{ext}"
    rel_thumb = f"thumbnails/{stem}_thumb{ext if ext != '.gif' else '.jpg'}"
    abs_file = root / rel_file
    abs_thumb = root / rel_thumb

    abs_file.write_bytes(data)

    width = height = None
    try:
        with Image.open(abs_file) as img:
            width, height = img.size
            img = img.convert("RGB") if img.mode not in ("RGB", "L") else img
            img.thumbnail(
                (settings.thumbnail_max_size, settings.thumbnail_max_size),
                Image.Resampling.LANCZOS,
            )
            save_kwargs = {}
            if abs_thumb.suffix.lower() in {".jpg", ".jpeg"}:
                save_kwargs["quality"] = 85
            img.save(abs_thumb, **save_kwargs)
    except Exception as exc:
        abs_file.unlink(missing_ok=True)
        raise HTTPException(status_code=400, detail="Invalid image") from exc

    return rel_file.replace("\\", "/"), rel_thumb.replace("\\", "/"), width, height


def resolve_media_path(rel_path: str) -> Path:
    """Resolve a relative storage path safely (no path traversal)."""
    root = Path(settings.storage_root).resolve()
    cleaned = rel_path.replace("\\", "/").lstrip("/")
    if ".." in cleaned.split("/"):
        raise HTTPException(status_code=400, detail="Invalid path")
    full = (root / cleaned).resolve()
    if not str(full).startswith(str(root)):
        raise HTTPException(status_code=400, detail="Invalid path")
    if not full.is_file():
        raise HTTPException(status_code=404, detail="File not found")
    return full
