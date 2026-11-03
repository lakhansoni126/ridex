package service

import (
	"context"
	"fmt"
	"mime/multipart"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/lakhansoni126/ridex/backend/internal/httpx"
)

const maxPostImages = 4

type PostImage struct {
	ID        uuid.UUID `json:"id"`
	FilePath  string    `json:"file_path"`
	ThumbPath string    `json:"thumb_path"`
	SortOrder int       `json:"sort_order"`
}

type Post struct {
	ID           uuid.UUID   `json:"id"`
	AuthorID     uuid.UUID   `json:"author_id"`
	Author       UserPublic  `json:"author"`
	Caption      *string     `json:"caption"`
	RideID       *uuid.UUID  `json:"ride_id"`
	DistanceKm   *float64    `json:"distance_km"`
	DurationS    *int        `json:"duration_s"`
	LikeCount    int         `json:"like_count"`
	CommentCount int         `json:"comment_count"`
	CreatedAt    time.Time   `json:"created_at"`
	Images       []PostImage `json:"images"`
	LikedByMe    bool        `json:"liked_by_me"`
}

type PostFeed struct {
	Posts      []Post  `json:"posts"`
	NextCursor *string `json:"next_cursor"`
}

type LikeResult struct {
	Liked     bool `json:"liked"`
	LikeCount int  `json:"like_count"`
}

type Comment struct {
	ID        uuid.UUID  `json:"id"`
	PostID    uuid.UUID  `json:"post_id"`
	UserID    uuid.UUID  `json:"user_id"`
	Body      string     `json:"body"`
	CreatedAt time.Time  `json:"created_at"`
	User      UserPublic `json:"user"`
}

type CreatePostInput struct {
	Caption    *string
	RideID     *uuid.UUID
	DistanceKm *float64
	DurationS  *int
	Files      []*multipart.FileHeader
}

// postSelect needs $1 = viewer id.
const postSelect = `
	SELECT p.id, p.author_id, p.caption, p.ride_id, p.distance_km, p.duration_s,
	       p.like_count, p.comment_count, p.created_at,
	       u.username, u.display_name, u.avatar_path,
	       EXISTS(SELECT 1 FROM likes l WHERE l.post_id=p.id AND l.user_id=$1)
	FROM posts p JOIN users u ON u.id=p.author_id`

func scanPost(row pgx.Row) (Post, error) {
	var p Post
	err := row.Scan(&p.ID, &p.AuthorID, &p.Caption, &p.RideID, &p.DistanceKm, &p.DurationS,
		&p.LikeCount, &p.CommentCount, &p.CreatedAt,
		&p.Author.Username, &p.Author.DisplayName, &p.Author.AvatarPath, &p.LikedByMe)
	p.Author.ID = p.AuthorID
	p.Images = []PostImage{}
	return p, err
}

func (s *Svc) CreatePost(ctx context.Context, me uuid.UUID, in CreatePostInput) (Post, error) {
	if len(in.Files) == 0 {
		return Post{}, httpx.BadRequest("add at least one photo")
	}
	if len(in.Files) > maxPostImages {
		return Post{}, httpx.BadRequest(fmt.Sprintf("at most %d photos per post", maxPostImages))
	}
	if in.Caption != nil {
		v, err := TrimmedText("caption", *in.Caption, 0, 2000)
		if err != nil {
			return Post{}, err
		}
		if v == "" {
			in.Caption = nil
		} else {
			in.Caption = &v
		}
	}
	if in.DistanceKm != nil && (*in.DistanceKm < 0 || *in.DistanceKm > 100000) {
		return Post{}, httpx.BadRequest("invalid distance")
	}
	if in.DurationS != nil && (*in.DurationS < 0 || *in.DurationS > 30*24*3600) {
		return Post{}, httpx.BadRequest("invalid duration")
	}
	if in.RideID != nil {
		if ok, err := s.CanJoinRideSocket(ctx, *in.RideID, me); err != nil {
			return Post{}, err
		} else if !ok {
			return Post{}, httpx.BadRequest("you can only link rides you took part in")
		}
	}

	var stored []storedImage
	cleanup := func() {
		for _, im := range stored {
			s.removeFiles(im.Rel, im.Thumb)
		}
	}
	for _, f := range in.Files {
		im, err := s.saveImage(f, "posts")
		if err != nil {
			cleanup()
			return Post{}, err
		}
		stored = append(stored, im)
	}

	id := uuid.New()
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `
			INSERT INTO posts(id, author_id, caption, ride_id, distance_km, duration_s)
			VALUES ($1,$2,$3,$4,$5,$6)`, id, me, in.Caption, in.RideID, in.DistanceKm, in.DurationS); err != nil {
			return err
		}
		for i, im := range stored {
			if _, err := tx.Exec(ctx, `
				INSERT INTO post_images(id, post_id, file_path, thumb_path, sort_order)
				VALUES ($1,$2,$3,$4,$5)`, uuid.New(), id, im.Rel, im.Thumb, i); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		cleanup()
		return Post{}, err
	}
	return s.GetPost(ctx, me, id)
}

