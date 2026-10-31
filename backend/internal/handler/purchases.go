package handler

import (
	"errors"
	"log/slog"
	"net/http"

	"github.com/gin-gonic/gin"

	"wordchain/backend/internal/middleware"
	"wordchain/backend/internal/service"
)

// PurchaseHandler exposes store-purchase verification.
type PurchaseHandler struct {
	svc *service.PurchaseService
}

func NewPurchaseHandler(svc *service.PurchaseService) *PurchaseHandler {
	return &PurchaseHandler{svc: svc}
}

type verifyPurchaseRequest struct {
	ProductID     string `json:"product_id" binding:"required"`
	PurchaseToken string `json:"purchase_token" binding:"required"`
}

// VerifyBazaar handles POST /api/v1/payments/bazaar/verify.
func (h *PurchaseHandler) VerifyBazaar(c *gin.Context) {
	userID := c.GetString(middleware.ContextKeyUserID)
	var req verifyPurchaseRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		respondError(c, http.StatusBadRequest, "validation_error", err.Error())
		return
	}
	res, err := h.svc.VerifyBazaar(c.Request.Context(), userID, req.ProductID, req.PurchaseToken)
	if err != nil {
		switch {
		case errors.Is(err, service.ErrUnknownProduct):
			respondError(c, http.StatusBadRequest, "unknown_product", "unknown product")
		case errors.Is(err, service.ErrPurchaseInvalid), errors.Is(err, service.ErrSubscriptionExpired):
			respondError(c, http.StatusBadRequest, "purchase_invalid", "purchase not valid")
		case errors.Is(err, service.ErrPurchaseOwnedByOther), errors.Is(err, service.ErrPurchaseWrongRecipient):
			respondError(c, http.StatusConflict, "purchase_already_claimed", "purchase belongs to another account")
		case errors.Is(err, service.ErrPaymentsUnavailable):
			respondError(c, http.StatusServiceUnavailable, "payments_unavailable", "payments are not available")
		case errors.Is(err, service.ErrStoreUnavailable):
			respondError(c, http.StatusBadGateway, "store_unavailable", "store verification failed, retry")
		default:
			slog.Error("VerifyBazaar failed", "userID", userID, "product", req.ProductID, "error", err)
			respondError(c, http.StatusInternalServerError, "internal_error", "failed to verify purchase")
		}
		return
	}
	data := gin.H{
		"product_id":        res.ProductID,
		"kind":              res.Kind,
		"coins_awarded":     res.CoinsAwarded,
		"already_processed": res.AlreadyProcessed,
	}
	if res.Kind == "coins" {
		data["coins"] = res.Coins
	}
	if res.PremiumUntil != nil {
		data["premium_until"] = res.PremiumUntil.UTC()
	}
	c.JSON(http.StatusOK, gin.H{"data": data})
}
