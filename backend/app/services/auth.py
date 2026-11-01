"""Authentication service."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.security import (
    create_access_token,
    create_refresh_token_value,
    hash_password,
    hash_token,
    verify_password,
)
from app.models.user import RefreshToken, User
from app.schemas.auth import LoginIn, RegisterIn, TokenOut, UserOut

settings = get_settings()


def _normalize_email(email: str) -> str:
    return email.strip().lower()


def _normalize_username(username: str) -> str:
    return username.strip().lower()


def _issue_tokens(db: Session, user: User) -> TokenOut:
    access = create_access_token(user.id)
    raw_refresh = create_refresh_token_value()
    expires = datetime.now(timezone.utc) + timedelta(
        days=settings.jwt_refresh_token_expire_days
    )
    db.add(
        RefreshToken(
            user_id=user.id,
            token_hash=hash_token(raw_refresh),
            expires_at=expires,
        )
    )
    db.commit()
    return TokenOut(
        access_token=access,
        refresh_token=raw_refresh,
        user=UserOut.model_validate(user),
    )


def register(db: Session, data: RegisterIn) -> TokenOut:
    email = _normalize_email(str(data.email))
    username = _normalize_username(data.username)

    existing = db.scalar(
        select(User).where((User.email == email) | (User.username == username))
    )
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Email or username already registered",
        )

    user = User(
        email=email,
        username=username,
        password_hash=hash_password(data.password),
        display_name=data.display_name.strip(),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return _issue_tokens(db, user)


def login(db: Session, data: LoginIn) -> TokenOut:
    email = _normalize_email(str(data.email))
    user = db.scalar(select(User).where(User.email == email))
    if user is None or user.deleted_at is not None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")
    if not verify_password(data.password, user.password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")
    return _issue_tokens(db, user)


def refresh(db: Session, raw_token: str) -> TokenOut:
    token_hash = hash_token(raw_token)
    match = db.scalar(
        select(RefreshToken).where(
            RefreshToken.token_hash == token_hash,
            RefreshToken.revoked_at.is_(None),
            RefreshToken.expires_at > datetime.now(timezone.utc),
        )
    )
    if match is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token")

    match.revoked_at = datetime.now(timezone.utc)
    user = db.get(User, match.user_id)
    if user is None or user.deleted_at is not None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found")
    db.commit()
    return _issue_tokens(db, user)


def logout(db: Session, raw_token: str) -> None:
    token_hash = hash_token(raw_token)
    match = db.scalar(
        select(RefreshToken).where(
            RefreshToken.token_hash == token_hash,
            RefreshToken.revoked_at.is_(None),
        )
    )
    if match:
        match.revoked_at = datetime.now(timezone.utc)
        db.commit()
