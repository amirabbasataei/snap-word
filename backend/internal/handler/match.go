package handler

import (
	"context"
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"

	"wordchain/backend/internal/middleware"
	"wordchain/backend/internal/service"
)

// MatchHandler exposes the matchmaking queue endpoints.
type MatchHandler struct {
	svc *service.MatchmakingService
}

func NewMatchHandler(svc *service.MatchmakingService) *MatchHandler {
	return &MatchHandler{svc: svc}
}

type joinQueueRequest struct {
	Mode       string `json:"mode"       binding:"required"`
	Difficulty string `json:"difficulty"`
}

// JoinQueue handles POST /api/v1/match/queue.
//
// Long-polls until the player is matched with a human opponent or, after
// AIFallbackWaitSec seconds, an AI opponent. Returns the roomID to connect to
// via GET /api/v1/ws/game/:roomID.
func (h *MatchHandler) JoinQueue(c *gin.Context) {
	userID := c.GetString(middleware.ContextKeyUserID)

	var req joinQueueRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		respondError(c, http.StatusBadRequest, "invalid_body", err.Error())
		return
	}
	if req.Mode != "classic" && req.Mode != "time_attack" {
		respondError(c, http.StatusBadRequest, "invalid_mode", "mode must be classic or time_attack")
		return
	}
	if req.Difficulty == "" {
		req.Difficulty = "easy"
	}
	if !service.ValidateDifficulty(req.Difficulty) {
		respondError(c, http.StatusBadRequest, "invalid_difficulty", "difficulty must be easy, medium, or hard")
		return
	}

	roomID, isAI, err := h.svc.Join(c.Request.Context(), userID, req.Mode, req.Difficulty)
	if err != nil {
		switch {
		case errors.Is(err, context.Canceled), err.Error() == "cancelled":
			c.JSON(http.StatusNoContent, nil)
		default:
			respondError(c, http.StatusGatewayTimeout, "no_match", "could not find an opponent")
		}
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": gin.H{
		"room_id": roomID,
		"is_ai":   isAI,
		"mode":    req.Mode,
	}})
}

// CancelQueue handles DELETE /api/v1/match/queue.
// Query param: mode (default "classic").
func (h *MatchHandler) CancelQueue(c *gin.Context) {
	userID := c.GetString(middleware.ContextKeyUserID)
	mode := c.DefaultQuery("mode", "classic")

	_ = h.svc.Cancel(c.Request.Context(), userID, mode)
	c.JSON(http.StatusOK, gin.H{"data": gin.H{"cancelled": true}})
}
