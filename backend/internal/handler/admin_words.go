package handler

import (
	"errors"
	"log/slog"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"wordchain/backend/internal/middleware"
	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/service"
)

// AdminWordsHandler serves the panel's «پیشنهاد کلمات» page: the review queue,
// decisions, and the manual dictionary editor. Reads are open to every admin
// role; decisions are mounted behind RequireRole(operator).
type AdminWordsHandler struct {
	svc *service.AdminWordService
}

func NewAdminWordsHandler(svc *service.AdminWordService) *AdminWordsHandler {
	return &AdminWordsHandler{svc: svc}
}

// Queue handles GET /api/v1/admin/words/suggestions.
func (h *AdminWordsHandler) Queue(c *gin.Context) {
	page, ok := intQuery(c, "page")
	if !ok {
		return
	}
	size, ok := intQuery(c, "page_size")
	if !ok {
		return
	}
	out, err := h.svc.Queue(c.Request.Context(), service.WordQueueQuery{
		Status: c.Query("status"), Kind: c.Query("kind"), Query: c.Query("q"), Sort: c.Query("sort"),
		Page: page, PageSize: size,
	})
	h.respond(c, "word queue", "", out, err)
}

// Detail handles GET /api/v1/admin/words/suggestions/:id.
func (h *AdminWordsHandler) Detail(c *gin.Context) {
	id, ok := suggestionID(c)
	if !ok {
		return
	}
	out, err := h.svc.Detail(c.Request.Context(), id)
	h.respond(c, "word detail", c.Param("id"), out, err)
}

// Approve handles POST /api/v1/admin/words/suggestions/:id/approve with
// {"outcome": "remove"|"ai_block" (removals only), "note": "..."}.
func (h *AdminWordsHandler) Approve(c *gin.Context) {
	id, ok := suggestionID(c)
	if !ok {
		return
	}
	var body struct {
		Outcome string `json:"outcome"`
		Note    string `json:"note"`
	}
	if !bindBody(c, &body) {
		return
	}
	out, err := h.svc.Approve(c.Request.Context(), middleware.AdminActor(c), id, body.Outcome, body.Note)
	h.respond(c, "word approve", c.Param("id"), out, err)
}

// Reject handles POST /api/v1/admin/words/suggestions/:id/reject with {"note": "..."}.
func (h *AdminWordsHandler) Reject(c *gin.Context) {
	id, ok := suggestionID(c)
	if !ok {
		return
	}
	var body struct {
		Note string `json:"note"`
	}
	if !bindBody(c, &body) {
		return
	}
	word, err := h.svc.Reject(c.Request.Context(), middleware.AdminActor(c), id, body.Note)
	h.respond(c, "word reject", c.Param("id"), gin.H{"word": word}, err)
}

// Bulk handles POST /api/v1/admin/words/bulk with {"ids": [...], "action": "approve"|"reject", "note": "..."}.
func (h *AdminWordsHandler) Bulk(c *gin.Context) {
	var body struct {
		IDs    []int64 `json:"ids"`
		Action string  `json:"action"`
		Note   string  `json:"note"`
	}
	if !bindBody(c, &body) {
		return
	}
	out, err := h.svc.Bulk(c.Request.Context(), middleware.AdminActor(c), body.IDs, body.Action, body.Note)
	h.respond(c, "word bulk", "", out, err)
}

// SetWord handles POST /api/v1/admin/dictionary/words with
// {"word": "...", "action": "add"|"remove"|"ai_block"|"ai_unblock", "reason": "..."}.
func (h *AdminWordsHandler) SetWord(c *gin.Context) {
	var body struct {
		Word   string `json:"word"`
		Action string `json:"action"`
		Reason string `json:"reason"`
	}
	if !bindBody(c, &body) {
		return
	}
	out, err := h.svc.SetWord(c.Request.Context(), middleware.AdminActor(c), body.Word, repository.OverrideAction(body.Action), body.Reason)
	h.respond(c, "dictionary set", body.Word, out, err)
}

// Lookup handles GET /api/v1/admin/dictionary/lookup?word=.
func (h *AdminWordsHandler) Lookup(c *gin.Context) {
	out, err := h.svc.Lookup(c.Request.Context(), c.Query("word"))
	h.respond(c, "dictionary lookup", c.Query("word"), out, err)
}

// Misses handles GET /api/v1/admin/dictionary/misses?limit=.
func (h *AdminWordsHandler) Misses(c *gin.Context) {
	limit, ok := intQuery(c, "limit")
	if !ok {
		return
	}
	out, err := h.svc.Misses(c.Request.Context(), limit)
	h.respond(c, "dictionary misses", "", gin.H{"items": out}, err)
}

// DismissMiss handles POST /api/v1/admin/dictionary/misses/dismiss with {"word": "..."}.
func (h *AdminWordsHandler) DismissMiss(c *gin.Context) {
	var body struct {
		Word string `json:"word"`
	}
	if !bindBody(c, &body) {
		return
	}
	err := h.svc.DismissMiss(c.Request.Context(), middleware.AdminActor(c), body.Word)
	h.respond(c, "dictionary dismiss miss", body.Word, gin.H{"ok": true}, err)
}

// Export handles GET /api/v1/admin/dictionary/export.
func (h *AdminWordsHandler) Export(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"data": h.svc.Export()})
}

func suggestionID(c *gin.Context) (int64, bool) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		adminError(c, http.StatusBadRequest, "validation_error", "id must be a positive number")
		return 0, false
	}
	return id, true
}

func (h *AdminWordsHandler) respond(c *gin.Context, op, id string, out any, err error) {
	switch {
	case err == nil:
		c.JSON(http.StatusOK, gin.H{"data": out})
	case errors.Is(err, service.ErrReasonRequired):
		adminError(c, http.StatusBadRequest, "reason_required",
			"a note or reason of "+strconv.Itoa(service.AdminReasonMinRunes)+"-"+strconv.Itoa(service.AdminReasonMaxRunes)+" characters is required")
	case errors.Is(err, service.ErrWordBadQuery), errors.Is(err, service.ErrWordInvalid):
		adminError(c, http.StatusBadRequest, "validation_error", "the word or query is not valid")
	case errors.Is(err, service.ErrWordBadAction), errors.Is(err, repository.ErrSuggestionOutcome):
		adminError(c, http.StatusBadRequest, "invalid_action", "unknown action or outcome")
	case errors.Is(err, service.ErrBulkTooMany):
		adminError(c, http.StatusBadRequest, "validation_error", "a bulk action takes 1-100 suggestions")
	case errors.Is(err, repository.ErrSuggestionNotFound):
		adminError(c, http.StatusNotFound, "not_found", "no such suggestion")
	case errors.Is(err, repository.ErrSuggestionNotPending):
		adminError(c, http.StatusConflict, "already_reviewed", "the suggestion was already reviewed")
	default:
		slog.Error("admin words request failed", "op", op, "id", id, "error", err)
		adminError(c, http.StatusInternalServerError, "internal_error", "could not complete the request")
	}
}
