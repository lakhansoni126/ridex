package service

import (
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"strconv"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
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

	rateMu sync.Mutex
	rate   map[string]time.Time
}

func New(db *pgxpool.Pool, cfg config.Config, hub *ws.Hub) *Svc {
	return &Svc{DB: db, Cfg: cfg, Hub: hub, rate: map[string]time.Time{}}
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

func (s *Svc) IssueAccess(userID uuid.UUID) (string, error) {
	claims := jwt.MapClaims{
		"sub":  userID.String(),
		"type": "access",
		"exp":  time.Now().Add(s.Cfg.AccessTTL).Unix(),
		"jti":  uuid.NewString(),
	}
	return jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString([]byte(s.Cfg.JWTSecret))
}

func (s *Svc) ParseAccess(token string) (uuid.UUID, error) {
	parsed, err := jwt.Parse(token, func(t *jwt.Token) (any, error) {
		return []byte(s.Cfg.JWTSecret), nil
	})
	if err != nil || !parsed.Valid {
		return uuid.Nil, httpx.E(http.StatusUnauthorized, "invalid token")
	}
	claims, _ := parsed.Claims.(jwt.MapClaims)
	if claims["type"] != "access" {
		return uuid.Nil, httpx.E(http.StatusUnauthorized, "invalid token")
	}
	sub, _ := claims["sub"].(string)
	id, err := uuid.Parse(sub)
	if err != nil {
		return uuid.Nil, httpx.E(http.StatusUnauthorized, "invalid token")
	}
	return id, nil
}

func (s *Svc) AllowLocation(userID uuid.UUID, minGap time.Duration) bool {
	s.rateMu.Lock()
	defer s.rateMu.Unlock()
	k := userID.String()
	if t, ok := s.rate[k]; ok && time.Since(t) < minGap {
		return false
	}
	s.rate[k] = time.Now()
	return true
}

func pointWKT(lon, lat float64) string {
	return "SRID=4326;POINT(" + strconv.FormatFloat(lon, 'f', 7, 64) + " " + strconv.FormatFloat(lat, 'f', 7, 64) + ")"
}
