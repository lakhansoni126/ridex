# RideX Database Schema

PostgreSQL 16 + PostGIS 3.4. Spatial columns use `geography` SRID 4326.

## Enums (stored as strings)

| Domain | Values |
|--------|--------|
| friendship.status | pending, accepted, declined, blocked |
| ride.visibility | public, private |
| ride.status | scheduled, live, ended, cancelled |
| participant.role | host, participant |
| participant.status | joined, on_the_way, riding, paused, stopped, reached, removed, left |
| share.duration | 1h, 8h, indefinite |

## Tables

### users
`id` UUID PK · `email` unique · `username` unique · `password_hash` · `display_name` · `avatar_path` · `bio` · timestamps · `deleted_at`

### refresh_tokens
`id` · `user_id` FK · `token_hash` unique · `expires_at` · `revoked_at` · `created_at`

### friendships
`id` · `requester_id` · `addressee_id` · `status` · timestamps · UNIQUE(requester, addressee)

### vehicles
`id` · `user_id` · `name` · `make` · `model` · `year` · `initial_odometer_km` · `created_at`

### rides
`id` · `host_id` · `title` · `description` · `visibility` · `status` · `join_code` unique · `invite_token` unique · schedule/start/end times · `start_point` geography(Point) · `destination` geography(Point) · `route` geography(LineString) · `waypoints` JSONB · timestamps  

Indexes: GiST on points/route; BTree on status, scheduled_at, join_code.

### ride_participants
`id` · `ride_id` · `user_id` · `role` · `status` · `last_location` Point · `last_seen_at` · distance fields · `joined_at` · UNIQUE(ride_id, user_id)

### location_points
`id` bigserial · `user_id` · `ride_id?` · `location_share_id?` · `geom` Point · speed/heading/accuracy · `recorded_at` · `received_at`  

Retention: delete older than `LOCATION_RETENTION_DAYS`.

### location_shares
`id` · `owner_id` · `duration` · `expires_at` · `is_active` · `last_location` · `last_seen_at` · `created_at`

### location_share_grants
`id` · `share_id` · `friend_user_id` · `revoked_at` · UNIQUE(share_id, friend)

### posts / post_images / comments / likes
Community feed with denormalized `like_count` / `comment_count`, optional `route_snapshot` LineString, local image paths + thumbnails.

## Migrations

Alembic revision `001_initial` enables PostGIS and creates all tables. Applied automatically on API container start.
