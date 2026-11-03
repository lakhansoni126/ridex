package service

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/lakhansoni126/ridex/backend/internal/httpx"
)

type ShareGrant struct {
	FriendUserID uuid.UUID  `json:"friend_user_id"`
	Friend       UserPublic `json:"friend"`
	RevokedAt    *time.Time `json:"revoked_at"`
}

type LocationShare struct {
	ID         uuid.UUID    `json:"id"`
	OwnerID    uuid.UUID    `json:"owner_id"`
	Owner      UserPublic   `json:"owner"`
	Duration   string       `json:"duration"`
	ExpiresAt  *time.Time   `json:"expires_at"`
	IsActive   bool         `json:"is_active"`
	LastSeenAt *time.Time   `json:"last_seen_at"`
	CreatedAt  time.Time    `json:"created_at"`
	Lat        *float64     `json:"lat"`
	Lon        *float64     `json:"lon"`
	Grants     []ShareGrant `json:"grants"`
}

const shareSelect = `
	SELECT s.id, s.owner_id, o.username, o.display_name, o.avatar_path,
	       s.duration, s.expires_at, (s.is_active AND (s.expires_at IS NULL OR s.expires_at > now())),
	       s.last_seen_at, s.created_at,
	       ST_Y(s.last_location::geometry), ST_X(s.last_location::geometry)
	FROM location_shares s JOIN users o ON o.id=s.owner_id`

func (s *Svc) CreateShare(ctx context.Context, me uuid.UUID, duration string, friendIDs []uuid.UUID) (LocationShare, error) {
	var exp *time.Time
	now := time.Now().UTC()
	switch duration {
	case "1h":
		t := now.Add(time.Hour)
		exp = &t
	case "8h":
		t := now.Add(8 * time.Hour)
		exp = &t
	case "indefinite":
	default:
		return LocationShare{}, httpx.BadRequest("duration must be 1h, 8h or indefinite")
	}
	friends, err := s.friendIDs(ctx, me, friendIDs)
	if err != nil {
		return LocationShare{}, err
	}
	if len(friends) == 0 {
		return LocationShare{}, httpx.BadRequest("select at least one friend")
	}
	id := uuid.New()
	var previous []uuid.UUID
	err = s.inTx(ctx, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			UPDATE location_shares SET is_active=false WHERE owner_id=$1 AND is_active RETURNING id`, me)
		if err != nil {
			return err
		}
		for rows.Next() {
			var pid uuid.UUID
			if err := rows.Scan(&pid); err != nil {
				rows.Close()
				return err
			}
			previous = append(previous, pid)
		}
		rows.Close()
		if err := rows.Err(); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO location_shares(id, owner_id, duration, expires_at, is_active)
			VALUES ($1,$2,$3,$4,true)`, id, me, duration, exp); err != nil {
			return err
		}
		for _, f := range friends {
			if _, err := tx.Exec(ctx, `
				INSERT INTO location_share_grants(id, share_id, friend_user_id) VALUES ($1,$2,$3)
				ON CONFLICT (share_id, friend_user_id) DO NOTHING`, uuid.New(), id, f); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		return LocationShare{}, err
	}
	for _, pid := range previous {
		s.notifyShareEnded(ctx, me, pid, nil)
	}
	return s.getShare(ctx, id)
}

func (s *Svc) getShare(ctx context.Context, id uuid.UUID) (LocationShare, error) {
	list, err := s.queryShares(ctx, shareSelect+` WHERE s.id=$1`, id)
	if err != nil {
		return LocationShare{}, err
	}
	if len(list) == 0 {
		return LocationShare{}, httpx.NotFound("share not found")
	}
	return list[0], nil
}

func (s *Svc) ListShares(ctx context.Context, me uuid.UUID) (map[string][]LocationShare, error) {
	mine, err := s.queryShares(ctx, shareSelect+` WHERE s.owner_id=$1 ORDER BY s.created_at DESC LIMIT 20`, me)
	if err != nil {
		return nil, err
	}
	shared, err := s.queryShares(ctx, shareSelect+`
		JOIN location_share_grants g ON g.share_id=s.id
		WHERE g.friend_user_id=$1 AND g.revoked_at IS NULL AND s.is_active
		  AND (s.expires_at IS NULL OR s.expires_at > now()) AND o.deleted_at IS NULL
		ORDER BY s.last_seen_at DESC NULLS LAST, s.created_at DESC`, me)
	if err != nil {
		return nil, err
	}
	// Viewers only need to know about their own grant, not the owner's whole list.
	for i := range shared {
		var own []ShareGrant
		for _, g := range shared[i].Grants {
			if g.FriendUserID == me {
				own = append(own, g)
			}
		}
		if own == nil {
			own = []ShareGrant{}
		}
		shared[i].Grants = own
	}
	return map[string][]LocationShare{"mine": mine, "shared_with_me": shared}, nil
}

