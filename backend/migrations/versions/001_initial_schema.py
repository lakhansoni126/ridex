"""Initial PostGIS schema for RideX.

Revision ID: 001_initial
Revises:
Create Date: 2026-11-01
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from geoalchemy2 import Geography
from sqlalchemy.dialects import postgresql

revision: str = "001_initial"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute("CREATE EXTENSION IF NOT EXISTS postgis")

    op.create_table(
        "users",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("email", sa.String(320), nullable=False),
        sa.Column("username", sa.String(64), nullable=False),
        sa.Column("password_hash", sa.Text(), nullable=False),
        sa.Column("display_name", sa.String(120), nullable=False),
        sa.Column("avatar_path", sa.String(512), nullable=True),
        sa.Column("bio", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_users_email", "users", ["email"], unique=True)
    op.create_index("ix_users_username", "users", ["username"], unique=True)

    op.create_table(
        "refresh_tokens",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("token_hash", sa.Text(), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_refresh_tokens_user_id", "refresh_tokens", ["user_id"])
    op.create_index("ix_refresh_tokens_token_hash", "refresh_tokens", ["token_hash"], unique=True)

    op.create_table(
        "friendships",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("requester_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("addressee_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("status", sa.String(32), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.UniqueConstraint("requester_id", "addressee_id", name="uq_friendship_pair"),
    )
    op.create_index("ix_friendships_requester_id", "friendships", ["requester_id"])
    op.create_index("ix_friendships_addressee_id", "friendships", ["addressee_id"])

    op.create_table(
        "vehicles",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("name", sa.String(120), nullable=False),
        sa.Column("make", sa.String(80), nullable=True),
        sa.Column("model", sa.String(80), nullable=True),
        sa.Column("year", sa.Integer(), nullable=True),
        sa.Column("initial_odometer_km", sa.Float(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_vehicles_user_id", "vehicles", ["user_id"])

    op.create_table(
        "rides",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("host_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("title", sa.String(200), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("visibility", sa.String(32), nullable=False),
        sa.Column("status", sa.String(32), nullable=False),
        sa.Column("join_code", sa.String(16), nullable=False),
        sa.Column("invite_token", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("scheduled_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("ended_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("start_point", Geography(geometry_type="POINT", srid=4326, spatial_index=False), nullable=True),
        sa.Column("destination", Geography(geometry_type="POINT", srid=4326, spatial_index=False), nullable=True),
        sa.Column("route", Geography(geometry_type="LINESTRING", srid=4326, spatial_index=False), nullable=True),
        sa.Column("waypoints", postgresql.JSONB(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.UniqueConstraint("join_code"),
        sa.UniqueConstraint("invite_token"),
    )
    op.create_index("ix_rides_host_id", "rides", ["host_id"])
    op.create_index("ix_rides_status", "rides", ["status"])
    op.create_index("ix_rides_join_code", "rides", ["join_code"])
    op.create_index("ix_rides_scheduled_at", "rides", ["scheduled_at"])
    op.execute(
        "CREATE INDEX IF NOT EXISTS idx_rides_start_point ON rides USING GIST (start_point)"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS idx_rides_destination ON rides USING GIST (destination)"
    )
    op.execute("CREATE INDEX IF NOT EXISTS idx_rides_route ON rides USING GIST (route)")

    op.create_table(
        "ride_participants",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("ride_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("rides.id", ondelete="CASCADE"), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("role", sa.String(32), nullable=False),
        sa.Column("status", sa.String(32), nullable=False),
        sa.Column("last_location", Geography(geometry_type="POINT", srid=4326, spatial_index=False), nullable=True),
        sa.Column("last_seen_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("distance_to_host_m", sa.Float(), nullable=True),
        sa.Column("distance_to_destination_m", sa.Float(), nullable=True),
        sa.Column("joined_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.UniqueConstraint("ride_id", "user_id", name="uq_ride_participant"),
    )
    op.create_index("ix_ride_participants_ride_id", "ride_participants", ["ride_id"])
    op.create_index("ix_ride_participants_user_id", "ride_participants", ["user_id"])

    op.create_table(
        "location_shares",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("owner_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("duration", sa.String(32), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("last_location", Geography(geometry_type="POINT", srid=4326, spatial_index=False), nullable=True),
        sa.Column("last_seen_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_location_shares_owner_id", "location_shares", ["owner_id"])

    op.create_table(
        "location_share_grants",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("share_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("location_shares.id", ondelete="CASCADE"), nullable=False),
        sa.Column("friend_user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.UniqueConstraint("share_id", "friend_user_id", name="uq_share_grant"),
    )
    op.create_index("ix_location_share_grants_share_id", "location_share_grants", ["share_id"])
    op.create_index("ix_location_share_grants_friend_user_id", "location_share_grants", ["friend_user_id"])

    op.create_table(
        "location_points",
        sa.Column("id", sa.BigInteger(), primary_key=True, autoincrement=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("ride_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("rides.id", ondelete="SET NULL"), nullable=True),
        sa.Column("location_share_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("location_shares.id", ondelete="SET NULL"), nullable=True),
        sa.Column("geom", Geography(geometry_type="POINT", srid=4326, spatial_index=False), nullable=False),
        sa.Column("speed_mps", sa.Float(), nullable=True),
        sa.Column("heading", sa.Float(), nullable=True),
        sa.Column("accuracy_m", sa.Float(), nullable=True),
        sa.Column("recorded_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("received_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_location_points_user_id", "location_points", ["user_id"])
    op.create_index("ix_location_points_ride_id", "location_points", ["ride_id"])
    op.create_index("ix_location_points_location_share_id", "location_points", ["location_share_id"])
    op.create_index("ix_location_points_user_recorded", "location_points", ["user_id", "recorded_at"])
    op.create_index("ix_location_points_ride_recorded", "location_points", ["ride_id", "recorded_at"])
    op.execute("CREATE INDEX IF NOT EXISTS idx_location_points_geom ON location_points USING GIST (geom)")

    op.create_table(
        "posts",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("author_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("caption", sa.Text(), nullable=True),
        sa.Column("ride_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("rides.id", ondelete="SET NULL"), nullable=True),
        sa.Column("distance_km", sa.Float(), nullable=True),
        sa.Column("duration_s", sa.Integer(), nullable=True),
        sa.Column("route_snapshot", Geography(geometry_type="LINESTRING", srid=4326, spatial_index=False), nullable=True),
        sa.Column("like_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("comment_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_posts_author_id", "posts", ["author_id"])
    op.create_index("ix_posts_created_at", "posts", ["created_at"])

    op.create_table(
        "post_images",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("post_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("posts.id", ondelete="CASCADE"), nullable=False),
        sa.Column("file_path", sa.String(512), nullable=False),
        sa.Column("thumb_path", sa.String(512), nullable=False),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("width", sa.Integer(), nullable=True),
        sa.Column("height", sa.Integer(), nullable=True),
    )
    op.create_index("ix_post_images_post_id", "post_images", ["post_id"])

    op.create_table(
        "comments",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("post_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("posts.id", ondelete="CASCADE"), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("body", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
    )
    op.create_index("ix_comments_post_id", "comments", ["post_id"])

    op.create_table(
        "likes",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("post_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("posts.id", ondelete="CASCADE"), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.UniqueConstraint("post_id", "user_id", name="uq_post_like"),
    )
    op.create_index("ix_likes_post_id", "likes", ["post_id"])


def downgrade() -> None:
    op.drop_table("likes")
    op.drop_table("comments")
    op.drop_table("post_images")
    op.drop_table("posts")
    op.drop_table("location_points")
    op.drop_table("location_share_grants")
    op.drop_table("location_shares")
    op.drop_table("ride_participants")
    op.drop_table("rides")
    op.drop_table("vehicles")
    op.drop_table("friendships")
    op.drop_table("refresh_tokens")
    op.drop_table("users")
