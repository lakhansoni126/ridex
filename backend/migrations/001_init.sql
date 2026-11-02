CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE IF NOT EXISTS schema_migrations (
  version TEXT PRIMARY KEY,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY,
  email VARCHAR(320) NOT NULL UNIQUE,
  username VARCHAR(64) NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  display_name VARCHAR(120) NOT NULL,
  avatar_path VARCHAR(512),
  bio TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS refresh_tokens (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_refresh_tokens_user_id ON refresh_tokens(user_id);

CREATE TABLE IF NOT EXISTS friendships (
  id UUID PRIMARY KEY,
  requester_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  addressee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status VARCHAR(32) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (requester_id, addressee_id)
);

CREATE TABLE IF NOT EXISTS rides (
  id UUID PRIMARY KEY,
  host_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title VARCHAR(200) NOT NULL,
  description TEXT,
  visibility VARCHAR(32) NOT NULL,
  status VARCHAR(32) NOT NULL,
  join_code VARCHAR(16) NOT NULL UNIQUE,
  invite_token UUID NOT NULL UNIQUE,
  scheduled_at TIMESTAMPTZ,
  started_at TIMESTAMPTZ,
  ended_at TIMESTAMPTZ,
  start_point GEOGRAPHY(POINT, 4326),
  destination GEOGRAPHY(POINT, 4326),
  route GEOGRAPHY(LINESTRING, 4326),
  waypoints JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_rides_status ON rides(status);
CREATE INDEX IF NOT EXISTS idx_rides_start_point ON rides USING GIST (start_point);
CREATE INDEX IF NOT EXISTS idx_rides_destination ON rides USING GIST (destination);

CREATE TABLE IF NOT EXISTS ride_participants (
  id UUID PRIMARY KEY,
  ride_id UUID NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role VARCHAR(32) NOT NULL,
  status VARCHAR(32) NOT NULL,
  last_location GEOGRAPHY(POINT, 4326),
  last_seen_at TIMESTAMPTZ,
  distance_to_host_m DOUBLE PRECISION,
  distance_to_destination_m DOUBLE PRECISION,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (ride_id, user_id)
);

CREATE TABLE IF NOT EXISTS location_shares (
  id UUID PRIMARY KEY,
  owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  duration VARCHAR(32) NOT NULL,
  expires_at TIMESTAMPTZ,
  is_active BOOLEAN NOT NULL DEFAULT true,
  last_location GEOGRAPHY(POINT, 4326),
  last_seen_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS location_share_grants (
  id UUID PRIMARY KEY,
  share_id UUID NOT NULL REFERENCES location_shares(id) ON DELETE CASCADE,
  friend_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (share_id, friend_user_id)
);

CREATE TABLE IF NOT EXISTS location_points (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  ride_id UUID REFERENCES rides(id) ON DELETE SET NULL,
  location_share_id UUID REFERENCES location_shares(id) ON DELETE SET NULL,
  geom GEOGRAPHY(POINT, 4326) NOT NULL,
  speed_mps DOUBLE PRECISION,
  heading DOUBLE PRECISION,
  accuracy_m DOUBLE PRECISION,
  recorded_at TIMESTAMPTZ NOT NULL,
  received_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_location_points_geom ON location_points USING GIST (geom);
CREATE INDEX IF NOT EXISTS ix_location_points_ride_recorded ON location_points(ride_id, recorded_at);

CREATE TABLE IF NOT EXISTS posts (
  id UUID PRIMARY KEY,
  author_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  caption TEXT,
  ride_id UUID REFERENCES rides(id) ON DELETE SET NULL,
  distance_km DOUBLE PRECISION,
  duration_s INT,
  like_count INT NOT NULL DEFAULT 0,
  comment_count INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_posts_created_at ON posts(created_at DESC);

CREATE TABLE IF NOT EXISTS post_images (
  id UUID PRIMARY KEY,
  post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  file_path VARCHAR(512) NOT NULL,
  thumb_path VARCHAR(512) NOT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  width INT,
  height INT
);

CREATE TABLE IF NOT EXISTS comments (
  id UUID PRIMARY KEY,
  post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  body TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS likes (
  id UUID PRIMARY KEY,
  post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (post_id, user_id)
);
