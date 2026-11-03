// Package httpx holds HTTP error types and small gin helpers.
package httpx

import (
	"errors"
	"log/slog"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// RequestIDKey is the gin context key for the request id.
const RequestIDKey = "request_id"

// Error is an error with an HTTP status that is safe to show to clients.
type Error struct {
	Code int
	Msg  string
}

func (e *Error) Error() string { return e.Msg }

// E builds a client-facing error.
func E(code int, msg string) error { return &Error{Code: code, Msg: msg} }

func BadRequest(msg string) error { return E(http.StatusBadRequest, msg) }
func NotFound(msg string) error   { return E(http.StatusNotFound, msg) }
func Forbidden(msg string) error  { return E(http.StatusForbidden, msg) }
func Conflict(msg string) error   { return E(http.StatusConflict, msg) }

func OK(c *gin.Context, v any) { c.JSON(http.StatusOK, v) }

func NoContent(c *gin.Context) { c.Status(http.StatusNoContent) }

// Fail writes err. Client errors are returned verbatim; anything else is
// logged with the request id and reported as a generic 500.
func Fail(c *gin.Context, err error) {
	var he *Error
	if errors.As(err, &he) {
		c.AbortWithStatusJSON(he.Code, gin.H{"detail": he.Msg})
		return
	}
	var mbe *http.MaxBytesError
	if errors.As(err, &mbe) {
		c.AbortWithStatusJSON(http.StatusRequestEntityTooLarge, gin.H{"detail": "request too large"})
		return
	}
	slog.Error("internal error",
		"request_id", c.GetString(RequestIDKey),
		"method", c.Request.Method,
		"path", c.FullPath(),
		"err", err)
	c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{"detail": "internal error"})
}

// Bind decodes a JSON body, writing a 400 on failure.
func Bind(c *gin.Context, dst any) bool {
	if err := c.ShouldBindJSON(dst); err != nil {
		var mbe *http.MaxBytesError
		if errors.As(err, &mbe) {
			c.AbortWithStatusJSON(http.StatusRequestEntityTooLarge, gin.H{"detail": "request too large"})
			return false
		}
		c.AbortWithStatusJSON(http.StatusBadRequest, gin.H{"detail": "invalid request body"})
		return false
	}
	return true
}

// ParamUUID parses a path parameter, writing a 404 when it is not a UUID.
func ParamUUID(c *gin.Context, name string) (uuid.UUID, bool) {
	id, err := uuid.Parse(c.Param(name))
	if err != nil {
		c.AbortWithStatusJSON(http.StatusNotFound, gin.H{"detail": "not found"})
		return uuid.Nil, false
	}
	return id, true
}
