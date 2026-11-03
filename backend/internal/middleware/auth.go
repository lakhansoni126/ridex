package middleware

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/lakhansoni126/ridex/backend/internal/service"
)

const UserIDKey = "userID"

// Auth requires a valid access token belonging to an active (not deleted) user.
func Auth(svc *service.Svc) gin.HandlerFunc {
	return func(c *gin.Context) {
		h := c.GetHeader("Authorization")
		if !strings.HasPrefix(h, "Bearer ") {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"detail": "missing token"})
			return
		}
		uid, err := svc.AuthenticateAccess(c.Request.Context(), strings.TrimPrefix(h, "Bearer "))
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"detail": "invalid token"})
			return
		}
		c.Set(UserIDKey, uid)
		c.Next()
	}
}

func UserID(c *gin.Context) uuid.UUID {
	return c.MustGet(UserIDKey).(uuid.UUID)
}
