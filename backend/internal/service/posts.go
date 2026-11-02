package service

import (
	"context"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/lakhansoni126/ridex/backend/internal/httpx"
)

type PostImage struct {
	ID        uuid.UUID `json:"id"`
	FilePath  string    `json:"file_path"`
	ThumbPath string    `json:"thumb_path"`
	SortOrder int       `json:"sort_order"`
}

type Post struct {
	ID           uuid.UUID   `json:"id"`
	AuthorID     uuid.UUID   `json:"author_id"`
	Caption      *string     `json:"caption"`
	RideID       *uuid.UUID  `json:"ride_id"`
	DistanceKm   *float64    `json:"distance_km"`
	DurationS    *int        `json:"duration_s"`
	LikeCount    int         `json:"like_count"`
	CommentCount int         `json:"comment_count"`
	CreatedAt    time.Time   `json:"created_at"`
	Images       []PostImage `json:"images"`
	Author       *UserPublic `json:"author,omitempty"`
	LikedByMe    bool        `json:"liked_by_me"`
}

type Comment struct {
	ID        uuid.UUID  `json:"id"`
	PostID    uuid.UUID  `json:"post_id"`
	UserID    uuid.UUID  `json:"user_id"`
	Body      string     `json:"body"`
	CreatedAt time.Time  `json:"created_at"`
	User      UserPublic `json:"user"`
}

func (s *Svc) EnsureStorageDirs() error { return s.ensureStorage() }

func (s *Svc) ensureStorage() error {
	for _, sub := range []string{"posts", "avatars", "thumbnails"} {
		if err := os.MkdirAll(filepath.Join(s.Cfg.StorageRoot, sub), 0o755); err != nil {
			return err
		}
	}
	return nil
}

func (s *Svc) saveUpload(file *multipart.FileHeader, kind string) (rel, thumb string, err error) {
	if err = s.ensureStorage(); err != nil {
		return
	}
	if file.Size > s.Cfg.MediaMaxBytes {
		return "", "", httpx.E(http.StatusBadRequest, "file too large")
	}
	ct := file.Header.Get("Content-Type")
	if !strings.HasPrefix(ct, "image/") {
		return "", "", httpx.E(http.StatusBadRequest, "unsupported media type")
	}
	ext := strings.ToLower(filepath.Ext(file.Filename))
	if ext == "" {
		ext = ".jpg"
	}
	name := uuid.NewString() + ext
	rel = filepath.ToSlash(filepath.Join(kind, name))
	thumb = filepath.ToSlash(filepath.Join("thumbnails", uuid.NewString()+"_thumb"+ext))
	src, err := file.Open()
	if err != nil {
		return
	}
	defer src.Close()
	dstPath := filepath.Join(s.Cfg.StorageRoot, filepath.FromSlash(rel))
	dst, err := os.Create(dstPath)
	if err != nil {
		return
	}
	defer dst.Close()
	if _, err = io.Copy(dst, src); err != nil {
		return
	}
	// Minimal thumb: copy original (keeps LOC low; swap for imaging lib later if needed).
	in, _ := os.Open(dstPath)
	defer in.Close()
	out, err := os.Create(filepath.Join(s.Cfg.StorageRoot, filepath.FromSlash(thumb)))
	if err != nil {
		return
	}
	defer out.Close()
	_, err = io.Copy(out, in)
	return
}

func (s *Svc) CreatePost(ctx context.Context, me uuid.UUID, caption *string, rideID *uuid.UUID, distanceKm *float64, durationS *int, files []*multipart.FileHeader) (Post, error) {
	if len(files) == 0 {
		return Post{}, httpx.E(http.StatusBadRequest, "at least one image required")
	}
	id := uuid.New()
	_, err := s.DB.Exec(ctx, `
		INSERT INTO posts(id, author_id, caption, ride_id, distance_km, duration_s)
		VALUES ($1,$2,$3,$4,$5,$6)`, id, me, caption, rideID, distanceKm, durationS)
	if err != nil {
		return Post{}, err
	}
	for i, f := range files {
		rel, thumb, err := s.saveUpload(f, "posts")
		if err != nil {
			return Post{}, err
		}
		_, err = s.DB.Exec(ctx, `
			INSERT INTO post_images(id, post_id, file_path, thumb_path, sort_order)
			VALUES ($1,$2,$3,$4,$5)`, uuid.New(), id, rel, thumb, i)
		if err != nil {
			return Post{}, err
		}
	}
	return s.GetPost(ctx, me, id)
}

func (s *Svc) GetPost(ctx context.Context, me, id uuid.UUID) (Post, error) {
	var p Post
	var uname, dname string
	var avatar *string
	err := s.DB.QueryRow(ctx, `
		SELECT p.id, p.author_id, p.caption, p.ride_id, p.distance_km, p.duration_s,
		       p.like_count, p.comment_count, p.created_at,
		       u.username, u.display_name, u.avatar_path,
		       EXISTS(SELECT 1 FROM likes l WHERE l.post_id=p.id AND l.user_id=$2)
		FROM posts p JOIN users u ON u.id=p.author_id WHERE p.id=$1`, id, me,
	).Scan(&p.ID, &p.AuthorID, &p.Caption, &p.RideID, &p.DistanceKm, &p.DurationS,
		&p.LikeCount, &p.CommentCount, &p.CreatedAt, &uname, &dname, &avatar, &p.LikedByMe)
	if err != nil {
		return p, httpx.E(http.StatusNotFound, "post not found")
	}
	p.Author = &UserPublic{ID: p.AuthorID, Username: uname, DisplayName: dname, AvatarPath: avatar}
	p.Images, _ = s.postImages(ctx, id)
	return p, nil
}

