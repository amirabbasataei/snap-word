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

// ChallengeHandler exposes the friend challenge endpoints.
type ChallengeHandler struct {
	svc *service.ChallengeService
}

func NewChallengeHandler(svc *service.ChallengeService) *ChallengeHandler {
	return &ChallengeHandler{svc: svc}
}

type createChallengeBody struct {
	ChallengedID string `json:"challenged_id" binding:"required"`
	Mode         string `json:"mode"          binding:"required"`
}

type respondChallengeBody struct {
	Action string `json:"action" binding:"required"`
}

type challengeResponse struct {
	ID           string    `json:"id"`
	ChallengerID string    `json:"challenger_id"`
	ChallengedID string    `json:"challenged_id"`
	Mode         string    `json:"mode"`
	Status       string    `json:"status"`
	RoomID       *string   `json:"room_id,omitempty"`
	CreatedAt    time.Time `json:"created_at"`
	ExpiresAt    time.Time `json:"expires_at"`
}

// Create handles POST /api/v1/challenges.
func (h *ChallengeHandler) Create(c *gin.Context) {
	challengerID := c.GetString(middleware.ContextKeyUserID)

	var req createChallengeBody
	if err := c.ShouldBindJSON(&req); err != nil {
		respondError(c, http.StatusBadRequest, "invalid_body", err.Error())
		return
	}
	if req.Mode != "classic" && req.Mode != "time_attack" {
		respondError(c, http.StatusBadRequest, "invalid_mode", "mode must be classic or time_attack")
		return
	}

	ch, err := h.svc.CreateChallenge(c.Request.Context(), challengerID, req.ChallengedID, req.Mode)
	if err != nil {
		switch {
		case errors.Is(err, service.ErrNotFriends):
			respondError(c, http.StatusForbidden, "not_friends", "you must be friends to challenge this player")
		default:
			slog.Error("CreateChallenge failed", "challengerID", challengerID, "error", err)
			respondError(c, http.StatusInternalServerError, "internal_error", "failed to create challenge")
		}
		return
	}

	c.JSON(http.StatusCreated, gin.H{"data": toChallResp(ch)})
}

// Respond handles POST /api/v1/challenges/:id/respond.
func (h *ChallengeHandler) Respond(c *gin.Context) {
	responderID := c.GetString(middleware.ContextKeyUserID)
	challengeID := c.Param("id")

	var req respondChallengeBody
	if err := c.ShouldBindJSON(&req); err != nil {
		respondError(c, http.StatusBadRequest, "invalid_body", err.Error())
		return
	}
	if req.Action != "accept" && req.Action != "decline" {
		respondError(c, http.StatusBadRequest, "invalid_action", "action must be accept or decline")
		return
	}

	roomID, err := h.svc.RespondToChallenge(c.Request.Context(), challengeID, responderID, req.Action)
	if err != nil {
		switch {
		case errors.Is(err, service.ErrChallengeNotFound):
			respondError(c, http.StatusNotFound, "challenge_not_found", "challenge not found")
		case errors.Is(err, service.ErrNotChallenged):
			respondError(c, http.StatusForbidden, "not_challenged", "you are not the challenged player")
		case errors.Is(err, service.ErrChallengeExpired):
			respondError(c, http.StatusConflict, "challenge_expired", "challenge is no longer pending")
		default:
			slog.Error("RespondToChallenge failed", "challengeID", challengeID, "error", err)
			respondError(c, http.StatusInternalServerError, "internal_error", "failed to respond to challenge")
		}
		return
	}

	resp := gin.H{"action": req.Action}
	if roomID != "" {
		resp["room_id"] = roomID
	}
	c.JSON(http.StatusOK, gin.H{"data": resp})
}

// GetPending handles GET /api/v1/challenges/pending.
func (h *ChallengeHandler) GetPending(c *gin.Context) {
	userID := c.GetString(middleware.ContextKeyUserID)

	challenges, err := h.svc.GetPendingChallenges(c.Request.Context(), userID)
	if err != nil {
		slog.Error("GetPendingChallenges failed", "userID", userID, "error", err)
		respondError(c, http.StatusInternalServerError, "internal_error", "failed to fetch pending challenges")
		return
	}

	resp := make([]challengeResponse, 0, len(challenges))
	for _, ch := range challenges {
		resp = append(resp, toChallResp(ch))
	}
	c.JSON(http.StatusOK, gin.H{"data": resp})
}

func toChallResp(ch *repository.FriendChallenge) challengeResponse {
	return challengeResponse{
		ID:           ch.ID,
		ChallengerID: ch.ChallengerID,
		ChallengedID: ch.ChallengedID,
		Mode:         ch.Mode,
		Status:       ch.Status,
		RoomID:       ch.RoomID,
		CreatedAt:    ch.CreatedAt,
		ExpiresAt:    ch.ExpiresAt,
	}
}
