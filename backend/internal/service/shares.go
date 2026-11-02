package service

import (
	"context"
	"net/http"
	"time"

	"github.com/google/uuid"
	"github.com/lakhansoni126/ridex/backend/internal/httpx"
)

type LocationShare struct {
	ID          uuid.UUID  `json:"id"`
	OwnerID     uuid.UUID  `json:"owner_id"`
	Duration    string     `json:"duration"`
	ExpiresAt   *time.Time `json:"expires_at"`
	IsActive    bool       `json:"is_active"`
	LastSeenAt  *time.Time `json:"last_seen_at"`
	CreatedAt   time.Time  `json:"created_at"`
	Lat         *float64   `json:"lat"`
	Lon         *float64   `json:"lon"`
	FriendIDs   []uuid.UUID `json:"friend_ids,omitempty"`
}

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
		return LocationShare{}, httpx.E(http.StatusBadRequest, "duration must be 1h|8h|indefinite")
	}
	id := uuid.New()
	_, err := s.DB.Exec(ctx, `
		INSERT INTO location_shares(id, owner_id, duration, expires_at, is_active)
		VALUES ($1,$2,$3,$4,true)`, id, me, duration, exp)
	if err != nil {
		return LocationShare{}, err
	}
	for _, f := range friendIDs {
		_, _ = s.DB.Exec(ctx, `
			INSERT INTO location_share_grants(id, share_id, friend_user_id) VALUES ($1,$2,$3)
			ON CONFLICT (share_id, friend_user_id) DO NOTHING`, uuid.New(), id, f)
	}
	return s.getShare(ctx, id)
}

func (s *Svc) getShare(ctx context.Context, id uuid.UUID) (LocationShare, error) {
	var sh LocationShare
	err := s.DB.QueryRow(ctx, `
		SELECT id, owner_id, duration, expires_at, is_active, last_seen_at, created_at,
		       ST_Y(last_location::geometry), ST_X(last_location::geometry)
		FROM location_shares WHERE id=$1`, id,
	).Scan(&sh.ID, &sh.OwnerID, &sh.Duration, &sh.ExpiresAt, &sh.IsActive, &sh.LastSeenAt, &sh.CreatedAt, &sh.Lat, &sh.Lon)
	return sh, err
}

func (s *Svc) ListShares(ctx context.Context, me uuid.UUID) (map[string][]LocationShare, error) {
	mine, err := s.queryShares(ctx, `
		SELECT id, owner_id, duration, expires_at, is_active, last_seen_at, created_at,
		       ST_Y(last_location::geometry), ST_X(last_location::geometry)
		FROM location_shares WHERE owner_id=$1 ORDER BY created_at DESC`, me)
	if err != nil {
		return nil, err
	}
	shared, err := s.queryShares(ctx, `
		SELECT s.id, s.owner_id, s.duration, s.expires_at, s.is_active, s.last_seen_at, s.created_at,
		       ST_Y(s.last_location::geometry), ST_X(s.last_location::geometry)
		FROM location_shares s
		JOIN location_share_grants g ON g.share_id=s.id
		WHERE g.friend_user_id=$1 AND g.revoked_at IS NULL AND s.is_active=true
		  AND (s.expires_at IS NULL OR s.expires_at > now())
		ORDER BY s.created_at DESC`, me)
	if err != nil {
		return nil, err
	}
	return map[string][]LocationShare{"mine": mine, "shared_with_me": shared}, nil
}

func (s *Svc) queryShares(ctx context.Context, q string, arg any) ([]LocationShare, error) {
	rows, err := s.DB.Query(ctx, q, arg)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []LocationShare
	for rows.Next() {
		var sh LocationShare
		if err := rows.Scan(&sh.ID, &sh.OwnerID, &sh.Duration, &sh.ExpiresAt, &sh.IsActive, &sh.LastSeenAt, &sh.CreatedAt, &sh.Lat, &sh.Lon); err != nil {
			return nil, err
		}
		out = append(out, sh)
	}
	if out == nil {
		out = []LocationShare{}
	}
	return out, nil
}

func (s *Svc) StopShare(ctx context.Context, me, id uuid.UUID) error {
	tag, err := s.DB.Exec(ctx, `UPDATE location_shares SET is_active=false WHERE id=$1 AND owner_id=$2`, id, me)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return httpx.E(http.StatusNotFound, "share not found")
	}
	s.Hub.Broadcast("shares:"+me.String(), map[string]any{"type": "share_ended", "share_id": id.String()})
	return nil
}

func (s *Svc) RevokeShareGrant(ctx context.Context, me, shareID, friendID uuid.UUID) error {
	tag, err := s.DB.Exec(ctx, `
		UPDATE location_share_grants g SET revoked_at=now()
		FROM location_shares s
		WHERE g.share_id=s.id AND s.id=$1 AND s.owner_id=$2 AND g.friend_user_id=$3`,
		shareID, me, friendID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return httpx.E(http.StatusNotFound, "grant not found")
	}
	return nil
}