func (s *Svc) GetPost(ctx context.Context, me, id uuid.UUID) (Post, error) {
	p, err := scanPost(s.DB.QueryRow(ctx, postSelect+` WHERE p.id=$2`, me, id))
	if isNoRows(err) {
		return p, httpx.NotFound("post not found")
	}
	if err != nil {
		return p, err
	}
	posts := []Post{p}
	if err := s.attachImages(ctx, posts); err != nil {
		return p, err
	}
	return posts[0], nil
}

// attachImages loads images for all posts with a single query.
func (s *Svc) attachImages(ctx context.Context, posts []Post) error {
	if len(posts) == 0 {
		return nil
	}
	ids := make([]uuid.UUID, len(posts))
	idx := map[uuid.UUID]int{}
	for i, p := range posts {
		ids[i] = p.ID
		idx[p.ID] = i
	}
	rows, err := s.DB.Query(ctx, `
		SELECT post_id, id, file_path, thumb_path, sort_order
		FROM post_images WHERE post_id = ANY($1::uuid[]) ORDER BY post_id, sort_order`, uuidStrings(ids))
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var pid uuid.UUID
		var im PostImage
		if err := rows.Scan(&pid, &im.ID, &im.FilePath, &im.ThumbPath, &im.SortOrder); err != nil {
			return err
		}
		i := idx[pid]
		posts[i].Images = append(posts[i].Images, im)
	}
	return rows.Err()
}

func (s *Svc) ListPosts(ctx context.Context, me uuid.UUID, cursor *time.Time, limit int, authorID *uuid.UUID) (PostFeed, error) {
	if limit <= 0 || limit > 50 {
		limit = 20
	}
	args := []any{me}
	var where []string
	if cursor != nil {
		args = append(args, *cursor)
		where = append(where, fmt.Sprintf("p.created_at < $%d", len(args)))
	}
	if authorID != nil {
		args = append(args, *authorID)
		where = append(where, fmt.Sprintf("p.author_id = $%d", len(args)))
	}
	q := postSelect
	if len(where) > 0 {
		q += " WHERE " + strings.Join(where, " AND ")
	}
	args = append(args, limit)
	q += fmt.Sprintf(" ORDER BY p.created_at DESC LIMIT $%d", len(args))
	rows, err := s.DB.Query(ctx, q, args...)
	if err != nil {
		return PostFeed{}, err
	}
	posts := []Post{}
	for rows.Next() {
		p, err := scanPost(rows)
		if err != nil {
			rows.Close()
			return PostFeed{}, err
		}
		posts = append(posts, p)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return PostFeed{}, err
	}
	if err := s.attachImages(ctx, posts); err != nil {
		return PostFeed{}, err
	}
	feed := PostFeed{Posts: posts}
	if len(posts) == limit {
		c := posts[len(posts)-1].CreatedAt.UTC().Format(time.RFC3339Nano)
		feed.NextCursor = &c
	}
	return feed, nil
}

func (s *Svc) DeletePost(ctx context.Context, me, id uuid.UUID) error {
	var files []string
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		var author uuid.UUID
		if err := tx.QueryRow(ctx, `SELECT author_id FROM posts WHERE id=$1 FOR UPDATE`, id).Scan(&author); err != nil {
			if isNoRows(err) {
				return httpx.NotFound("post not found")
			}
			return err
		}
		if author != me {
			return httpx.Forbidden("you can only delete your own posts")
		}
		rows, err := tx.Query(ctx, `SELECT file_path, thumb_path FROM post_images WHERE post_id=$1`, id)
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
		_, err = tx.Exec(ctx, `DELETE FROM posts WHERE id=$1`, id)
		return err
	})
	if err != nil {
		return err
	}
	s.removeFiles(files...)
	return nil
}

