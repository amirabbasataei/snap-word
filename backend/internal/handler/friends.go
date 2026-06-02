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

// FriendHandler exposes the friend management endpoints.
type FriendHandler struct {
	svc *service.FriendService
}

func NewFriendHandler(svc *service.FriendService) *FriendHandler {
	return &FriendHandler{svc: svc}
}

type sendFriendRequestBody struct {
	Username string `json:"username" binding:"required"`
}

type respondFriendRequestBody struct {
	RequesterID string `json:"requester_id" binding:"required"`
	Action      string `json:"action"       binding:"required"`
}

type friendResponse struct {
	UserID    string    `json:"user_id"`
	Username  string    `json:"username"`
	FriendSince time.Time `json:"friend_since"`
}

type pendingRequestResponse struct {
	RequesterID string    `json:"requester_id"`
	Username    string    `json:"username"`
	RequestedAt time.Time `json:"requested_at"`
}

// SendRequest handles POST /api/v1/friends/request.
func (h *FriendHandler) SendRequest(c *gin.Context) {
	requesterID := c.GetString(middleware.ContextKeyUserID)

	var req sendFriendRequestBody
	if err := c.ShouldBindJSON(&req); err != nil {
		respondError(c, http.StatusBadRequest, "invalid_body", err.Error())
		return
	}

	target, err := h.svc.SendFriendRequest(c.Request.Context(), requesterID, req.Username)
	if err != nil {
		switch {
		case errors.Is(err, service.ErrSelfRequest):
			respondError(c, http.StatusBadRequest, "self_request", "cannot send a friend request to yourself")
		case errors.Is(err, service.ErrFriendRequestExists):
			respondError(c, http.StatusConflict, "request_exists", "a friendship or pending request already exists")
		case errors.Is(err, repository.ErrUserNotFound):
			respondError(c, http.StatusNotFound, "user_not_found", "no user with that username")
		default:
			slog.Error("SendFriendRequest failed", "requesterID", requesterID, "error", err)
			respondError(c, http.StatusInternalServerError, "internal_error", "failed to send friend request")
		}
		return
	}

	c.JSON(http.StatusCreated, gin.H{"data": gin.H{
		"user_id":  target.ID,
		"username": target.Username,
	}})
}

// ListFriends handles GET /api/v1/friends.
func (h *FriendHandler) ListFriends(c *gin.Context) {
	userID := c.GetString(middleware.ContextKeyUserID)

	friends, err := h.svc.ListFriends(c.Request.Context(), userID)
	if err != nil {
		slog.Error("ListFriends failed", "userID", userID, "error", err)
		respondError(c, http.StatusInternalServerError, "internal_error", "failed to list friends")
		return
	}

	resp := make([]friendResponse, 0, len(friends))
	for _, f := range friends {
		resp = append(resp, friendResponse{
			UserID:      f.UserID,
			Username:    f.Username,
			FriendSince: f.CreatedAt,
		})
	}
	c.JSON(http.StatusOK, gin.H{"data": resp})
}

// ListRequests handles GET /api/v1/friends/requests.
func (h *FriendHandler) ListRequests(c *gin.Context) {
	userID := c.GetString(middleware.ContextKeyUserID)

	reqs, err := h.svc.ListPendingRequests(c.Request.Context(), userID)
	if err != nil {
		slog.Error("ListPendingRequests failed", "userID", userID, "error", err)
		respondError(c, http.StatusInternalServerError, "internal_error", "failed to list friend requests")
		return
	}

	resp := make([]pendingRequestResponse, 0, len(reqs))
	for _, r := range reqs {
		resp = append(resp, pendingRequestResponse{
			RequesterID: r.RequesterID,
			Username:    r.Username,
			RequestedAt: r.CreatedAt,
		})
	}
	c.JSON(http.StatusOK, gin.H{"data": resp})
}

// RespondToRequest handles POST /api/v1/friends/respond.
func (h *FriendHandler) RespondToRequest(c *gin.Context) {
	addresseeID := c.GetString(middleware.ContextKeyUserID)

	var req respondFriendRequestBody
	if err := c.ShouldBindJSON(&req); err != nil {
		respondError(c, http.StatusBadRequest, "invalid_body", err.Error())
		return
	}
	if req.Action != "accept" && req.Action != "decline" {
		respondError(c, http.StatusBadRequest, "invalid_action", "action must be accept or decline")
		return
	}

	if err := h.svc.RespondToFriendRequest(c.Request.Context(), addresseeID, req.RequesterID, req.Action); err != nil {
		switch {
		case errors.Is(err, service.ErrFriendRequestNotFound):
			respondError(c, http.StatusNotFound, "request_not_found", "no pending friend request from that user")
		default:
			slog.Error("RespondToFriendRequest failed", "addresseeID", addresseeID, "error", err)
			respondError(c, http.StatusInternalServerError, "internal_error", "failed to respond to friend request")
		}
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": gin.H{"action": req.Action}})
}

// RemoveFriend handles DELETE /api/v1/friends/:friendId.
func (h *FriendHandler) RemoveFriend(c *gin.Context) {
	userID := c.GetString(middleware.ContextKeyUserID)
	friendID := c.Param("friendId")

	if err := h.svc.RemoveFriend(c.Request.Context(), userID, friendID); err != nil {
		slog.Error("RemoveFriend failed", "userID", userID, "friendID", friendID, "error", err)
		respondError(c, http.StatusInternalServerError, "internal_error", "failed to remove friend")
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": gin.H{"removed": true}})
}
