package handler

import (
	"log/slog"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"wordchain/backend/internal/middleware"
	"wordchain/backend/internal/service"
)

// LeaderboardHandler exposes leaderboard query endpoints.
type LeaderboardHandler struct {
	svc *service.LeaderboardService
}

func NewLeaderboardHandler(svc *service.LeaderboardService) *LeaderboardHandler {
	return &LeaderboardHandler{svc: svc}
}

// Get handles GET /api/v1/leaderboard?type=global&limit=100
//
//	and      GET /api/v1/leaderboard?type=friends&limit=100
func (h *LeaderboardHandler) Get(c *gin.Context) {
	userID := c.GetString(middleware.ContextKeyUserID)
	lbType := c.DefaultQuery("type", "global")
	limit := clampLimit(c.DefaultQuery("limit", "100"))

	var (
		entries []service.LeaderboardEntry
		err     error
	)

	switch lbType {
	case "friends":
		entries, err = h.svc.GetFriendsLeaderboard(c.Request.Context(), userID, limit)
	default:
		entries, err = h.svc.GetTopN(c.Request.Context(), limit)
	}
	if err != nil {
		slog.Error("leaderboard: query failed", "type", lbType, "userID", userID, "error", err)
		respondError(c, http.StatusInternalServerError, "leaderboard_error", "failed to fetch leaderboard")
		return
	}

	rank, score, err := h.svc.GetPlayerRank(c.Request.Context(), userID)
	if err != nil {
		slog.Warn("leaderboard: GetPlayerRank failed", "userID", userID, "error", err)
	}

	c.JSON(http.StatusOK, gin.H{
		"data": gin.H{
			"entries":      entries,
			"player_rank":  rank,
			"player_score": score,
		},
	})
}

func clampLimit(s string) int {
	n, err := strconv.Atoi(s)
	if err != nil || n <= 0 {
		return 100
	}
	if n > 100 {
		return 100
	}
	return n
}
