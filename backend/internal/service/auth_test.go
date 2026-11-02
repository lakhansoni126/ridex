package service

import (
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/lakhansoni126/ridex/backend/internal/config"
)

func TestAccessTokenRoundTrip(t *testing.T) {
	s := New(nil, config.Config{
		JWTSecret: "test-secret",
		AccessTTL: time.Hour,
	}, nil)
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

func TestPasswordHash(t *testing.T) {
	s := New(nil, config.Config{}, nil)
	h, err := s.HashPassword("password123")
	if err != nil || !s.CheckPassword(h, "password123") || s.CheckPassword(h, "nope") {
		t.Fatal("password hash/verify failed")
	}
}
