package service

import (
	"context"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/lakhansoni126/ridex/backend/internal/httpx"
)

type Friendship struct {
	ID          uuid.UUID  `json:"id"`
	RequesterID uuid.UUID  `json:"requester_id"`
	AddresseeID uuid.UUID  `json:"addressee_id"`
	Status      string     `json:"status"`
	CreatedAt   time.Time  `json:"created_at"`
	User        UserPublic `json:"user"`
	Requester   UserPublic `json:"requester"`
	Addressee   UserPublic `json:"addressee"`
}

const friendshipSelect = `
	SELECT f.id, f.requester_id, f.addressee_id, f.status, f.created_at,
	       r.id, r.username, r.display_name, r.avatar_path,
	       a.id, a.username, a.display_name, a.avatar_path
	FROM friendships f
	JOIN users r ON r.id=f.requester_id
	JOIN users a ON a.id=f.addressee_id`

func scanFriendship(row pgx.Row, me uuid.UUID) (Friendship, error) {
	var f Friendship
	err := row.Scan(&f.ID, &f.RequesterID, &f.AddresseeID, &f.Status, &f.CreatedAt,
		&f.Requester.ID, &f.Requester.Username, &f.Requester.DisplayName, &f.Requester.AvatarPath,
		&f.Addressee.ID, &f.Addressee.Username, &f.Addressee.DisplayName, &f.Addressee.AvatarPath)
	if f.RequesterID == me {
		f.User = f.Addressee
	} else {
		f.User = f.Requester
	}
	return f, err
}

func (s *Svc) getFriendship(ctx context.Context, me, id uuid.UUID) (Friendship, error) {
	f, err := scanFriendship(s.DB.QueryRow(ctx, friendshipSelect+` WHERE f.id=$1`, id), me)
	if isNoRows(err) {
		return f, httpx.NotFound("request not found")
	}
	return f, err
}

func (s *Svc) ListFriends(ctx context.Context, me uuid.UUID) ([]UserPublic, error) {
	rows, err := s.DB.Query(ctx, `
		SELECT u.id, u.username, u.display_name, u.avatar_path
		FROM friendships f
		JOIN users u ON u.id = CASE WHEN f.requester_id=$1 THEN f.addressee_id ELSE f.requester_id END
		WHERE f.status='accepted' AND (f.requester_id=$1 OR f.addressee_id=$1) AND u.deleted_at IS NULL
		ORDER BY lower(u.display_name)`, me)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []UserPublic{}
	for rows.Next() {
		var u UserPublic
		if err := rows.Scan(&u.ID, &u.Username, &u.DisplayName, &u.AvatarPath); err != nil {
			return nil, err
		}
		out = append(out, u)
	}
	return out, rows.Err()
}

func (s *Svc) ListFriendRequests(ctx context.Context, me uuid.UUID) (map[string][]Friendship, error) {
	rows, err := s.DB.Query(ctx, friendshipSelect+`
		WHERE f.status='pending' AND (f.requester_id=$1 OR f.addressee_id=$1)
		  AND r.deleted_at IS NULL AND a.deleted_at IS NULL
		ORDER BY f.created_at DESC`, me)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	incoming, outgoing := []Friendship{}, []Friendship{}
	for rows.Next() {
		f, err := scanFriendship(rows, me)
		if err != nil {
			return nil, err
		}
		if f.AddresseeID == me {
			incoming = append(incoming, f)
		} else {
			outgoing = append(outgoing, f)
		}
	}
	return map[string][]Friendship{"incoming": incoming, "outgoing": outgoing}, rows.Err()
}

