package service

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/lakhansoni126/ridex/backend/internal/config"
	"github.com/lakhansoni126/ridex/backend/internal/httpx"
	"github.com/lakhansoni126/ridex/backend/internal/ws"
	"golang.org/x/crypto/bcrypt"
)

// Svc is the shared application service layer — inject once, reuse everywhere.
type Svc struct {
	DB  *pgxpool.Pool
	Cfg config.Config
	Hub *ws.Hub

	wsLocation *Limiter // min gap between WS location messages per user+target
	login      *Limiter // per (ip,email) attempts
	register   *Limiter // per ip
}

func New(db *pgxpool.Pool, cfg config.Config, hub *ws.Hub) *Svc {
	return &Svc{
		DB:         db,
		Cfg:        cfg,
		Hub:        hub,
		wsLocation: NewLimiter(1, time.Second),
		login:      NewLimiter(10, 15*time.Minute),
		register:   NewLimiter(20, time.Hour),
	}
}

func (s *Svc) HashPassword(pw string) (string, error) {
	b, err := bcrypt.GenerateFromPassword([]byte(pw), bcrypt.DefaultCost)
	return string(b), err
}

func (s *Svc) CheckPassword(hash, pw string) bool {
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(pw)) == nil
}

func (s *Svc) HashToken(raw string) string {
	sum := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(sum[:])
}

func randomToken() string {
	b := make([]byte, 32)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func (s *Svc) IssueAccess(userID uuid.UUID) (string, error) {
	claims := jwt.MapClaims{
		"sub":  userID.String(),
		"type": "access",
		"iat":  time.Now().Unix(),
		"exp":  time.Now().Add(s.Cfg.AccessTTL).Unix(),
		"jti":  uuid.NewString(),
	}
	return jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString([]byte(s.Cfg.JWTSecret))
}

var errInvalidToken = httpx.E(http.StatusUnauthorized, "invalid token")

// ParseAccess validates signature (HS256 only), expiry and token type.
func (s *Svc) ParseAccess(token string) (uuid.UUID, error) {
	parsed, err := jwt.Parse(token, func(t *jwt.Token) (any, error) {
		return []byte(s.Cfg.JWTSecret), nil
	}, jwt.WithValidMethods([]string{"HS256"}), jwt.WithExpirationRequired())
	if err != nil || !parsed.Valid {
		return uuid.Nil, errInvalidToken
	}
	claims, _ := parsed.Claims.(jwt.MapClaims)
	if claims["type"] != "access" {
		return uuid.Nil, errInvalidToken
	}
	sub, _ := claims["sub"].(string)
	id, err := uuid.Parse(sub)
	if err != nil {
		return uuid.Nil, errInvalidToken
	}
	return id, nil
}

// AuthenticateAccess parses the token and checks that the user still exists.
func (s *Svc) AuthenticateAccess(ctx context.Context, token string) (uuid.UUID, error) {
	id, err := s.ParseAccess(token)
	if err != nil {
		return uuid.Nil, err
	}
	var active bool
	if err := s.DB.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM users WHERE id=$1 AND deleted_at IS NULL)`, id).Scan(&active); err != nil || !active {
		return uuid.Nil, errInvalidToken
	}
	return id, nil
}

func pointWKT(lon, lat float64) string {
	return "SRID=4326;POINT(" + strconv.FormatFloat(lon, 'f', 7, 64) + " " + strconv.FormatFloat(lat, 'f', 7, 64) + ")"
}

// pgErrCode returns the Postgres error code and constraint name, if any.
func pgErr(err error) (code, constraint string) {
	var pe *pgconn.PgError
	if errors.As(err, &pe) {
		return pe.Code, pe.ConstraintName
	}
	return "", ""
}

func isUniqueViolation(err error) bool {
	code, _ := pgErr(err)
	return code == "23505"
}

func isNoRows(err error) bool { return errors.Is(err, pgx.ErrNoRows) }

// inTx runs fn inside a transaction.
func (s *Svc) inTx(ctx context.Context, fn func(tx pgx.Tx) error) error {
	tx, err := s.DB.Begin(ctx)
	if err != nil {
		return err
	}
	if err := fn(tx); err != nil {
		_ = tx.Rollback(ctx)
		return err
	}
	return tx.Commit(ctx)
}
