package service

import (
	"math"
	"net/http"
	"regexp"
	"strings"
	"unicode/utf8"

	"github.com/lakhansoni126/ridex/backend/internal/httpx"
)

var usernamePattern = regexp.MustCompile(`^[a-z0-9_.]{3,32}$`)

// NormalizeEmail lowercases/trims and checks a basic address shape.
func NormalizeEmail(raw string) (string, error) {
	e := strings.ToLower(strings.TrimSpace(raw))
	if len(e) > 320 {
		return "", httpx.BadRequest("email is too long")
	}
	at := strings.LastIndex(e, "@")
	if at < 1 || at == len(e)-1 || strings.ContainsAny(e, " \t\r\n") {
		return "", httpx.BadRequest("enter a valid email address")
	}
	domain := e[at+1:]
	dot := strings.LastIndex(domain, ".")
	if dot < 1 || dot == len(domain)-1 {
		return "", httpx.BadRequest("enter a valid email address")
	}
	return e, nil
}

// NormalizeUsername lowercases/trims and enforces ^[a-z0-9_.]{3,32}$.
func NormalizeUsername(raw string) (string, error) {
	u := strings.ToLower(strings.TrimSpace(raw))
	if !usernamePattern.MatchString(u) {
		return "", httpx.BadRequest("username must be 3-32 characters: letters, numbers, '_' or '.'")
	}
	return u, nil
}

// ValidatePassword enforces 8..128 characters.
func ValidatePassword(pw string) error {
	n := utf8.RuneCountInString(pw)
	if n < 8 {
		return httpx.BadRequest("password must be at least 8 characters")
	}
	if n > 128 {
		return httpx.BadRequest("password must be at most 128 characters")
	}
	return nil
}

// TrimmedText trims s and checks min..max runes.
func TrimmedText(field, s string, min, max int) (string, error) {
	t := strings.TrimSpace(s)
	n := utf8.RuneCountInString(t)
	if n < min {
		if min == 1 {
			return "", httpx.BadRequest(field + " is required")
		}
		return "", httpx.E(http.StatusBadRequest, field+" is too short")
	}
	if n > max {
		return "", httpx.E(http.StatusBadRequest, field+" is too long")
	}
	return t, nil
}

// ValidCoord reports whether lat/lon are finite and in range.
func ValidCoord(lat, lon float64) bool {
	if math.IsNaN(lat) || math.IsNaN(lon) || math.IsInf(lat, 0) || math.IsInf(lon, 0) {
		return false
	}
	return lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180
}
