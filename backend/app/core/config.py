"""Application settings loaded from environment."""

from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # Database
    database_url: str = "postgresql+psycopg://ridex:ridex_dev_password@localhost:5432/ridex"

    # API
    api_host: str = "0.0.0.0"
    api_port: int = 8000
    api_prefix: str = "/api/v1"
    cors_origins: str = "*"

    # JWT
    jwt_secret: str = "change-me-to-a-long-random-string"
    jwt_algorithm: str = "HS256"
    jwt_access_token_expire_minutes: int = 30
    jwt_refresh_token_expire_days: int = 30

    # Storage / media
    storage_root: Path = Path("/storage")
    media_max_upload_mb: int = 10
    media_allowed_types: str = "image/jpeg,image/png,image/webp,image/gif"
    thumbnail_max_size: int = 400

    # Location
    location_retention_days: int = 30
    location_rate_limit_moving_seconds: float = 2.0
    location_rate_limit_stationary_seconds: float = 15.0
    location_stationary_speed_mps: float = 0.5

    # Join codes
    join_code_length: int = 6

    @property
    def media_max_bytes(self) -> int:
        return self.media_max_upload_mb * 1024 * 1024

    @property
    def allowed_media_types(self) -> set[str]:
        return {t.strip() for t in self.media_allowed_types.split(",") if t.strip()}

    @property
    def cors_origin_list(self) -> list[str]:
        if self.cors_origins.strip() == "*":
            return ["*"]
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
