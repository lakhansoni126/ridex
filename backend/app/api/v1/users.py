"""User profile routes."""

from uuid import UUID

from fastapi import APIRouter, Depends, File, UploadFile
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.user import User
from app.schemas.auth import UserOut, UserUpdateIn
from app.schemas.common import UserPublic
from app.services.media import save_image

router = APIRouter(prefix="/users", tags=["users"])


@router.get("/me", response_model=UserOut)
def me(user: User = Depends(get_current_user)) -> UserOut:
    return UserOut.model_validate(user)


@router.patch("/me", response_model=UserOut)
def update_me(
    body: UserUpdateIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> UserOut:
    if body.display_name is not None:
        user.display_name = body.display_name
    if body.bio is not None:
        user.bio = body.bio
    db.commit()
    db.refresh(user)
    return UserOut.model_validate(user)


@router.post("/me/avatar", response_model=UserOut)
async def upload_avatar(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> UserOut:
    path, _thumb, _w, _h = await save_image(file, kind="avatars")
    user.avatar_path = path
    db.commit()
    db.refresh(user)
    return UserOut.model_validate(user)


@router.get("/{user_id}/profile", response_model=UserPublic)
def public_profile(
    user_id: UUID,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
) -> UserPublic:
    u = db.get(User, user_id)
    if u is None or u.deleted_at is not None:
        from fastapi import HTTPException

        raise HTTPException(status_code=404, detail="User not found")
    return UserPublic.model_validate(u)
