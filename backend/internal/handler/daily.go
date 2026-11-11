package handler

import (
	"errors"
	"log/slog"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/middleware"
	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/service"
)

type DailyHandler struct {
	svc *service.DailyService
}

func NewDailyHandler(svc *service.DailyService) *DailyHandler {
	return &DailyHandler{svc: svc}
}

type dailyAttemptResponse struct {
	AttemptNumber int      `json:"attempt_number"`
	Score         int      `json:"score"`
	ChainLength   int      `json:"chain_length"`
	WordChain     []string `json:"word_chain"`
}

type dailyChallengeResponse struct {
	ChallengeDate  string                `json:"challenge_date"`
	DayNumber      int                   `json:"day_number"`
	Variant        int                   `json:"variant"`
	TurnTimerSec   int                   `json:"turn_timer_sec"`
	PlayedVariants []int                 `json:"played_variants"`
	StartLetter    string                `json:"start_letter"`
	TodayBest      int                   `json:"today_best"`
	YourBest       int                   `json:"your_best"`
	DailyStreak    int                   `json:"daily_streak"`
	Attempt        *dailyAttemptResponse `json:"attempt"`
	RetryAttempt   *dailyAttemptResponse `json:"retry_attempt"`
	Rank           *int                  `json:"rank"`
}

// dailyVariantParam reads the Daily variant from the `variant` query
// parameter; missing means the classic one (an app older than the variants).
// It answers 400 invalid_daily_variant and returns false for anything else.
func dailyVariantParam(c *gin.Context) (int, bool) {
	raw := c.Query("variant")
	if raw == "" {
		return config.DailyVariantClassic, true
	}
	v, err := strconv.Atoi(raw)
	if err != nil || !config.IsDailyVariant(v) {
		respondError(c, http.StatusBadRequest, "invalid_daily_variant", "unknown daily challenge variant")
		return 0, false
	}
	return v, true
}

// GetDaily handles GET /api/v1/daily?variant=N (N = the link position, 1–3;
// default 1).
func (h *DailyHandler) GetDaily(c *gin.Context) {
	userID := c.GetString(middleware.ContextKeyUserID)
	variant, ok := dailyVariantParam(c)
	if !ok {
		return
	}

	info, err := h.svc.GetDailyInfo(c.Request.Context(), userID, variant)
	if errors.Is(err, service.ErrNoDailyChallenge) {
		respondError(c, http.StatusNotFound, "no_daily_challenge", "today's challenge has not been set up yet")
		return
	}
	if err != nil {
		slog.Error("GetDailyInfo failed", "userID", userID, "error", err)
		respondError(c, http.StatusInternalServerError, "internal_error", "failed to load daily challenge")
		return
	}

	played := info.PlayedVariants
	if played == nil {
		played = []int{}
	}
	resp := dailyChallengeResponse{
		ChallengeDate:  info.ChallengeDate,
		DayNumber:      info.DayNumber,
		Variant:        info.Variant,
		TurnTimerSec:   info.TurnTimerSec,
		PlayedVariants: played,
		StartLetter:    info.StartLetter,
		TodayBest:      info.TodayBest,
		YourBest:       info.YourBest,
		DailyStreak:    info.DailyStreak,
		Rank:           info.Rank,
	}
	if info.Attempt != nil {
		resp.Attempt = toAttemptResp(info.Attempt)
	}
	if info.RetryAttempt != nil {
		resp.RetryAttempt = toAttemptResp(info.RetryAttempt)
	}

	c.JSON(http.StatusOK, gin.H{"data": resp})
}

// Retry handles POST /api/v1/daily/retry?variant=N (default 1).
func (h *DailyHandler) Retry(c *gin.Context) {
	userID := c.GetString(middleware.ContextKeyUserID)
	variant, ok := dailyVariantParam(c)
	if !ok {
		return
	}

	err := h.svc.Retry(c.Request.Context(), userID, variant)
	switch {
	case errors.Is(err, service.ErrDailyNotAttempted):
		respondError(c, http.StatusBadRequest, "not_attempted", "complete today's challenge before retrying")
	case errors.Is(err, service.ErrDailyAlreadyRetried):
		respondError(c, http.StatusConflict, "already_retried", "daily retry already used")
	case errors.Is(err, repository.ErrInsufficientCoins):
		respondError(c, http.StatusPaymentRequired, "insufficient_coins", "not enough coins to retry")
	case err != nil:
		slog.Error("daily retry failed", "userID", userID, "error", err)
		respondError(c, http.StatusInternalServerError, "internal_error", "could not process retry")
	default:
		c.JSON(http.StatusOK, gin.H{"data": gin.H{"ok": true}})
	}
}

func toAttemptResp(a *service.DailyAttemptInfo) *dailyAttemptResponse {
	wc := a.WordChain
	if wc == nil {
		wc = []string{}
	}
	return &dailyAttemptResponse{
		AttemptNumber: a.AttemptNumber,
		Score:         a.Score,
		ChainLength:   a.ChainLength,
		WordChain:     wc,
	}
}

type dailyBoardEntry struct {
	Rank        int    `json:"rank"`
	UserID      string `json:"user_id"`
	Username    string `json:"username"`
	Score       int    `json:"score"`
	ChainLength int    `json:"chain_length"`
}

// GetLeaderboard handles GET /api/v1/daily/leaderboard?variant=N: today's
// ranking of one variant (default 1).
func (h *DailyHandler) GetLeaderboard(c *gin.Context) {
	userID := c.GetString(middleware.ContextKeyUserID)
	variant, ok := dailyVariantParam(c)
	if !ok {
		return
	}

	board, err := h.svc.Leaderboard(c.Request.Context(), userID, variant, 100)
	if err != nil {
		slog.Error("daily leaderboard failed", "userID", userID, "error", err)
		respondError(c, http.StatusInternalServerError, "internal_error", "failed to load daily leaderboard")
		return
	}

	entries := make([]dailyBoardEntry, 0, len(board.Entries))
	for _, e := range board.Entries {
		entries = append(entries, dailyBoardEntry{
			Rank: e.Rank, UserID: e.UserID, Username: e.Username, Score: e.Score, ChainLength: e.ChainLength,
		})
	}
	c.JSON(http.StatusOK, gin.H{"data": gin.H{
		"challenge_date": board.ChallengeDate,
		"day_number":     board.DayNumber,
		"variant":        board.Variant,
		"entries":        entries,
		"my_rank":        board.MyRank,
	}})
}
