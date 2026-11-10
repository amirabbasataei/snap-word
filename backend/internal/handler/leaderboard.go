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

// Get handles GET /api/v1/leaderboard?type=global&limit=100   (this week's net «جام»)
//
//	and      GET /api/v1/leaderboard?type=friends&limit=100  (friends by rating)
//	and      GET /api/v1/leaderboard?type=alltime&limit=100  (rating, ≥ 10 rated games)
//
// player_rank / player_score / player_games are the caller's own row on that
// board (player_wins on the weekly board only); player_rank is 0 when the
// caller is not on it.
func (h *LeaderboardHandler) Get(c *gin.Context) {
	ctx := c.Request.Context()
	userID := c.GetString(middleware.ContextKeyUserID)
	lbType := c.DefaultQuery("type", "global")
	limit := clampLimit(c.DefaultQuery("limit", "100"))

	var (
		entries []service.LeaderboardEntry
		me      service.PlayerStanding
		err     error
		meErr   error
	)
	switch lbType {
	case "friends":
		entries, me, err = h.svc.GetFriendsLeaderboard(ctx, userID, limit)
	case "alltime":
		entries, err = h.svc.GetAllTimeTop(ctx, limit)
		if err == nil {
			me, meErr = h.svc.AllTimeStanding(ctx, userID)
		}
	default:
		lbType = "global"
		entries, err = h.svc.GetTopN(ctx, limit)
		if err == nil {
			me, meErr = h.svc.WeeklyStanding(ctx, userID)
		}
	}
	if err != nil {
		slog.Error("leaderboard: query failed", "type", lbType, "userID", userID, "error", err)
		respondError(c, http.StatusInternalServerError, "leaderboard_error", "failed to fetch leaderboard")
		return
	}
	if meErr != nil {
		slog.Warn("leaderboard: player standing failed", "type", lbType, "userID", userID, "error", meErr)
	}

	data := gin.H{
		"entries":          entries,
		"player_rank":      me.Rank,
		"player_score":     me.Score,
		"player_games":     me.Games,
		"player_avatar_id": h.svc.GetAvatarID(ctx, userID),
	}
	if lbType == "global" {
		data["player_wins"] = me.Wins
	}
	c.JSON(http.StatusOK, gin.H{"data": data})
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
