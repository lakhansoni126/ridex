package db

import (
	"context"
	_ "embed"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

//go:embed schema.sql
var schemaSQL string

func Connect(ctx context.Context, url string) (*pgxpool.Pool, error) {
	url = strings.Replace(url, "postgresql+psycopg://", "postgres://", 1)
	url = strings.Replace(url, "postgresql://", "postgres://", 1)
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		return nil, err
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, err
	}
	return pool, nil
}

func Migrate(ctx context.Context, pool *pgxpool.Pool) error {
	if _, err := pool.Exec(ctx, schemaSQL); err != nil {
		return fmt.Errorf("migrate: %w", err)
	}
	_, _ = pool.Exec(ctx, `INSERT INTO schema_migrations(version) VALUES ('001_init') ON CONFLICT DO NOTHING`)
	return nil
}
