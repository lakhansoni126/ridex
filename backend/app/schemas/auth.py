"""Auth schemas."""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field

from app.schemas.common import ORMModel


class RegisterIn(BaseModel):
    email: EmailStr
    username: str = Field(..., min_length=3, max_length=64, pattern=r"^[a-zA-Z0-9_]+$")
    password: str = Field(..., min_length=8, max_length=128)
    display_name: str = Field(..., min_length=1, max_length=120)


class LoginIn(BaseModel):
    email: EmailStr
    password: str


class RefreshIn(BaseModel):
    refresh_token: str


class LogoutIn(BaseModel):
    refresh_token: str


class UserOut(ORMModel):
    id: UUID
    email: EmailStr
    username: str
    display_name: str
    avatar_path: str | None = None
    bio: str | None = None
    created_at: datetime


class TokenOut(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user: UserOut


class UserUpdateIn(BaseModel):
    display_name: str | None = Field(None, min_length=1, max_length=120)
    bio: str | None = Field(None, max_length=2000)
