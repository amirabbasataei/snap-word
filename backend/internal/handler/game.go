package handler

import (
	"errors"
	"log/slog"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"

	"wordchain/backend/internal/middleware"
	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/service"
)

// GameHandler exposes the game REST endpoints.
type GameHandler struct {
	gameSvc *service.GameService
}

func NewGameHandler(gameSvc *service.GameService) *GameHandler {
	return &GameHandler{gameSvc: gameSvc}
}

type createSoloRequest struct {
	Mode      string    `json:"mode"       binding:"required"`
	Score     int       `json:"score"      binding:"min=0"`
	WordChain []string  `json:"word_chain" binding:"required"`
	StartedAt time.Time `json:"started_at" binding:"required"`
	EndedAt   time.Time `json:"ended_at"   binding:"required"`
}

type matchResponse struct {
	ID        string               `json:"id"`
	Mode      string               `json:"mode"`
	Status    string               `json:"status"`
	GameState interface{}          `json:"game_state,omitempty"`
	StartedAt *time.Time           `json:"started_at,omitempty"`
	EndedAt   *time.Time           `json:"ended_at,omitempty"`
	CreatedAt time.Time            `json:"created_at"`
	Players   []*playerResponse    `json:"players,omitempty"`
}

type playerResponse struct {
	UserID       string    `json:"user_id"`
	Score        int       `json:"score"`
	IsAI         bool      `json:"is_ai"`
	ContinueUsed bool      `json:"continue_used"`
	JoinedAt     time.Time `json:"joined_at"`
}

type statsResponse struct {
	TotalMatches       int        `json:"total_matches"`
	Wins               int        `json:"wins"`
	LongestWord        *string    `json:"longest_word"`
	BestMatchStreak    int        `json:"best_match_streak"`
	DailyStreak        int        `json:"daily_streak"`
	LongestDailyStreak int        `json:"longest_daily_streak"`
	LastPlayedDate     *time.Time `json:"last_played_date,omitempty"`
}

// CreateSolo handles POST /api/v1/game/solo.
// Returns 201 on success, 409 if the match already exists (idempotent sync upload).
func (h *GameHandler) CreateSolo(c *gin.Context) {
	userID := c.GetString(middleware.ContextKeyUserID)

	var req createSoloRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		respondError(c, http.StatusBadRequest, "validation_error", err.Error())
		return
	}

	slog.Info("game/solo upload", "userID", userID, "mode", req.Mode, "score", req.Score)

	in := service.SoloGameInput{
		Mode:      req.Mode,
		Score:     req.Score,
		WordChain: req.WordChain,
		StartedAt: req.StartedAt,
		EndedAt:   req.EndedAt,
	}

	match, alreadyExisted, err := h.gameSvc.CreateSoloGame(c.Request.Context(), userID, in)
	if err != nil {
		slog.Error("CreateSolo failed", "userID", userID, "error", err)
		respondError(c, http.StatusInternalServerError, "internal_error", "failed to create game")
		return
	}

	resp := toMatchResponse(match, nil)
	if alreadyExisted {
		c.JSON(http.StatusConflict, gin.H{"data": resp})
		return
	}
	c.JSON(http.StatusCreated, gin.H{"data": resp})
}

// GetGame handles GET /api/v1/game/:id.
func (h *GameHandler) GetGame(c *gin.Context) {
	userID := c.GetString(middleware.ContextKeyUserID)
	matchID := c.Param("id")

	result, err := h.gameSvc.GetGameState(c.Request.Context(), matchID, userID)
	if err != nil {
		switch {
		case errors.Is(err, service.ErrMatchNotFound):
			respondError(c, http.StatusNotFound, "match_not_found", "match not found")
		case errors.Is(err, service.ErrMatchForbidden):
			respondError(c, http.StatusForbidden, "forbidden", "you are not a player in this match")
		default:
			slog.Error("GetGame failed", "matchID", matchID, "error", err)
			respondError(c, http.StatusInternalServerError, "internal_error", "failed to retrieve game")
		}
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": toMatchResponse(result.Match, result.Players)})
}

// GetStats handles GET /api/v1/profile/stats.
func (h *GameHandler) GetStats(c *gin.Context) {
	userID := c.GetString(middleware.ContextKeyUserID)

	stats, err := h.gameSvc.GetStats(c.Request.Context(), userID)
	if err != nil {
		slog.Error("GetStats failed", "userID", userID, "error", err)
		respondError(c, http.StatusInternalServerError, "internal_error", "failed to retrieve stats")
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": toStatsResponse(stats)})
}

func toMatchResponse(m *repository.Match, players []*repository.MatchPlayer) matchResponse {
	resp := matchResponse{
		ID:        m.ID,
		Mode:      m.Mode,
		Status:    m.Status,
		GameState: m.GameState,
		StartedAt: m.StartedAt,
		EndedAt:   m.EndedAt,
		CreatedAt: m.CreatedAt,
	}
	for _, p := range players {
		resp.Players = append(resp.Players, &playerResponse{
			UserID:       p.UserID,
			Score:        p.Score,
			IsAI:         p.IsAI,
			ContinueUsed: p.ContinueUsed,
			JoinedAt:     p.JoinedAt,
		})
	}
	return resp
}

func toStatsResponse(s *repository.PlayerStats) statsResponse {
	return statsResponse{
		TotalMatches:       s.TotalMatches,
		Wins:               s.Wins,
		LongestWord:        s.LongestWord,
		BestMatchStreak:    s.BestMatchStreak,
		DailyStreak:        s.DailyStreak,
		LongestDailyStreak: s.LongestDailyStreak,
		LastPlayedDate:     s.LastPlayedDate,
	}
}
