package handler

import (
	"errors"
	"log/slog"
	"net/http"

	"github.com/gin-gonic/gin"

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
	ChallengeDate string                `json:"challenge_date"`
	DayNumber     int                   `json:"day_number"`
	StartLetter   string                `json:"start_letter"`
	TodayBest     int                   `json:"today_best"`
	YourBest      int                   `json:"your_best"`
	DailyStreak   int                   `json:"daily_streak"`
	Attempt       *dailyAttemptResponse `json:"attempt"`
	RetryAttempt  *dailyAttemptResponse `json:"retry_attempt"`
	Rank          *int                  `json:"rank"`
}

// GetDaily handles GET /api/v1/daily.
func (h *DailyHandler) GetDaily(c *gin.Context) {
	userID := c.GetString(middleware.ContextKeyUserID)

	info, err := h.svc.GetDailyInfo(c.Request.Context(), userID)
	if errors.Is(err, service.ErrNoDailyChallenge) {
		respondError(c, http.StatusNotFound, "no_daily_challenge", "today's challenge has not been set up yet")
		return
	}
	if err != nil {
		slog.Error("GetDailyInfo failed", "userID", userID, "error", err)
		respondError(c, http.StatusInternalServerError, "internal_error", "failed to load daily challenge")
		return
	}

	resp := dailyChallengeResponse{
		ChallengeDate: info.ChallengeDate,
		DayNumber:     info.DayNumber,
		StartLetter:   info.StartLetter,
		TodayBest:     info.TodayBest,
		YourBest:      info.YourBest,
		DailyStreak:   info.DailyStreak,
		Rank:          info.Rank,
	}
	if info.Attempt != nil {
		resp.Attempt = toAttemptResp(info.Attempt)
	}
	if info.RetryAttempt != nil {
		resp.RetryAttempt = toAttemptResp(info.RetryAttempt)
	}

	c.JSON(http.StatusOK, gin.H{"data": resp})
}

// Retry handles POST /api/v1/daily/retry.
func (h *DailyHandler) Retry(c *gin.Context) {
	userID := c.GetString(middleware.ContextKeyUserID)

	err := h.svc.Retry(c.Request.Context(), userID)
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
