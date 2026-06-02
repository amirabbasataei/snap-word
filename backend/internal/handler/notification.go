package handler

import (
	"log/slog"
	"net/http"

	"github.com/gin-gonic/gin"

	"wordchain/backend/internal/middleware"
	"wordchain/backend/internal/repository"
)

// NotificationHandler manages device token registration for push notifications.
type NotificationHandler struct {
	repo *repository.NotificationRepository
}

func NewNotificationHandler(repo *repository.NotificationRepository) *NotificationHandler {
	return &NotificationHandler{repo: repo}
}

type registerTokenReq struct {
	Token    string `json:"token"    binding:"required"`
	Platform string `json:"platform" binding:"required,oneof=ios android"`
}

type deregisterTokenReq struct {
	Token string `json:"token" binding:"required"`
}

// RegisterToken handles POST /api/v1/notifications/token.
func (h *NotificationHandler) RegisterToken(c *gin.Context) {
	userID := c.GetString(middleware.ContextKeyUserID)

	var req registerTokenReq
	if err := c.ShouldBindJSON(&req); err != nil {
		respondError(c, http.StatusBadRequest, "invalid_body", err.Error())
		return
	}

	if err := h.repo.RegisterToken(c.Request.Context(), userID, req.Token, req.Platform); err != nil {
		slog.Error("RegisterToken failed", "userID", userID, "error", err)
		respondError(c, http.StatusInternalServerError, "internal_error", "failed to register token")
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": gin.H{"registered": true}})
}

// DeregisterToken handles DELETE /api/v1/notifications/token.
func (h *NotificationHandler) DeregisterToken(c *gin.Context) {
	userID := c.GetString(middleware.ContextKeyUserID)

	var req deregisterTokenReq
	if err := c.ShouldBindJSON(&req); err != nil {
		respondError(c, http.StatusBadRequest, "invalid_body", err.Error())
		return
	}

	if err := h.repo.DeregisterToken(c.Request.Context(), userID, req.Token); err != nil {
		slog.Error("DeregisterToken failed", "userID", userID, "error", err)
		respondError(c, http.StatusInternalServerError, "internal_error", "failed to deregister token")
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": gin.H{"deregistered": true}})
}
