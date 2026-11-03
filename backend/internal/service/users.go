package service

import (
	"context"
	"mime/multipart"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/lakhansoni126/ridex/backend/internal/httpx"
)

func (s *Svc) Me(ctx context.Context, id uuid.UUID) (User, error) { return s.getUser(ctx, id) }

func (s *Svc) UpdateMe(ctx context.Context, id uuid.UUID, displayName, bio *string) (User, error) {
	if displayName != nil {
		v, err := TrimmedText("display name", *displayName, 1, 60)
		if err != nil {
			return User{}, err
		}
		displayName = &v
	}
	var bioArg any
	setBio := bio != nil
	if bio != nil {
		v, err := TrimmedText("bio", *bio, 0, 280)
		if err != nil {
			return User{}, err
		}
		if v != "" {
			bioArg = v
		}
	}
	_, err := s.DB.Exec(ctx, `
		UPDATE users SET
			display_name = COALESCE($2, display_name),
			bio = CASE WHEN $3 THEN $4::text ELSE bio END,
			updated_at = now()
		WHERE id=$1 AND deleted_at IS NULL`, id, displayName, setBio, bioArg)
	if err != nil {
		return User{}, err
	}
	return s.getUser(ctx, id)
}

// SetAvatar stores a new avatar image and returns the updated user.
func (s *Svc) SetAvatar(ctx context.Context, id uuid.UUID, fh *multipart.FileHeader) (User, error) {
	if fh == nil {
		return User{}, httpx.BadRequest("avatar file is required")
	}
	img, err := s.saveImage(fh, "avatars")
	if err != nil {
		return User{}, err
	}
	// The avatar is the (small) thumbnail; the original is not needed.
	s.removeFiles(img.Rel)
	var old *string
	err = s.DB.QueryRow(ctx, `
		UPDATE users u SET avatar_path=$2, updated_at=now()
		FROM (SELECT avatar_path FROM users WHERE id=$1) prev
		WHERE u.id=$1 AND u.deleted_at IS NULL
		RETURNING prev.avatar_path`, id, img.Thumb).Scan(&old)
	if err != nil {
		s.removeFiles(img.Thumb)
		if isNoRows(err) {
			return User{}, httpx.NotFound("user not found")
		}
		return User{}, err
	}
	if old != nil && *old != img.Thumb {
		s.removeFiles(*old)
	}
	return s.getUser(ctx, id)
}

// DeleteMe anonymises the account, revokes sessions, stops shares and removes posts.
func (s *Svc) DeleteMe(ctx context.Context, id uuid.UUID) error {
	var files []string
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		short := strings.ReplaceAll(id.String(), "-", "")[:8]
		var avatar *string
		if err := tx.QueryRow(ctx, `SELECT avatar_path FROM users WHERE id=$1 AND deleted_at IS NULL FOR UPDATE`, id).Scan(&avatar); err != nil {
			if isNoRows(err) {
				return httpx.NotFound("user not found")
			}
			return err
		}
		if avatar != nil {
			files = append(files, *avatar)
		}
		rows, err := tx.Query(ctx, `
			SELECT i.file_path, i.thumb_path FROM post_images i JOIN posts p ON p.id=i.post_id WHERE p.author_id=$1`, id)
		if err != nil {
			return err
		}
		for rows.Next() {
			var a, b string
			if err := rows.Scan(&a, &b); err != nil {
				rows.Close()
				return err
			}
			files = append(files, a, b)
		}
		rows.Close()
		if err := rows.Err(); err != nil {
			return err
		}
		stmts := []struct {
			q    string
			args []any
		}{
			{`UPDATE users SET deleted_at=now(), updated_at=now(),
				email=$2, username=$3, display_name='Deleted user', bio=NULL, avatar_path=NULL,
				password_hash='!' WHERE id=$1`,
				[]any{id, "deleted+" + id.String() + "@ridex.invalid", "deleted_" + short}},
			{`UPDATE refresh_tokens SET revoked_at=now() WHERE user_id=$1 AND revoked_at IS NULL`, []any{id}},
			{`UPDATE location_shares SET is_active=false WHERE owner_id=$1 AND is_active`, []any{id}},
			{`UPDATE posts SET like_count = GREATEST(like_count-1,0)
				WHERE id IN (SELECT post_id FROM likes WHERE user_id=$1)`, []any{id}},
			{`DELETE FROM likes WHERE user_id=$1`, []any{id}},
			{`UPDATE posts SET comment_count = GREATEST(comment_count - c.n, 0)
				FROM (SELECT post_id, count(*) n FROM comments WHERE user_id=$1 GROUP BY post_id) c
				WHERE posts.id=c.post_id`, []any{id}},
			{`DELETE FROM comments WHERE user_id=$1`, []any{id}},
			{`DELETE FROM posts WHERE author_id=$1`, []any{id}},
			{`DELETE FROM friendships WHERE requester_id=$1 OR addressee_id=$1`, []any{id}},
			{`UPDATE ride_participants SET status='left' WHERE user_id=$1 AND status NOT IN ('removed','left')`, []any{id}},
			{`UPDATE rides SET status='cancelled', updated_at=now() WHERE host_id=$1 AND status IN ('scheduled','live')`, []any{id}},
		}
		for _, st := range stmts {
			if _, err := tx.Exec(ctx, st.q, st.args...); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		return err
	}
	s.removeFiles(files...)
	return nil
}

