package handler

import (
	"log/slog"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"

	"wordchain/backend/internal/middleware"
	"wordchain/backend/internal/service"
)

// InboxHandler serves the signed-in player's admin in-app messages.
type InboxHandler struct {
	svc *service.InboxService
}

func NewInboxHandler(svc *service.InboxService) *InboxHandler { return &InboxHandler{svc: svc} }

type inboxMessageResp struct {
	ID        string    `json:"id"`
	Title     string    `json:"title"`
	Body      string    `json:"body"`
	Route     string    `json:"route"`
	CreatedAt time.Time `json:"created_at"`
}

// List handles GET /api/v1/inbox — unread admin messages, newest first.
func (h *InboxHandler) List(c *gin.Context) {
	userID := c.GetString(middleware.ContextKeyUserID)
	msgs, err := h.svc.Unread(c.Request.Context(), userID)
	if err != nil {
		slog.Error("inbox list failed", "userID", userID, "error", err)
		respondError(c, http.StatusInternalServerError, "internal_error", "could not load messages")
		return
	}
	out := make([]inboxMessageResp, len(msgs))
	for i, m := range msgs {
		out[i] = inboxMessageResp{ID: m.ID, Title: m.Title, Body: m.Body, Route: m.Route, CreatedAt: m.CreatedAt}
	}
	c.JSON(http.StatusOK, gin.H{"data": gin.H{"messages": out}})
}

// MarkRead handles POST /api/v1/inbox/:id/read.
func (h *InboxHandler) MarkRead(c *gin.Context) {
	userID := c.GetString(middleware.ContextKeyUserID)
	if err := h.svc.MarkRead(c.Request.Context(), userID, c.Param("id")); err != nil {
		slog.Error("inbox mark read failed", "userID", userID, "error", err)
		respondError(c, http.StatusInternalServerError, "internal_error", "could not update the message")
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": gin.H{"read": true}})
}
