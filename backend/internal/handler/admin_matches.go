package handler

import (
	"errors"
	"log/slog"
	"net/http"

	"github.com/gin-gonic/gin"

	"wordchain/backend/internal/service"
)

// AdminMatchesHandler serves the panel's matches pages (read-only, any admin role).
type AdminMatchesHandler struct {
	svc *service.AdminMatchService
}

func NewAdminMatchesHandler(svc *service.AdminMatchService) *AdminMatchesHandler {
	return &AdminMatchesHandler{svc: svc}
}

// List handles GET /api/v1/admin/matches?q=&kind=&status=&from=&to=&page=&page_size=.
func (h *AdminMatchesHandler) List(c *gin.Context) {
	q := service.MatchListQuery{
		Q: c.Query("q"), Kind: c.Query("kind"), Status: c.Query("status"),
		From: c.Query("from"), To: c.Query("to"),
	}
	var ok bool
	if q.Page, ok = intQuery(c, "page"); !ok {
		return
	}
	if q.PageSize, ok = intQuery(c, "page_size"); !ok {
		return
	}
	out, err := h.svc.List(c.Request.Context(), q)
	if err != nil {
		h.fail(c, "list", "", err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": out})
}

// Get handles GET /api/v1/admin/matches/:id.
func (h *AdminMatchesHandler) Get(c *gin.Context) {
	out, err := h.svc.Detail(c.Request.Context(), c.Param("id"))
	if err != nil {
		h.fail(c, "detail", c.Param("id"), err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": out})
}

func (h *AdminMatchesHandler) fail(c *gin.Context, op, id string, err error) {
	switch {
	case errors.Is(err, service.ErrAdminMatchNotFound):
		adminError(c, http.StatusNotFound, "match_not_found", "no such match")
	case errors.Is(err, service.ErrInvalidMatchFilter):
		adminError(c, http.StatusBadRequest, "validation_error", "unknown kind or status, or a bad date range")
	default:
		slog.Error("admin matches request failed", "op", op, "matchID", id, "error", err)
		adminError(c, http.StatusInternalServerError, "internal_error", "could not complete the request")
	}
}
