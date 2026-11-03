package handler

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/lakhansoni126/ridex/backend/internal/config"
	"github.com/lakhansoni126/ridex/backend/internal/service"
	"github.com/lakhansoni126/ridex/backend/internal/ws"
)

// Gin panics at registration on conflicting wildcard routes, which the
// compiler can't catch. Mounting the full router here fails fast in CI.
func TestMountRoutesAndAuthGate(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	svc := service.New(nil, config.Config{JWTSecret: "test-secret-test-secret-test-secret"}, ws.NewHub())
	(&API{Svc: svc}).Mount(r)

	cases := []struct {
		method, path string
		want         int
	}{
		{"GET", "/health", http.StatusOK},
		{"GET", "/api/v1/users/me", http.StatusUnauthorized},
		{"POST", "/api/v1/rides/join", http.StatusUnauthorized},
		{"DELETE", "/api/v1/friends/requests/abc", http.StatusUnauthorized},
		{"GET", "/api/v1/media/../../etc/passwd", http.StatusUnauthorized},
	}
	for _, c := range cases {
		w := httptest.NewRecorder()
		r.ServeHTTP(w, httptest.NewRequest(c.method, c.path, nil))
		if w.Code != c.want {
			t.Errorf("%s %s = %d, want %d", c.method, c.path, w.Code, c.want)
		}
	}
}
