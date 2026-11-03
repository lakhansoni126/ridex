-- Production hardening: dedupe + query-path indexes. No CHECK constraints so
-- existing rows are never rejected.

-- WS and REST batch sync can both deliver the same GPS sample; dedupe on it.
DELETE FROM location_points a
USING location_points b
WHERE a.id > b.id
  AND a.user_id = b.user_id
  AND COALESCE(a.ride_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE(b.ride_id, '00000000-0000-0000-0000-000000000000'::uuid)
  AND COALESCE(a.location_share_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE(b.location_share_id, '00000000-0000-0000-0000-000000000000'::uuid)
  AND a.recorded_at = b.recorded_at;

CREATE UNIQUE INDEX IF NOT EXISTS ux_location_points_dedupe ON location_points (
  user_id,
  COALESCE(ride_id, '00000000-0000-0000-0000-000000000000'::uuid),
  COALESCE(location_share_id, '00000000-0000-0000-0000-000000000000'::uuid),
  recorded_at
);

CREATE INDEX IF NOT EXISTS ix_location_points_recorded_at ON location_points (recorded_at);
CREATE INDEX IF NOT EXISTS ix_friendships_addressee_status ON friendships (addressee_id, status);
CREATE INDEX IF NOT EXISTS ix_friendships_requester_status ON friendships (requester_id, status);
CREATE INDEX IF NOT EXISTS ix_ride_participants_user_id ON ride_participants (user_id);
CREATE INDEX IF NOT EXISTS ix_location_shares_owner_id ON location_shares (owner_id);
CREATE INDEX IF NOT EXISTS ix_location_share_grants_friend ON location_share_grants (friend_user_id);
CREATE INDEX IF NOT EXISTS ix_post_images_post_id ON post_images (post_id);
CREATE INDEX IF NOT EXISTS ix_comments_post_created ON comments (post_id, created_at);
CREATE INDEX IF NOT EXISTS ix_posts_author_id ON posts (author_id);
CREATE INDEX IF NOT EXISTS ix_refresh_tokens_expires_at ON refresh_tokens (expires_at);
