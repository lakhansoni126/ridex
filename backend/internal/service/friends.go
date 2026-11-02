package service

import (
	"context"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/lakhansoni126/ridex/backend/internal/httpx"
)

type Friendship struct {
	ID          uuid.UUID  `json:"id"`
	RequesterID uuid.UUID  `json:"requester_id"`
	AddresseeID uuid.UUID  `json:"addressee_id"`
	Status      string     `json:"status"`
	CreatedAt   time.Time  `json:"created_at"`
	User        UserPublic `json:"user"`
}

func (s *Svc) ListFriends(ctx context.Context, me uuid.UUID) ([]UserPublic, error) {
	rows, err := s.DB.Query(ctx, `
		SELECT u.id, u.username, u.display_name, u.avatar_path
		FROM friendships f
		JOIN users u ON u.id = CASE WHEN f.requester_id=$1 THEN f.addressee_id ELSE f.requester_id END
		WHERE f.status='accepted' AND (f.requester_id=$1 OR f.addressee_id=$1)`, me)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []UserPublic
	for rows.Next() {
		var u UserPublic
		if err := rows.Scan(&u.ID, &u.Username, &u.DisplayName, &u.AvatarPath); err != nil {
			return nil, err
		}
		out = append(out, u)
	}
	if out == nil {
		out = []UserPublic{}
	}
	return out, nil
}

func (s *Svc) ListFriendRequests(ctx context.Context, me uuid.UUID) (map[string][]Friendship, error) {
	rows, err := s.DB.Query(ctx, `
		SELECT f.id, f.requester_id, f.addressee_id, f.status, f.created_at,
		       u.id, u.username, u.display_name, u.avatar_path
		FROM friendships f
		JOIN users u ON u.id = CASE WHEN f.requester_id=$1 THEN f.addressee_id ELSE f.requester_id END
		WHERE f.status='pending' AND (f.requester_id=$1 OR f.addressee_id=$1)`, me)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	incoming, outgoing := []Friendship{}, []Friendship{}
	for rows.Next() {
		var f Friendship
		if err := rows.Scan(&f.ID, &f.RequesterID, &f.AddresseeID, &f.Status, &f.CreatedAt,
			&f.User.ID, &f.User.Username, &f.User.DisplayName, &f.User.AvatarPath); err != nil {
			return nil, err
		}
		if f.AddresseeID == me {
			incoming = append(incoming, f)
		} else {
			outgoing = append(outgoing, f)
		}
	}
	return map[string][]Friendship{"incoming": incoming, "outgoing": outgoing}, nil
}

func (s *Svc) RequestFriend(ctx context.Context, me uuid.UUID, username string) (Friendship, error) {
	username = strings.ToLower(strings.TrimSpace(username))
	var other uuid.UUID
	if err := s.DB.QueryRow(ctx, `SELECT id FROM users WHERE username=$1 AND deleted_at IS NULL`, username).Scan(&other); err != nil {
		return Friendship{}, httpx.E(http.StatusNotFound, "user not found")
	}
	if other == me {
		return Friendship{}, httpx.E(http.StatusBadRequest, "cannot friend yourself")
	}
	f := Friendship{ID: uuid.New(), RequesterID: me, AddresseeID: other, Status: "pending", CreatedAt: time.Now().UTC()}
	_, err := s.DB.Exec(ctx, `
		INSERT INTO friendships(id, requester_id, addressee_id, status) VALUES ($1,$2,$3,'pending')`,
		f.ID, me, other)
	if err != nil {
		return Friendship{}, httpx.E(http.StatusConflict, "request already exists")
	}
	return f, nil
}

func (s *Svc) AcceptFriend(ctx context.Context, me, reqID uuid.UUID) error {
	tag, err := s.DB.Exec(ctx, `
		UPDATE friendships SET status='accepted', updated_at=now()
		WHERE id=$1 AND addressee_id=$2 AND status='pending'`, reqID, me)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return httpx.E(http.StatusNotFound, "request not found")
	}
	return nil
}

func (s *Svc) DeclineFriend(ctx context.Context, me, reqID uuid.UUID) error {
	tag, err := s.DB.Exec(ctx, `
		UPDATE friendships SET status='declined', updated_at=now()
		WHERE id=$1 AND addressee_id=$2 AND status='pending'`, reqID, me)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return httpx.E(http.StatusNotFound, "request not found")
	}
	return nil
}

func (s *Svc) Unfriend(ctx context.Context, me, other uuid.UUID) error {
	_, err := s.DB.Exec(ctx, `
		DELETE FROM friendships
		WHERE status='accepted' AND (
			(requester_id=$1 AND addressee_id=$2) OR (requester_id=$2 AND addressee_id=$1)
		)`, me, other)
	return err
}
