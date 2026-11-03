package config

import (
	"errors"
	"os"
	"strconv"
	"strings"
	"time"
)

// DefaultJWTSecret is the placeholder secret shipped in .env.example. It is
// rejected when APP_ENV=production.
const DefaultJWTSecret = "change-me-to-a-long-random-string"

type Config struct {
	Env                string
	DatabaseURL        string
	JWTSecret          string
	AccessTTL          time.Duration
	RefreshTTL         time.Duration
	StorageRoot        string
	MediaMaxBytes      int64
	CORSOrigins        []string
	Addr               string
	LocationRetainDays int
}

func Load() Config {
	return Config{
		Env:                strings.ToLower(env("APP_ENV", "development")),
		DatabaseURL:        env("DATABASE_URL", "postgres://ridex:ridex_dev_password@localhost:5432/ridex?sslmode=disable"),
		JWTSecret:          env("JWT_SECRET", DefaultJWTSecret),
		AccessTTL:          time.Duration(envInt("JWT_ACCESS_TOKEN_EXPIRE_MINUTES", 30)) * time.Minute,
		RefreshTTL:         time.Duration(envInt("JWT_REFRESH_TOKEN_EXPIRE_DAYS", 30)) * 24 * time.Hour,
		StorageRoot:        env("STORAGE_ROOT", "../storage"),
		MediaMaxBytes:      int64(envInt("MEDIA_MAX_UPLOAD_MB", 10)) * 1024 * 1024,
		CORSOrigins:        splitTrim(env("CORS_ORIGINS", "*")),
		Addr:               ":" + env("API_PORT", "8000"),
		LocationRetainDays: envInt("LOCATION_RETENTION_DAYS", 30),
	}
}

// IsProduction reports whether APP_ENV=production.
func (c Config) IsProduction() bool { return c.Env == "production" || c.Env == "prod" }

// Validate refuses unsafe settings in production.
func (c Config) Validate() error {
	if !c.IsProduction() {
		return nil
	}
	if c.JWTSecret == DefaultJWTSecret || len(c.JWTSecret) < 32 {
		return errors.New("JWT_SECRET must be set to a random value of at least 32 characters when APP_ENV=production")
	}
	return nil
}

func splitTrim(v string) []string {
	var out []string
	for _, p := range strings.Split(v, ",") {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}

func env(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func envInt(k string, def int) int {
	if v := os.Getenv(k); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return def
}
