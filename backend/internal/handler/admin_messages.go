package handler

import (
	"errors"
	"log/slog"
	"net/http"

	"github.com/gin-gonic/gin"

	"wordchain/backend/internal/service"
)

// AdminMessagesHandler serves the panel's player-messages page (read-only, any admin role).
type AdminMessagesHandler struct {
	svc *service.AdminMessageService
}

func NewAdminMessagesHandler(svc *service.AdminMessageService) *AdminMessagesHandler {
	return &AdminMessagesHandler{svc: svc}
}

// List handles GET /api/v1/admin/messages?q=&kind=&from=&to=&page=&page_size=.
func (h *AdminMessagesHandler) List(c *gin.Context) {
	q := service.MessageListQuery{
		Q: c.Query("q"), Kind: c.Query("kind"), From: c.Query("from"), To: c.Query("to"),
	}
	var ok bool
	if q.Page, ok = intQuery(c, "page"); !ok {
		return
	}
	if q.PageSize, ok = intQuery(c, "page_size"); !ok {
		return
	}
	out, err := h.svc.List(c.Request.Context(), q)
	switch {
	case errors.Is(err, service.ErrInvalidMessageFilter):
		adminError(c, http.StatusBadRequest, "validation_error", "unknown kind, or a bad date range")
	case err != nil:
		slog.Error("admin messages request failed", "error", err)
		adminError(c, http.StatusInternalServerError, "internal_error", "could not complete the request")
	default:
		c.JSON(http.StatusOK, gin.H{"data": out})
	}
}