// RequestFriend sends a request, auto-accepting a reverse pending request and
// re-opening a previously declined one.
func (s *Svc) RequestFriend(ctx context.Context, me uuid.UUID, username string) (Friendship, error) {
	username = strings.ToLower(strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(username), "@")))
	var other uuid.UUID
	if err := s.DB.QueryRow(ctx, `SELECT id FROM users WHERE username=$1 AND deleted_at IS NULL`, username).Scan(&other); err != nil {
		if isNoRows(err) {
			return Friendship{}, httpx.NotFound("user not found")
		}
		return Friendship{}, err
	}
	if other == me {
		return Friendship{}, httpx.BadRequest("you can't add yourself")
	}
	var resultID uuid.UUID
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT id, requester_id, status FROM friendships
			WHERE (requester_id=$1 AND addressee_id=$2) OR (requester_id=$2 AND addressee_id=$1)
			FOR UPDATE`, me, other)
		if err != nil {
			return err
		}
		type row struct {
			id, requester uuid.UUID
			status        string
		}
		var existing []row
		for rows.Next() {
			var r row
			if err := rows.Scan(&r.id, &r.requester, &r.status); err != nil {
				rows.Close()
				return err
			}
			existing = append(existing, r)
		}
		rows.Close()
		if err := rows.Err(); err != nil {
			return err
		}
		for _, r := range existing {
			if r.status == "accepted" {
				return httpx.Conflict("already friends")
			}
		}
		for _, r := range existing {
			if r.status == "pending" && r.requester == other {
				resultID = r.id
				_, err := tx.Exec(ctx, `UPDATE friendships SET status='accepted', updated_at=now() WHERE id=$1`, r.id)
				return err
			}
		}
		for _, r := range existing {
			if r.status == "pending" && r.requester == me {
				return httpx.Conflict("request already pending")
			}
		}
		// Declined (or other) rows: clear them and open a fresh request from me.
		if len(existing) > 0 {
			if _, err := tx.Exec(ctx, `
				DELETE FROM friendships
				WHERE (requester_id=$1 AND addressee_id=$2) OR (requester_id=$2 AND addressee_id=$1)`, me, other); err != nil {
				return err
			}
		}
		resultID = uuid.New()
		_, err = tx.Exec(ctx, `
			INSERT INTO friendships(id, requester_id, addressee_id, status) VALUES ($1,$2,$3,'pending')`,
			resultID, me, other)
		if isUniqueViolation(err) {
			return httpx.Conflict("request already pending")
		}
		return err
	})
	if err != nil {
		return Friendship{}, err
	}
	return s.getFriendship(ctx, me, resultID)
}

func (s *Svc) AcceptFriend(ctx context.Context, me, reqID uuid.UUID) (Friendship, error) {
	tag, err := s.DB.Exec(ctx, `
		UPDATE friendships SET status='accepted', updated_at=now()
		WHERE id=$1 AND addressee_id=$2 AND status='pending'`, reqID, me)
	if err != nil {
		return Friendship{}, err
	}
	if tag.RowsAffected() == 0 {
		return Friendship{}, httpx.NotFound("request not found")
	}
	return s.getFriendship(ctx, me, reqID)
}

func (s *Svc) DeclineFriend(ctx context.Context, me, reqID uuid.UUID) error {
	tag, err := s.DB.Exec(ctx, `
		UPDATE friendships SET status='declined', updated_at=now()
		WHERE id=$1 AND addressee_id=$2 AND status='pending'`, reqID, me)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return httpx.NotFound("request not found")
	}
	return nil
}

// CancelFriendRequest lets the requester withdraw a pending request.
func (s *Svc) CancelFriendRequest(ctx context.Context, me, reqID uuid.UUID) error {
	tag, err := s.DB.Exec(ctx, `
		DELETE FROM friendships WHERE id=$1 AND requester_id=$2 AND status='pending'`, reqID, me)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return httpx.NotFound("request not found")
	}
	return nil
}

func (s *Svc) Unfriend(ctx context.Context, me, other uuid.UUID) error {
	return s.inTx(ctx, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `
			DELETE FROM friendships
			WHERE status='accepted' AND (
				(requester_id=$1 AND addressee_id=$2) OR (requester_id=$2 AND addressee_id=$1)
			)`, me, other); err != nil {
			return err
		}
		// Unfriending also revokes any live location grants between the two.
		_, err := tx.Exec(ctx, `
			UPDATE location_share_grants g SET revoked_at=now()
			FROM location_shares s
			WHERE g.share_id=s.id AND g.revoked_at IS NULL AND (
				(s.owner_id=$1 AND g.friend_user_id=$2) OR (s.owner_id=$2 AND g.friend_user_id=$1)
			)`, me, other)
		return err
	})
}

// friendIDs returns the subset of candidates that are accepted friends of me.
func (s *Svc) friendIDs(ctx context.Context, me uuid.UUID, candidates []uuid.UUID) ([]uuid.UUID, error) {
	if len(candidates) == 0 {
		return nil, nil
	}
	rows, err := s.DB.Query(ctx, `
		SELECT DISTINCT CASE WHEN f.requester_id=$1 THEN f.addressee_id ELSE f.requester_id END
		FROM friendships f
		WHERE f.status='accepted' AND (
			(f.requester_id=$1 AND f.addressee_id = ANY($2::uuid[])) OR (f.addressee_id=$1 AND f.requester_id = ANY($2::uuid[]))
		)`, me, uuidStrings(candidates))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []uuid.UUID
	for rows.Next() {
		var id uuid.UUID
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		out = append(out, id)
	}
	return out, rows.Err()
}

// uuidStrings converts ids for an explicit ::uuid[] parameter.
func uuidStrings(ids []uuid.UUID) []string {
	out := make([]string, len(ids))
	for i, id := range ids {
		out[i] = id.String()
	}
	return out
}
