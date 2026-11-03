package service

import (
	"context"
	"log/slog"
	"time"
)

// RunJanitor performs periodic cleanup until ctx is cancelled.
func (s *Svc) RunJanitor(ctx context.Context, every time.Duration) {
	s.cleanup(ctx)
	t := time.NewTicker(every)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			s.cleanup(ctx)
		}
	}
}

func (s *Svc) cleanup(ctx context.Context) {
	s.wsLocation.Prune()
	s.login.Prune()
	s.register.Prune()

	ctx, cancel := context.WithTimeout(ctx, 2*time.Minute)
	defer cancel()
	jobs := []struct {
		name string
		sql  string
		args []any
	}{
		{"location_points_retention", `DELETE FROM location_points WHERE recorded_at < now() - make_interval(days => $1)`, []any{s.Cfg.LocationRetainDays}},
		{"expire_location_shares", `UPDATE location_shares SET is_active=false WHERE is_active AND expires_at IS NOT NULL AND expires_at <= now()`, nil},
		{"refresh_tokens", `DELETE FROM refresh_tokens WHERE (expires_at < now() - interval '7 days') OR (revoked_at IS NOT NULL AND revoked_at < now() - interval '7 days')`, nil},
	}
	for _, j := range jobs {
		if j.name == "location_points_retention" && s.Cfg.LocationRetainDays <= 0 {
			continue
		}
		tag, err := s.DB.Exec(ctx, j.sql, j.args...)
		if err != nil {
			if ctx.Err() == nil {
				slog.Error("janitor job failed", "job", j.name, "err", err)
			}
			continue
		}
		if n := tag.RowsAffected(); n > 0 {
			slog.Info("janitor", "job", j.name, "rows", n)
		}
	}
}