func (s *Svc) ToggleLike(ctx context.Context, me, postID uuid.UUID) (LikeResult, error) {
	var res LikeResult
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		if err := tx.QueryRow(ctx, `SELECT like_count FROM posts WHERE id=$1 FOR UPDATE`, postID).Scan(&res.LikeCount); err != nil {
			if isNoRows(err) {
				return httpx.NotFound("post not found")
			}
			return err
		}
		tag, err := tx.Exec(ctx, `DELETE FROM likes WHERE post_id=$1 AND user_id=$2`, postID, me)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			if _, err := tx.Exec(ctx, `INSERT INTO likes(id, post_id, user_id) VALUES ($1,$2,$3)`, uuid.New(), postID, me); err != nil {
				return err
			}
			res.Liked = true
			return tx.QueryRow(ctx, `UPDATE posts SET like_count = like_count + 1 WHERE id=$1 RETURNING like_count`, postID).Scan(&res.LikeCount)
		}
		return tx.QueryRow(ctx, `UPDATE posts SET like_count = GREATEST(like_count - 1, 0) WHERE id=$1 RETURNING like_count`, postID).Scan(&res.LikeCount)
	})
	return res, err
}

func (s *Svc) AddComment(ctx context.Context, me, postID uuid.UUID, body string) (Comment, error) {
	body, err := TrimmedText("comment", body, 1, 1000)
	if err != nil {
		return Comment{}, err
	}
	c := Comment{ID: uuid.New(), PostID: postID, UserID: me, Body: body}
	err = s.inTx(ctx, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `UPDATE posts SET comment_count = comment_count + 1 WHERE id=$1`, postID)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return httpx.NotFound("post not found")
		}
		return tx.QueryRow(ctx, `
			INSERT INTO comments(id, post_id, user_id, body) VALUES ($1,$2,$3,$4) RETURNING created_at`,
			c.ID, postID, me, body).Scan(&c.CreatedAt)
	})
	if err != nil {
		return Comment{}, err
	}
	u, err := s.getUser(ctx, me)
	if err != nil {
		return Comment{}, err
	}
	c.User = u.Public()
	return c, nil
}

func (s *Svc) ListComments(ctx context.Context, postID uuid.UUID) ([]Comment, error) {
	var exists bool
	if err := s.DB.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM posts WHERE id=$1)`, postID).Scan(&exists); err != nil {
		return nil, err
	}
	if !exists {
		return nil, httpx.NotFound("post not found")
	}
	rows, err := s.DB.Query(ctx, `
		SELECT c.id, c.post_id, c.user_id, c.body, c.created_at, u.username, u.display_name, u.avatar_path
		FROM comments c JOIN users u ON u.id=c.user_id
		WHERE c.post_id=$1 ORDER BY c.created_at ASC LIMIT 500`, postID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Comment{}
	for rows.Next() {
		var c Comment
		if err := rows.Scan(&c.ID, &c.PostID, &c.UserID, &c.Body, &c.CreatedAt,
			&c.User.Username, &c.User.DisplayName, &c.User.AvatarPath); err != nil {
			return nil, err
		}
		c.User.ID = c.UserID
		out = append(out, c)
	}
	return out, rows.Err()
}

func (s *Svc) DeleteComment(ctx context.Context, me, postID, commentID uuid.UUID) error {
	return s.inTx(ctx, func(tx pgx.Tx) error {
		var commenter, author uuid.UUID
		err := tx.QueryRow(ctx, `
			SELECT c.user_id, p.author_id FROM comments c JOIN posts p ON p.id=c.post_id
			WHERE c.id=$1 AND c.post_id=$2 FOR UPDATE OF c`, commentID, postID).Scan(&commenter, &author)
		if isNoRows(err) {
			return httpx.NotFound("comment not found")
		}
		if err != nil {
			return err
		}
		if me != commenter && me != author {
			return httpx.Forbidden("you can't delete this comment")
		}
		if _, err := tx.Exec(ctx, `DELETE FROM comments WHERE id=$1`, commentID); err != nil {
			return err
		}
		_, err = tx.Exec(ctx, `UPDATE posts SET comment_count = GREATEST(comment_count - 1, 0) WHERE id=$1`, postID)
		return err
	})
}
