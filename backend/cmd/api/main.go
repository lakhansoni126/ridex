package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/lakhansoni126/ridex/backend/internal/config"
	"github.com/lakhansoni126/ridex/backend/internal/db"
	"github.com/lakhansoni126/ridex/backend/internal/handler"
	"github.com/lakhansoni126/ridex/backend/internal/middleware"
	"github.com/lakhansoni126/ridex/backend/internal/service"
	"github.com/lakhansoni126/ridex/backend/internal/ws"
)

const jsonBodyLimit = 1 << 20 // 1 MiB for non-upload requests

func main() {
	cfg := config.Load()
	setupLogging(cfg)
	if err := cfg.Validate(); err != nil {
		fatal("invalid configuration", err)
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	startCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	pool, err := db.Connect(startCtx, cfg.DatabaseURL)
	if err != nil {
		cancel()
		fatal("database connect failed", err)
	}
	if err := db.Migrate(startCtx, pool); err != nil {
		cancel()
		pool.Close()
		fatal("migration failed", err)
	}
	cancel()
	defer pool.Close()

	svc := service.New(pool, cfg, ws.NewHub())
	if err := svc.EnsureStorageDirs(); err != nil {
		slog.Warn("storage dirs", "err", err)
	}
	go svc.RunJanitor(ctx, 10*time.Minute)

	if cfg.IsProduction() {
		gin.SetMode(gin.ReleaseMode)
	}
	r := gin.New()
	// nginx terminates TLS in front of us; trust only loopback/docker-bridge proxies.
	_ = r.SetTrustedProxies([]string{"127.0.0.1", "::1", "172.16.0.0/12"})
	r.MaxMultipartMemory = 8 << 20
	uploadLimit := cfg.MediaMaxBytes*4 + (1 << 20)
	r.Use(
		middleware.RequestID(),
		middleware.Recovery(),
		middleware.Logger(),
		middleware.SecurityHeaders(),
		middleware.CORS(cfg.CORSOrigins),
		func(c *gin.Context) {
			limit := int64(jsonBodyLimit)
			if strings.HasPrefix(c.GetHeader("Content-Type"), "multipart/form-data") {
				limit = uploadLimit
			}
			middleware.BodyLimit(limit)(c)
		},
	)
	r.NoRoute(func(c *gin.Context) { c.JSON(http.StatusNotFound, gin.H{"detail": "not found"}) })
	(&handler.API{Svc: svc}).Mount(r)

	srv := &http.Server{
		Addr:              cfg.Addr,
		Handler:           r,
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       60 * time.Second,
		// WriteTimeout stays 0: websockets are long-lived and use per-frame deadlines.
		IdleTimeout:    120 * time.Second,
		MaxHeaderBytes: 1 << 20,
	}

	errCh := make(chan error, 1)
	go func() {
		slog.Info("RideX API listening", "addr", cfg.Addr, "env", cfg.Env)
		errCh <- srv.ListenAndServe()
	}()

	select {
	case err := <-errCh:
		if err != nil && !errors.Is(err, http.ErrServerClosed) {
			fatal("server failed", err)
		}
	case <-ctx.Done():
		slog.Info("shutting down")
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		defer cancel()
		if err := srv.Shutdown(shutdownCtx); err != nil {
			slog.Error("graceful shutdown failed", "err", err)
		}
	}
}

func setupLogging(cfg config.Config) {
	var h slog.Handler
	if cfg.IsProduction() {
		h = slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo})
	} else {
		h = slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelDebug})
	}
	slog.SetDefault(slog.New(h))
}

func fatal(msg string, err error) {
	slog.Error(msg, "err", err)
	os.Exit(1)
}
