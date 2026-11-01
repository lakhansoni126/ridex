"""Auth routes."""

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.schemas.auth import LoginIn, LogoutIn, RefreshIn, RegisterIn, TokenOut
from app.schemas.common import MessageOut
from app.services import auth as auth_service

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", response_model=TokenOut)
def register(body: RegisterIn, db: Session = Depends(get_db)) -> TokenOut:
    return auth_service.register(db, body)


@router.post("/login", response_model=TokenOut)
def login(body: LoginIn, db: Session = Depends(get_db)) -> TokenOut:
    return auth_service.login(db, body)


@router.post("/refresh", response_model=TokenOut)
def refresh(body: RefreshIn, db: Session = Depends(get_db)) -> TokenOut:
    return auth_service.refresh(db, body.refresh_token)


@router.post("/logout", response_model=MessageOut)
def logout(body: LogoutIn, db: Session = Depends(get_db)) -> MessageOut:
    auth_service.logout(db, body.refresh_token)
    return MessageOut(detail="logged out")
