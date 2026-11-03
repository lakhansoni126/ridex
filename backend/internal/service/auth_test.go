package service

import (
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/lakhansoni126/ridex/backend/internal/config"
)

func testSvc() *Svc {
	return New(nil, config.Config{JWTSecret: "test-secret-test-secret-test-secret", AccessTTL: time.Hour}, nil)
}

func TestAccessTokenRoundTrip(t *testing.T) {
	s := testSvc()
	id := uuid.New()
	tok, err := s.IssueAccess(id)
	if err != nil {
		t.Fatal(err)
	}
	got, err := s.ParseAccess(tok)
	if err != nil || got != id {
		t.Fatalf("got %v err %v", got, err)
	}
}

func TestParseAccessRejectsOtherAlgorithms(t *testing.T) {
	s := testSvc()
	claims := jwt.MapClaims{"sub": uuid.NewString(), "type": "access", "exp": time.Now().Add(time.Hour).Unix()}

	// HS512 with the right secret: must be rejected (only HS256 allowed).
	tok, err := jwt.NewWithClaims(jwt.SigningMethodHS512, claims).SignedString([]byte(s.Cfg.JWTSecret))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.ParseAccess(tok); err == nil {
		t.Fatal("HS512 token accepted")
	}

	// alg=none must be rejected.
	none, err := jwt.NewWithClaims(jwt.SigningMethodNone, claims).SignedString(jwt.UnsafeAllowNoneSignatureType)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.ParseAccess(none); err == nil {
		t.Fatal("alg=none token accepted")
	}
}

func TestParseAccessRequiresExpAndType(t *testing.T) {
	s := testSvc()
	noExp, _ := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{"sub": uuid.NewString(), "type": "access"}).
		SignedString([]byte(s.Cfg.JWTSecret))
	if _, err := s.ParseAccess(noExp); err == nil {
		t.Fatal("token without exp accepted")
	}
	refreshType, _ := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub": uuid.NewString(), "type": "refresh", "exp": time.Now().Add(time.Hour).Unix(),
	}).SignedString([]byte(s.Cfg.JWTSecret))
	if _, err := s.ParseAccess(refreshType); err == nil {
		t.Fatal("non-access token accepted")
	}
	expired, _ := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub": uuid.NewString(), "type": "access", "exp": time.Now().Add(-time.Minute).Unix(),
	}).SignedString([]byte(s.Cfg.JWTSecret))
	if _, err := s.ParseAccess(expired); err == nil {
		t.Fatal("expired token accepted")
	}
}

func TestPasswordHash(t *testing.T) {
	s := testSvc()
	h, err := s.HashPassword("password123")
	if err != nil || !s.CheckPassword(h, "password123") || s.CheckPassword(h, "nope") {
		t.Fatal("password hash/verify failed")
	}
}

func TestConfigValidateProduction(t *testing.T) {
	c := config.Config{Env: "production", JWTSecret: config.DefaultJWTSecret}
	if c.Validate() == nil {
		t.Fatal("default secret accepted in production")
	}
	c.JWTSecret = "short"
	if c.Validate() == nil {
		t.Fatal("short secret accepted in production")
	}
	c.JWTSecret = "0123456789abcdef0123456789abcdef"
	if err := c.Validate(); err != nil {
		t.Fatal(err)
	}
	if (config.Config{Env: "development", JWTSecret: config.DefaultJWTSecret}).Validate() != nil {
		t.Fatal("development should allow the default secret")
	}
}