// SearchUsers finds users by username/display-name prefix.
func (s *Svc) SearchUsers(ctx context.Context, me uuid.UUID, q string) ([]UserSearchResult, error) {
	q = strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(q), "@"))
	if len([]rune(q)) < 2 {
		return nil, httpx.BadRequest("search needs at least 2 characters")
	}
	if len(q) > 64 {
		q = q[:64]
	}
	pattern := escapeLike(q) + "%"
	rows, err := s.DB.Query(ctx, `
		SELECT u.id, u.username, u.display_name, u.avatar_path,
		       COALESCE((
		         SELECT CASE
		           WHEN f.status='accepted' THEN 'friends'
		           WHEN f.status='pending' AND f.requester_id=$1 THEN 'outgoing'
		           WHEN f.status='pending' THEN 'incoming'
		           ELSE 'none' END
		         FROM friendships f
		         WHERE (f.requester_id=$1 AND f.addressee_id=u.id) OR (f.requester_id=u.id AND f.addressee_id=$1)
		         ORDER BY (f.status='accepted') DESC, (f.status='pending') DESC
		         LIMIT 1), 'none')
		FROM users u
		WHERE u.deleted_at IS NULL AND u.id <> $1
		  AND (u.username ILIKE $2 ESCAPE '\' OR u.display_name ILIKE $2 ESCAPE '\')
		ORDER BY (lower(u.username) = lower($3)) DESC, u.username
		LIMIT 20`, me, pattern, q)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []UserSearchResult{}
	for rows.Next() {
		var r UserSearchResult
		if err := rows.Scan(&r.ID, &r.Username, &r.DisplayName, &r.AvatarPath, &r.Friendship); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

func escapeLike(s string) string {
	r := strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`)
	return r.Replace(s)
}

func (s *Svc) Stats(ctx context.Context, me uuid.UUID) (UserStats, error) {
	var st UserStats
	err := s.DB.QueryRow(ctx, `
		SELECT
		  (SELECT count(*) FROM friendships WHERE status='accepted' AND (requester_id=$1 OR addressee_id=$1)),
		  (SELECT count(*) FROM rides WHERE host_id=$1),
		  (SELECT count(*) FROM ride_participants WHERE user_id=$1 AND role<>'host' AND status NOT IN ('removed','left')),
		  (SELECT count(*) FROM posts WHERE author_id=$1)`, me,
	).Scan(&st.Friends, &st.RidesHosted, &st.RidesJoined, &st.Posts)
	return st, err
}
