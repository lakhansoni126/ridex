package service

import (
	"context"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/lakhansoni126/ridex/backend/internal/httpx"
	"golang.org/x/crypto/bcrypt"
)

var (
	errTooManyAttempts = httpx.E(http.StatusTooManyRequests, "too many attempts, try again later")
	errBadCredentials  = httpx.E(http.StatusUnauthorized, "invalid email or password")
	errBadRefresh      = httpx.E(http.StatusUnauthorized, "invalid refresh token")
)

// dummyHash equalizes login timing for unknown emails.
var dummyHash = sync.OnceValue(func() string {
	b, _ := bcrypt.GenerateFromPassword([]byte("ridex-timing-equalizer"), bcrypt.DefaultCost)
	return string(b)
})

func (s *Svc) getUser(ctx context.Context, id uuid.UUID) (User, error) {
	var u User
	err := s.DB.QueryRow(ctx, `
		SELECT id, email, username, display_name, avatar_path, bio, created_at
		FROM users WHERE id=$1 AND deleted_at IS NULL`, id,
	).Scan(&u.ID, &u.Email, &u.Username, &u.DisplayName, &u.AvatarPath, &u.Bio, &u.CreatedAt)
	if isNoRows(err) {
		return u, httpx.NotFound("user not found")
	}
	return u, err
}

func (s *Svc) issueTokens(ctx context.Context, u User) (TokenOut, error) {
	access, err := s.IssueAccess(u.ID)
	if err != nil {
		return TokenOut{}, err
	}
	raw := randomToken()
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

// Register creates an account. ip is used for abuse rate limiting ("" skips it).
func (s *Svc) Register(ctx context.Context, ip, email, username, password, displayName string) (TokenOut, error) {
	if ip != "" && !s.register.Allow(ip) {
		return TokenOut{}, errTooManyAttempts
	}
	email, err := NormalizeEmail(email)
	if err != nil {
		return TokenOut{}, err
	}
	username, err = NormalizeUsername(username)
	if err != nil {
		return TokenOut{}, err
	}
	if err := ValidatePassword(password); err != nil {
		return TokenOut{}, err
	}
	displayName, err = TrimmedText("display name", displayName, 1, 60)
	if err != nil {
		return TokenOut{}, err
	}
	hash, err := s.HashPassword(password)
	if err != nil {
		return TokenOut{}, err
	}
	u := User{ID: uuid.New(), Email: email, Username: username, DisplayName: displayName, CreatedAt: time.Now().UTC()}
	_, err = s.DB.Exec(ctx, `
		INSERT INTO users(id,email,username,password_hash,display_name)
		VALUES ($1,$2,$3,$4,$5)`, u.ID, email, username, hash, u.DisplayName)
	if err != nil {
		if code, constraint := pgErr(err); code == "23505" {
			if strings.Contains(constraint, "username") {
				return TokenOut{}, httpx.Conflict("username taken")
			}
			return TokenOut{}, httpx.Conflict("email already registered")
		}
		return TokenOut{}, err
	}
	return s.issueTokens(ctx, u)
}

// Login checks credentials. ip is used for brute-force limiting ("" skips it).
func (s *Svc) Login(ctx context.Context, ip, email, password string) (TokenOut, error) {
	email = strings.ToLower(strings.TrimSpace(email))
	key := ip + "|" + email
	if ip != "" && !s.login.Allow(key) {
		return TokenOut{}, errTooManyAttempts
	}
	var u User
	var hash string
	err := s.DB.QueryRow(ctx, `
		SELECT id, email, username, display_name, avatar_path, bio, created_at, password_hash
		FROM users WHERE email=$1 AND deleted_at IS NULL`, email,
	).Scan(&u.ID, &u.Email, &u.Username, &u.DisplayName, &u.AvatarPath, &u.Bio, &u.CreatedAt, &hash)
	if err != nil {
		if !isNoRows(err) {
			return TokenOut{}, err
		}
		s.CheckPassword(dummyHash(), password)
		return TokenOut{}, errBadCredentials
	}
	if !s.CheckPassword(hash, password) {
		return TokenOut{}, errBadCredentials
	}
	if ip != "" {
		s.login.Reset(key)
	}
	return s.issueTokens(ctx, u)
}

// Refresh rotates a refresh token. Presenting an already-revoked token is
// treated as theft: every token of that user is revoked.
func (s *Svc) Refresh(ctx context.Context, raw string) (TokenOut, error) {
	var id, userID uuid.UUID
	var revokedAt *time.Time
	var expiresAt time.Time
	err := s.DB.QueryRow(ctx, `
		SELECT id, user_id, revoked_at, expires_at FROM refresh_tokens WHERE token_hash=$1`,
		s.HashToken(raw),
	).Scan(&id, &userID, &revokedAt, &expiresAt)
	if err != nil {
		if isNoRows(err) {
			return TokenOut{}, errBadRefresh
		}
		return TokenOut{}, err
	}
	if revokedAt != nil {
		_, _ = s.DB.Exec(ctx, `UPDATE refresh_tokens SET revoked_at=now() WHERE user_id=$1 AND revoked_at IS NULL`, userID)
		return TokenOut{}, errBadRefresh
	}
	if time.Now().After(expiresAt) {
		return TokenOut{}, errBadRefresh
	}
	tag, err := s.DB.Exec(ctx, `UPDATE refresh_tokens SET revoked_at=now() WHERE id=$1 AND revoked_at IS NULL`, id)
	if err != nil {
		return TokenOut{}, err
	}
	if tag.RowsAffected() == 0 {
		return TokenOut{}, errBadRefresh
	}
	u, err := s.getUser(ctx, userID)
	if err != nil {
		return TokenOut{}, errBadRefresh
	}
	return s.issueTokens(ctx, u)
}

func (s *Svc) Logout(ctx context.Context, raw string) error {
	_, err := s.DB.Exec(ctx, `
		UPDATE refresh_tokens SET revoked_at=now()
		WHERE token_hash=$1 AND revoked_at IS NULL`, s.HashToken(raw))
	return err
}
