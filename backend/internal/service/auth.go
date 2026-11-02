package service

import (
	"context"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/lakhansoni126/ridex/backend/internal/httpx"
)

func (s *Svc) getUser(ctx context.Context, id uuid.UUID) (User, error) {
	var u User
	err := s.DB.QueryRow(ctx, `
		SELECT id, email, username, display_name, avatar_path, bio, created_at
		FROM users WHERE id=$1 AND deleted_at IS NULL`, id,
	).Scan(&u.ID, &u.Email, &u.Username, &u.DisplayName, &u.AvatarPath, &u.Bio, &u.CreatedAt)
	if err == pgx.ErrNoRows {
		return u, httpx.E(http.StatusNotFound, "user not found")
	}
	return u, err
}

func (s *Svc) issueTokens(ctx context.Context, u User) (TokenOut, error) {
	access, err := s.IssueAccess(u.ID)
	if err != nil {
		return TokenOut{}, err
	}
	raw := uuid.NewString() + uuid.NewString()
	_, err = s.DB.Exec(ctx, `
		INSERT INTO refresh_tokens(id, user_id, token_hash, expires_at)
		VALUES ($1,$2,$3,$4)`,
		uuid.New(), u.ID, s.HashToken(raw), time.Now().UTC().Add(s.Cfg.RefreshTTL),
	)
	if err != nil {
		return TokenOut{}, err
	}
	return TokenOut{AccessToken: access, RefreshToken: raw, TokenType: "bearer", User: u}, nil
}

func (s *Svc) Register(ctx context.Context, email, username, password, displayName string) (TokenOut, error) {
	email, username = strings.ToLower(strings.TrimSpace(email)), strings.ToLower(strings.TrimSpace(username))
	hash, err := s.HashPassword(password)
	if err != nil {
		return TokenOut{}, err
	}
	u := User{ID: uuid.New(), Email: email, Username: username, DisplayName: strings.TrimSpace(displayName), CreatedAt: time.Now().UTC()}
	_, err = s.DB.Exec(ctx, `
		INSERT INTO users(id,email,username,password_hash,display_name)
		VALUES ($1,$2,$3,$4,$5)`, u.ID, email, username, hash, u.DisplayName)
	if err != nil {
		return TokenOut{}, httpx.E(http.StatusConflict, "email or username already registered")
	}
	return s.issueTokens(ctx, u)
}

func (s *Svc) Login(ctx context.Context, email, password string) (TokenOut, error) {
	email = strings.ToLower(strings.TrimSpace(email))
	var u User
	var hash string
	err := s.DB.QueryRow(ctx, `
		SELECT id, email, username, display_name, avatar_path, bio, created_at, password_hash
		FROM users WHERE email=$1 AND deleted_at IS NULL`, email,
	).Scan(&u.ID, &u.Email, &u.Username, &u.DisplayName, &u.AvatarPath, &u.Bio, &u.CreatedAt, &hash)
	if err != nil || !s.CheckPassword(hash, password) {
		return TokenOut{}, httpx.E(http.StatusUnauthorized, "invalid credentials")
	}
	return s.issueTokens(ctx, u)
}

func (s *Svc) Refresh(ctx context.Context, raw string) (TokenOut, error) {
	var userID uuid.UUID
	var id uuid.UUID
	err := s.DB.QueryRow(ctx, `
		SELECT id, user_id FROM refresh_tokens
		WHERE token_hash=$1 AND revoked_at IS NULL AND expires_at > now()`, s.HashToken(raw),
	).Scan(&id, &userID)
	if err != nil {
		return TokenOut{}, httpx.E(http.StatusUnauthorized, "invalid refresh token")
	}
	_, _ = s.DB.Exec(ctx, `UPDATE refresh_tokens SET revoked_at=now() WHERE id=$1`, id)
	u, err := s.getUser(ctx, userID)
	if err != nil {
		return TokenOut{}, err
	}
	return s.issueTokens(ctx, u)
}

func (s *Svc) Logout(ctx context.Context, raw string) error {
	_, err := s.DB.Exec(ctx, `
		UPDATE refresh_tokens SET revoked_at=now()
		WHERE token_hash=$1 AND revoked_at IS NULL`, s.HashToken(raw))
	return err
}

func (s *Svc) Me(ctx context.Context, id uuid.UUID) (User, error) { return s.getUser(ctx, id) }

func (s *Svc) UpdateMe(ctx context.Context, id uuid.UUID, displayName, bio *string) (User, error) {
	_, err := s.DB.Exec(ctx, `
		UPDATE users SET
			display_name = COALESCE($2, display_name),
			bio = COALESCE($3, bio),
			updated_at = now()
		WHERE id=$1`, id, displayName, bio)
	if err != nil {
		return User{}, err
	}
	return s.getUser(ctx, id)
}
