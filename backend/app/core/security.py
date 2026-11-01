"""Password hashing and JWT helpers."""

from datetime import datetime, timedelta, timezone
from typing import Any
from uuid import UUID, uuid4

from jose import JWTError, jwt
from passlib.context import CryptContext

from app.core.config import get_settings

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
settings = get_settings()


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)


def create_access_token(
    subject: str | UUID,
    *,
    extra: dict[str, Any] | None = None,
    expires_delta: timedelta | None = None,
) -> str:
    expire = datetime.now(timezone.utc) + (
        expires_delta
        or timedelta(minutes=settings.jwt_access_token_expire_minutes)
    )
    payload: dict[str, Any] = {
        "sub": str(subject),
        "exp": expire,
        "type": "access",
        "jti": str(uuid4()),
    }
    if extra:
        payload.update(extra)
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def create_refresh_token_value() -> str:
    """Opaque refresh token (stored hashed in DB)."""
    return str(uuid4()) + str(uuid4())


def decode_token(token: str) -> dict[str, Any]:
    return jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])


def verify_access_token(token: str) -> UUID:
    try:
        payload = decode_token(token)
    except JWTError as exc:
        raise ValueError("Invalid token") from exc
    if payload.get("type") != "access":
        raise ValueError("Not an access token")
    sub = payload.get("sub")
    if not sub:
        raise ValueError("Missing subject")
    return UUID(str(sub))


def hash_token(raw: str) -> str:
    """SHA-256 hash for refresh tokens (indexed lookup)."""
    import hashlib

    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def verify_token_hash(raw: str, hashed: str) -> bool:
    return hash_token(raw) == hashed
