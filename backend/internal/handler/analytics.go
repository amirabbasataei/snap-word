package handler

import (
	"errors"
	"log/slog"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/service"
)

type tokenParser interface {
	ParseAccessToken(token string) (userID, username string, err error)
}

// AnalyticsHandler serves the public event-ingest endpoint.
type AnalyticsHandler struct {
	svc  *service.AnalyticsService
	auth tokenParser
}

func NewAnalyticsHandler(svc *service.AnalyticsService, auth tokenParser) *AnalyticsHandler {
	return &AnalyticsHandler{svc: svc, auth: auth}
}

// Ingest handles POST /api/v1/analytics/events. It is public so guests are
// tracked; a valid Bearer token only fills user_id server-side, and a bad or
// expired one is treated as a guest rather than an error (the events still
// matter, and the client refreshes its token separately).
func (h *AnalyticsHandler) Ingest(c *gin.Context) {
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, config.AnalyticsMaxBodyBytes)
	var req service.AnalyticsBatchInput
	if err := c.ShouldBindJSON(&req); err != nil {
		respondError(c, http.StatusBadRequest, "validation_error", "invalid analytics batch")
		return
	}

	ctx := c.Request.Context()
	if err := h.svc.AllowRequest(ctx, req.InstallID, c.ClientIP()); err != nil {
		respondError(c, http.StatusTooManyRequests, "rate_limited", "too many analytics requests")
		return
	}

	userID := ""
	if parts := strings.SplitN(c.GetHeader("Authorization"), " ", 2); len(parts) == 2 && strings.EqualFold(parts[0], "Bearer") {
		if id, _, err := h.auth.ParseAccessToken(parts[1]); err == nil {
			userID = id
		}
	}

	out, err := h.svc.Ingest(ctx, userID, req)
	switch {
	case errors.Is(err, service.ErrAnalyticsInvalid):
		respondError(c, http.StatusBadRequest, "validation_error", "invalid analytics batch")
		return
	case err != nil:
		slog.Error("analytics ingest failed", "error", err)
		respondError(c, http.StatusInternalServerError, "internal_error", "could not store events")
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": out})
}