func (s *Svc) queryShares(ctx context.Context, q string, args ...any) ([]LocationShare, error) {
	rows, err := s.DB.Query(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	out := []LocationShare{}
	for rows.Next() {
		var sh LocationShare
		if err := rows.Scan(&sh.ID, &sh.OwnerID, &sh.Owner.Username, &sh.Owner.DisplayName, &sh.Owner.AvatarPath,
			&sh.Duration, &sh.ExpiresAt, &sh.IsActive, &sh.LastSeenAt, &sh.CreatedAt, &sh.Lat, &sh.Lon); err != nil {
			rows.Close()
			return nil, err
		}
		sh.Owner.ID = sh.OwnerID
		sh.Grants = []ShareGrant{}
		out = append(out, sh)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if len(out) == 0 {
		return out, nil
	}
	ids := make([]uuid.UUID, len(out))
	idx := map[uuid.UUID]int{}
	for i, sh := range out {
		ids[i] = sh.ID
		idx[sh.ID] = i
	}
	grows, err := s.DB.Query(ctx, `
		SELECT g.share_id, g.friend_user_id, g.revoked_at, u.username, u.display_name, u.avatar_path
		FROM location_share_grants g JOIN users u ON u.id=g.friend_user_id
		WHERE g.share_id = ANY($1::uuid[])
		ORDER BY lower(u.display_name)`, uuidStrings(ids))
	if err != nil {
		return nil, err
	}
	defer grows.Close()
	for grows.Next() {
		var sid uuid.UUID
		var g ShareGrant
		if err := grows.Scan(&sid, &g.FriendUserID, &g.RevokedAt, &g.Friend.Username, &g.Friend.DisplayName, &g.Friend.AvatarPath); err != nil {
			return nil, err
		}
		g.Friend.ID = g.FriendUserID
		out[idx[sid]].Grants = append(out[idx[sid]].Grants, g)
	}
	return out, grows.Err()
}

// notifyShareEnded tells the owner and grantees (or only `only`) that a share ended.
func (s *Svc) notifyShareEnded(ctx context.Context, owner, shareID uuid.UUID, only *uuid.UUID) {
	msg := map[string]any{"type": "share_ended", "share_id": shareID.String()}
	if only != nil {
		s.Hub.Broadcast("shares:"+only.String(), msg)
		return
	}
	s.Hub.Broadcast("shares:"+owner.String(), msg)
	rows, err := s.DB.Query(ctx, `SELECT friend_user_id FROM location_share_grants WHERE share_id=$1`, shareID)
	if err != nil {
		return
	}
	defer rows.Close()
	for rows.Next() {
		var fid uuid.UUID
		if rows.Scan(&fid) == nil {
			s.Hub.Broadcast("shares:"+fid.String(), msg)
		}
	}
}

func (s *Svc) StopShare(ctx context.Context, me, id uuid.UUID) error {
	tag, err := s.DB.Exec(ctx, `UPDATE location_shares SET is_active=false WHERE id=$1 AND owner_id=$2`, id, me)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return httpx.NotFound("share not found")
	}
	s.notifyShareEnded(ctx, me, id, nil)
	return nil
}

func (s *Svc) RevokeShareGrant(ctx context.Context, me, shareID, friendID uuid.UUID) error {
	tag, err := s.DB.Exec(ctx, `
		UPDATE location_share_grants g SET revoked_at=now()
		FROM location_shares s
		WHERE g.share_id=s.id AND s.id=$1 AND s.owner_id=$2 AND g.friend_user_id=$3 AND g.revoked_at IS NULL`,
		shareID, me, friendID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return httpx.NotFound("grant not found")
	}
	s.notifyShareEnded(ctx, me, shareID, &friendID)
	return nil
}
