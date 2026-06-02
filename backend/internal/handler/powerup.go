package handler

import (
	"errors"
	"log/slog"
	"net/http"

	"github.com/gin-gonic/gin"

	"wordchain/backend/internal/middleware"
	"wordchain/backend/internal/service"
)

// PowerupHandler exposes the powerup inventory and usage endpoints.
type PowerupHandler struct {
	powerupSvc *service.PowerupService
}

func NewPowerupHandler(powerupSvc *service.PowerupService) *PowerupHandler {
	return &PowerupHandler{powerupSvc: powerupSvc}
}

type usePowerupRequest struct {
	PowerupType string `json:"powerup_type" binding:"required"`
}

// GetInventory handles GET /api/v1/powerup/inventory.
func (h *PowerupHandler) GetInventory(c *gin.Context) {
	userID := c.GetString(middleware.ContextKeyUserID)

	items, err := h.powerupSvc.GetInventory(c.Request.Context(), userID)
	if err != nil {
		slog.Error("GetInventory failed", "userID", userID, "error", err)
		respondError(c, http.StatusInternalServerError, "internal_error", "failed to retrieve inventory")
		return
	}

	type itemResp struct {
		PowerupType string `json:"powerup_type"`
		Quantity    int    `json:"quantity"`
	}
	resp := make([]itemResp, 0, len(items))
	for _, item := range items {
		resp = append(resp, itemResp{PowerupType: item.PowerupType, Quantity: item.Quantity})
	}

	c.JSON(http.StatusOK, gin.H{"data": gin.H{"items": resp}})
}

// Use handles POST /api/v1/powerup/use.
func (h *PowerupHandler) Use(c *gin.Context) {
	userID := c.GetString(middleware.ContextKeyUserID)

	var req usePowerupRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		respondError(c, http.StatusBadRequest, "validation_error", err.Error())
		return
	}

	slog.Info("powerup use", "userID", userID, "type", req.PowerupType)

	remaining, err := h.powerupSvc.UseItem(c.Request.Context(), userID, req.PowerupType)
	if err != nil {
		switch {
		case errors.Is(err, service.ErrInvalidPowerupType):
			respondError(c, http.StatusBadRequest, "invalid_powerup_type", "unknown powerup type")
		case errors.Is(err, service.ErrInsufficientPowerup):
			respondError(c, http.StatusConflict, "insufficient_powerup", "no charges remaining for this powerup")
		default:
			slog.Error("UseItem failed", "userID", userID, "type", req.PowerupType, "error", err)
			respondError(c, http.StatusInternalServerError, "internal_error", "failed to use powerup")
		}
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": gin.H{
		"powerup_type":       req.PowerupType,
		"quantity_remaining": remaining,
	}})
}
