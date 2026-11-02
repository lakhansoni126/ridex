package httpx

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"
)

var (
	ErrBadRequest   = errors.New("bad request")
	ErrUnauthorized = errors.New("unauthorized")
	ErrForbidden    = errors.New("forbidden")
	ErrNotFound     = errors.New("not found")
	ErrConflict     = errors.New("conflict")
)

type Error struct {
	Code int
	Msg  string
}

func (e *Error) Error() string { return e.Msg }

func E(code int, msg string) error { return &Error{Code: code, Msg: msg} }

func OK(c *gin.Context, v any) { c.JSON(http.StatusOK, v) }

func Created(c *gin.Context, v any) { c.JSON(http.StatusCreated, v) }

func Fail(c *gin.Context, err error) {
	var he *Error
	if errors.As(err, &he) {
		c.JSON(he.Code, gin.H{"detail": he.Msg})
		return
	}
	switch {
	case errors.Is(err, ErrUnauthorized):
		c.JSON(http.StatusUnauthorized, gin.H{"detail": err.Error()})
	case errors.Is(err, ErrForbidden):
		c.JSON(http.StatusForbidden, gin.H{"detail": err.Error()})
	case errors.Is(err, ErrNotFound):
		c.JSON(http.StatusNotFound, gin.H{"detail": err.Error()})
	case errors.Is(err, ErrConflict):
		c.JSON(http.StatusConflict, gin.H{"detail": err.Error()})
	case errors.Is(err, ErrBadRequest):
		c.JSON(http.StatusBadRequest, gin.H{"detail": err.Error()})
	default:
		c.JSON(http.StatusInternalServerError, gin.H{"detail": "internal error"})
	}
}

func Bind(c *gin.Context, dst any) bool {
	if err := c.ShouldBindJSON(dst); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"detail": err.Error()})
		return false
	}
	return true
}
