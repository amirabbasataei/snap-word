package handler

import (
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"wordchain/backend/internal/middleware"
	"wordchain/backend/internal/service"
)

// WordHandler serves the player-facing dictionary endpoints: reporting a
// missing or unreal word, the player's own reports, and the dictionary delta.
type WordHandler struct {
	suggestions *service.WordSuggestionService
	dict        *service.DictionaryService
	auth        tokenParser
}

func NewWordHandler(suggestions *service.WordSuggestionService, dict *service.DictionaryService, auth tokenParser) *WordHandler {
	return &WordHandler{suggestions: suggestions, dict: dict, auth: auth}
}

// Submit handles POST /api/v1/words/suggestions. It is public so guests can
// report; a valid Bearer token attributes the report (and the reward) to the
// account, a bad one is treated as a guest.
func (h *WordHandler) Submit(c *gin.Context) {
	var req service.SubmitWordInput
	if err := c.ShouldBindJSON(&req); err != nil {
		respondError(c, http.StatusBadRequest, "validation_error", "invalid request body")
		return
	}
	userID := ""
	if parts := strings.SplitN(c.GetHeader("Authorization"), " ", 2); len(parts) == 2 && strings.EqualFold(parts[0], "Bearer") {
		if id, _, err := h.auth.ParseAccessToken(parts[1]); err == nil {
			userID = id
		}
	}

	out, err := h.suggestions.Submit(c.Request.Context(), userID, c.ClientIP(), req)
	switch {
	case err == nil:
		c.JSON(http.StatusOK, gin.H{"data": out})
	case errors.Is(err, service.ErrWordInvalid):
		respondError(c, http.StatusBadRequest, "invalid_word", "the word or request is not valid")
	case errors.Is(err, service.ErrWordInDictionary):
		respondError(c, http.StatusConflict, "word_in_dictionary", "the word is already in the dictionary")
	case errors.Is(err, service.ErrWordUnknown):
		respondError(c, http.StatusConflict, "word_unknown", "the word is not in the dictionary")
	case errors.Is(err, service.ErrWordReviewed):
		respondError(c, http.StatusConflict, "word_already_reviewed", "the word was already reviewed")
	case errors.Is(err, service.ErrWordRateLimited):
		respondError(c, http.StatusTooManyRequests, "rate_limited", "too many word reports today")
	default:
		slog.Error("word suggestion failed", "error", err)
		respondError(c, http.StatusInternalServerError, "internal_error", "could not store the report")
	}
}

// Mine handles GET /api/v1/words/suggestions/mine (signed-in only).
func (h *WordHandler) Mine(c *gin.Context) {
	out, err := h.suggestions.Mine(c.Request.Context(), c.GetString(middleware.ContextKeyUserID))
	if err != nil {
		slog.Error("list own word reports failed", "error", err)
		respondError(c, http.StatusInternalServerError, "internal_error", "could not load the reports")
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": gin.H{"items": out}})
}

// Delta handles GET /api/v1/dictionary/delta?since=N. Public and served from
// memory: solo and vs-AI are guest-first, so every install needs it.
func (h *WordHandler) Delta(c *gin.Context) {
	since := int64(0)
	if raw := c.Query("since"); raw != "" {
		n, err := strconv.ParseInt(raw, 10, 64)
		if err != nil || n < 0 {
			respondError(c, http.StatusBadRequest, "validation_error", "since must be a non-negative number")
			return
		}
		since = n
	}
	c.Header("Cache-Control", "no-store")
	c.JSON(http.StatusOK, gin.H{"data": h.dict.Delta(since)})
}
