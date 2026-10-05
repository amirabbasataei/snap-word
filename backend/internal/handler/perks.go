package handler

import (
	"errors"
	"log/slog"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"

	"wordchain/backend/internal/middleware"
	"wordchain/backend/internal/service"
)

// PerksHandler exposes premium status and avatar selection.
type PerksHandler struct {
	svc *service.PerksService
}

func NewPerksHandler(svc *service.PerksService) *PerksHandler {
	return &PerksHandler{svc: svc}
}

type perksResponse struct {
	IsPremium    bool       `json:"is_premium"`
	PremiumUntil *time.Time `json:"premium_until"`
	AvatarID     string     `json:"avatar_id"`
}

// Get handles GET /api/v1/profile/perks.
func (h *PerksHandler) Get(c *gin.Context) {
	userID := c.GetString(middleware.ContextKeyUserID)
	st, err := h.svc.Status(c.Request.Context(), userID)
	if err != nil {
		slog.Error("GetPerks failed", "userID", userID, "error", err)
		respondError(c, http.StatusInternalServerError, "internal_error", "failed to load perks")
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": perksResponse{
		IsPremium: st.IsPremium, PremiumUntil: st.PremiumUntil, AvatarID: st.AvatarID,
	}})
}

type setAvatarRequest struct {
	AvatarID string `json:"avatar_id" binding:"required"`
}

// SetAvatar handles PATCH /api/v1/profile/avatar (premium only).
func (h *PerksHandler) SetAvatar(c *gin.Context) {
	userID := c.GetString(middleware.ContextKeyUserID)

	var req setAvatarRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		respondError(c, http.StatusBadRequest, "validation_error", err.Error())
		return
	}
	switch err := h.svc.SetAvatar(c.Request.Context(), userID, req.AvatarID); {
	case err == nil:
		c.JSON(http.StatusOK, gin.H{"data": gin.H{"avatar_id": req.AvatarID}})
	case errors.Is(err, service.ErrInvalidAvatar):
		respondError(c, http.StatusBadRequest, "invalid_avatar", "unknown avatar")
	case errors.Is(err, service.ErrNotPremium):
		respondError(c, http.StatusForbidden, "premium_required", "premium subscription required")
	default:
		slog.Error("SetAvatar failed", "userID", userID, "error", err)
		respondError(c, http.StatusInternalServerError, "internal_error", "failed to set avatar")
	}
}