func (s *Svc) postImages(ctx context.Context, postID uuid.UUID) ([]PostImage, error) {
	rows, err := s.DB.Query(ctx, `
		SELECT id, file_path, thumb_path, sort_order FROM post_images WHERE post_id=$1 ORDER BY sort_order`, postID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []PostImage
	for rows.Next() {
		var im PostImage
		if err := rows.Scan(&im.ID, &im.FilePath, &im.ThumbPath, &im.SortOrder); err != nil {
			return nil, err
		}
		out = append(out, im)
	}
	if out == nil {
		out = []PostImage{}
	}
	return out, nil
}

func (s *Svc) ListPosts(ctx context.Context, me uuid.UUID, cursor *time.Time, limit int) ([]Post, error) {
	if limit <= 0 || limit > 50 {
		limit = 20
	}
	q := `
		SELECT p.id, p.author_id, p.caption, p.ride_id, p.distance_km, p.duration_s,
		       p.like_count, p.comment_count, p.created_at,
		       u.username, u.display_name, u.avatar_path,
		       EXISTS(SELECT 1 FROM likes l WHERE l.post_id=p.id AND l.user_id=$1)
		FROM posts p JOIN users u ON u.id=p.author_id`
	args := []any{me}
	if cursor != nil {
		args = append(args, *cursor)
		q += ` WHERE p.created_at < $2`
	}
	q += fmt.Sprintf(` ORDER BY p.created_at DESC LIMIT $%d`, len(args)+1)
	args = append(args, limit)
	rows, err := s.DB.Query(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Post
	for rows.Next() {
		var p Post
		var uname, dname string
		var avatar *string
		if err := rows.Scan(&p.ID, &p.AuthorID, &p.Caption, &p.RideID, &p.DistanceKm, &p.DurationS,
			&p.LikeCount, &p.CommentCount, &p.CreatedAt, &uname, &dname, &avatar, &p.LikedByMe); err != nil {
			return nil, err
		}
		p.Author = &UserPublic{ID: p.AuthorID, Username: uname, DisplayName: dname, AvatarPath: avatar}
		p.Images, _ = s.postImages(ctx, p.ID)
		out = append(out, p)
	}
	if out == nil {
		out = []Post{}
	}
	return out, nil
}

func (s *Svc) ToggleLike(ctx context.Context, me, postID uuid.UUID) (Post, error) {
	tag, err := s.DB.Exec(ctx, `DELETE FROM likes WHERE post_id=$1 AND user_id=$2`, postID, me)
	if err != nil {
		return Post{}, err
	}
	if tag.RowsAffected() == 0 {
		_, err = s.DB.Exec(ctx, `INSERT INTO likes(id, post_id, user_id) VALUES ($1,$2,$3)`, uuid.New(), postID, me)
		if err != nil {
			return Post{}, err
		}
		_, _ = s.DB.Exec(ctx, `UPDATE posts SET like_count = like_count + 1 WHERE id=$1`, postID)
	} else {
		_, _ = s.DB.Exec(ctx, `UPDATE posts SET like_count = GREATEST(like_count - 1, 0) WHERE id=$1`, postID)
	}
	return s.GetPost(ctx, me, postID)
}

func (s *Svc) AddComment(ctx context.Context, me, postID uuid.UUID, body string) (Comment, error) {
	c := Comment{ID: uuid.New(), PostID: postID, UserID: me, Body: body, CreatedAt: time.Now().UTC()}
	_, err := s.DB.Exec(ctx, `INSERT INTO comments(id, post_id, user_id, body) VALUES ($1,$2,$3,$4)`, c.ID, postID, me, body)
	if err != nil {
		return c, err
	}
	_, _ = s.DB.Exec(ctx, `UPDATE posts SET comment_count = comment_count + 1 WHERE id=$1`, postID)
	u, _ := s.getUser(ctx, me)
	c.User = UserPublic{ID: u.ID, Username: u.Username, DisplayName: u.DisplayName, AvatarPath: u.AvatarPath}
	return c, nil
}

func (s *Svc) ListComments(ctx context.Context, postID uuid.UUID) ([]Comment, error) {
	rows, err := s.DB.Query(ctx, `
		SELECT c.id, c.post_id, c.user_id, c.body, c.created_at, u.username, u.display_name, u.avatar_path
		FROM comments c JOIN users u ON u.id=c.user_id
		WHERE c.post_id=$1 ORDER BY c.created_at ASC`, postID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Comment
	for rows.Next() {
		var c Comment
		if err := rows.Scan(&c.ID, &c.PostID, &c.UserID, &c.Body, &c.CreatedAt,
			&c.User.Username, &c.User.DisplayName, &c.User.AvatarPath); err != nil {
			return nil, err
		}
		c.User.ID = c.UserID
		out = append(out, c)
	}
	if out == nil {
		out = []Comment{}
	}
	return out, nil
}
