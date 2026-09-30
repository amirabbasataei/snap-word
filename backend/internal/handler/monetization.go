package handler

import (
	"log/slog"
	"net/http"

	"github.com/gin-gonic/gin"

	"wordchain/backend/internal/middleware"
	"wordchain/backend/internal/service"
)

// MonetizationHandler exposes coin-earning endpoints.
type MonetizationHandler struct {
	svc *service.MonetizationService
}

func NewMonetizationHandler(svc *service.MonetizationService) *MonetizationHandler {
	return &MonetizationHandler{svc: svc}
}

// RewardedAd handles POST /api/v1/rewarded-ad/claim: credits config.CoinRewardedAd
// after the client reports a completed rewarded ad.
// TODO: the ad completion is client-reported (mock ad SDK); before shipping,
// verify it server-side (AdMob SSV) and cap claims per day.
func (h *MonetizationHandler) RewardedAd(c *gin.Context) {
	userID := c.GetString(middleware.ContextKeyUserID)

	awarded, coins, err := h.svc.ClaimRewardedAd(c.Request.Context(), userID)
	if err != nil {
		slog.Error("RewardedAd failed", "userID", userID, "error", err)
		respondError(c, http.StatusInternalServerError, "internal_error", "failed to award coins")
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": gin.H{"coins_awarded": awarded, "coins": coins}})
}
