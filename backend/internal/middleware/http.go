package middleware

import (
	"log/slog"
	"net/http"
	"regexp"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/lakhansoni126/ridex/backend/internal/httpx"
)

var requestIDPattern = regexp.MustCompile(`^[A-Za-z0-9._-]{1,64}$`)

// RequestID propagates a sane incoming X-Request-ID or generates one.
func RequestID() gin.HandlerFunc {
	return func(c *gin.Context) {
		id := c.GetHeader("X-Request-ID")
		if !requestIDPattern.MatchString(id) {
			id = uuid.NewString()
		}
		c.Set(httpx.RequestIDKey, id)
		c.Header("X-Request-ID", id)
		c.Next()
	}
}

// Logger emits one structured log line per request.
func Logger() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		c.Next()
		status := c.Writer.Status()
		level := slog.LevelInfo
		if status >= 500 {
			level = slog.LevelError
		} else if status >= 400 {
			level = slog.LevelWarn
		}
		route := c.FullPath()
		if route == "" {
			route = "unmatched"
		}
		slog.Log(c.Request.Context(), level, "request",
			"request_id", c.GetString(httpx.RequestIDKey),
			"method", c.Request.Method,
			"route", route,
			"status", status,
			"duration_ms", time.Since(start).Milliseconds(),
			"ip", c.ClientIP(),
		)
	}
}

// Recovery turns panics into logged 500s.
func Recovery() gin.HandlerFunc {
	return gin.CustomRecovery(func(c *gin.Context, err any) {
		slog.Error("panic", "request_id", c.GetString(httpx.RequestIDKey), "err", err)
		c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{"detail": "internal error"})
	})
}

// SecurityHeaders sets conservative defaults for an API.
func SecurityHeaders() gin.HandlerFunc {
	return func(c *gin.Context) {
		h := c.Writer.Header()
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("X-Frame-Options", "DENY")
		h.Set("Referrer-Policy", "no-referrer")
		h.Set("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'")
		c.Next()
	}
}

// BodyLimit caps request bodies at n bytes.
func BodyLimit(n int64) gin.HandlerFunc {
	return func(c *gin.Context) {
		if c.Request.Body != nil {
			c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, n)
		}
		c.Next()
	}
}

// CORS allows the configured origins ("*" = any).
func CORS(origins []string) gin.HandlerFunc {
	allowAll := len(origins) == 0 || (len(origins) == 1 && origins[0] == "*")
	allowed := map[string]bool{}
	for _, o := range origins {
		allowed[o] = true
	}
	return func(c *gin.Context) {
		o := c.GetHeader("Origin")
		if allowAll {
			c.Header("Access-Control-Allow-Origin", "*")
		} else if o != "" && allowed[o] {
			c.Header("Access-Control-Allow-Origin", o)
			c.Header("Vary", "Origin")
		}
		c.Header("Access-Control-Allow-Headers", "Authorization, Content-Type, X-Request-ID")
		c.Header("Access-Control-Allow-Methods", "GET,POST,PATCH,DELETE,OPTIONS")
		if c.Request.Method == http.MethodOptions {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		c.Next()
	}
}
