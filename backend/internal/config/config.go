package config

import (
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	DatabaseURL       string
	JWTSecret         string
	AccessTTL         time.Duration
	RefreshTTL        time.Duration
	StorageRoot       string
	MediaMaxBytes     int64
	CORSOrigins       []string
	Addr              string
	LocationRetainDays int
}

func Load() Config {
	return Config{
		DatabaseURL:        env("DATABASE_URL", "postgres://ridex:ridex_dev_password@localhost:5432/ridex?sslmode=disable"),
		JWTSecret:          env("JWT_SECRET", "change-me-to-a-long-random-string"),
		AccessTTL:          time.Duration(envInt("JWT_ACCESS_TOKEN_EXPIRE_MINUTES", 30)) * time.Minute,
		RefreshTTL:         time.Duration(envInt("JWT_REFRESH_TOKEN_EXPIRE_DAYS", 30)) * 24 * time.Hour,
		StorageRoot:        env("STORAGE_ROOT", "../storage"),
		MediaMaxBytes:      int64(envInt("MEDIA_MAX_UPLOAD_MB", 10)) * 1024 * 1024,
		CORSOrigins:        strings.Split(env("CORS_ORIGINS", "*"), ","),
		Addr:               ":" + env("API_PORT", "8000"),
		LocationRetainDays: envInt("LOCATION_RETENTION_DAYS", 30),
	}
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
