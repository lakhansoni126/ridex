package db

import (
	"context"
	"embed"
	"fmt"
	"io/fs"
	"sort"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

//go:embed migrations/*.sql
var migrationFS embed.FS

// migrationLockKey is an arbitrary constant for pg_advisory_lock so that
// concurrent API replicas never run migrations at the same time.
const migrationLockKey int64 = 0x52494445580001

// Migration is one versioned SQL file (e.g. "001_init").
type Migration struct {
	Version string
	SQL     string
}

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

// Migrations returns the embedded migrations sorted by version.
func Migrations() ([]Migration, error) {
	entries, err := fs.ReadDir(migrationFS, "migrations")
	if err != nil {
		return nil, err
	}
	var out []Migration
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".sql") {
			continue
		}
		b, err := migrationFS.ReadFile("migrations/" + e.Name())
		if err != nil {
			return nil, err
		}
		out = append(out, Migration{Version: strings.TrimSuffix(e.Name(), ".sql"), SQL: string(b)})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Version < out[j].Version })
	return out, nil
}

// Migrate applies every embedded migration not yet recorded in
// schema_migrations, each in its own transaction, under an advisory lock.
func Migrate(ctx context.Context, pool *pgxpool.Pool) error {
	conn, err := pool.Acquire(ctx)
	if err != nil {
		return err
	}
	defer conn.Release()

	if _, err := conn.Exec(ctx, `SELECT pg_advisory_lock($1)`, migrationLockKey); err != nil {
		return fmt.Errorf("migrate lock: %w", err)
	}
	defer conn.Exec(context.Background(), `SELECT pg_advisory_unlock($1)`, migrationLockKey) //nolint:errcheck

	if _, err := conn.Exec(ctx, `
		CREATE TABLE IF NOT EXISTS schema_migrations (
		  version TEXT PRIMARY KEY,
		  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
		)`); err != nil {
		return fmt.Errorf("migrate bootstrap: %w", err)
	}

	migs, err := Migrations()
	if err != nil {
		return err
	}
	for _, m := range migs {
		var exists bool
		if err := conn.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM schema_migrations WHERE version=$1)`, m.Version).Scan(&exists); err != nil {
			return err
		}
		if exists {
			continue
		}
		tx, err := conn.Begin(ctx)
		if err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, m.SQL); err != nil {
			_ = tx.Rollback(ctx)
			return fmt.Errorf("migrate %s: %w", m.Version, err)
		}
		if _, err := tx.Exec(ctx, `INSERT INTO schema_migrations(version) VALUES ($1)`, m.Version); err != nil {
			_ = tx.Rollback(ctx)
			return fmt.Errorf("migrate %s record: %w", m.Version, err)
		}
		if err := tx.Commit(ctx); err != nil {
			return fmt.Errorf("migrate %s commit: %w", m.Version, err)
		}
	}
	return nil
}
