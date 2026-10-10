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

// AdminContentHandler serves the panel's content pages: catalogue listings,
// the Daily Challenge calendar and the leaderboard views. Reads are open to
// every admin role; the start-letter change is mounted behind RequireRole(operator).
// Taunt/avatar writes are CatalogHandler's.
type AdminContentHandler struct {
	svc *service.AdminContentService
}

func NewAdminContentHandler(svc *service.AdminContentService) *AdminContentHandler {
	return &AdminContentHandler{svc: svc}
}

// Taunts handles GET /api/v1/admin/taunts.
func (h *AdminContentHandler) Taunts(c *gin.Context) {
	out, err := h.svc.Taunts(c.Request.Context())
	h.respond(c, "taunts", "", out, err)
}

// Avatars handles GET /api/v1/admin/avatars.
func (h *AdminContentHandler) Avatars(c *gin.Context) {
	out, err := h.svc.Avatars(c.Request.Context())
	h.respond(c, "avatars", "", out, err)
}

// AvatarUsage handles GET /api/v1/admin/avatars/:id/usage.
func (h *AdminContentHandler) AvatarUsage(c *gin.Context) {
	out, err := h.svc.AvatarUsage(c.Request.Context(), c.Param("id"))
	h.respond(c, "avatar usage", c.Param("id"), out, err)
}

// DailyList handles GET /api/v1/admin/daily?from=YYYY-MM-DD&to=YYYY-MM-DD.
func (h *AdminContentHandler) DailyList(c *gin.Context) {
	out, err := h.svc.DailyCalendar(c.Request.Context(), c.Query("from"), c.Query("to"))
	h.respond(c, "daily list", "", out, err)
}

// DailyDetail handles GET /api/v1/admin/daily/:date.
func (h *AdminContentHandler) DailyDetail(c *gin.Context) {
	out, err := h.svc.DailyDetail(c.Request.Context(), c.Param("date"))
	h.respond(c, "daily detail", c.Param("date"), out, err)
}

// SetStartLetter handles PATCH /api/v1/admin/daily/:date with {"start_letter": "ب", "reason": "..."}.
func (h *AdminContentHandler) SetStartLetter(c *gin.Context) {
	var body struct {
		StartLetter string `json:"start_letter"`
		Reason      string `json:"reason"`
	}
	if !bindBody(c, &body) {
		return
	}
	out, err := h.svc.SetStartLetter(c.Request.Context(), middleware.AdminActor(c), c.Param("date"), body.StartLetter, body.Reason)
	h.respond(c, "daily start letter", c.Param("date"), out, err)
}

// WeeklyBoard handles GET /api/v1/admin/leaderboards/weekly?limit=.
func (h *AdminContentHandler) WeeklyBoard(c *gin.Context) {
	limit, ok := intQuery(c, "limit")
	if !ok {
		return
	}
	out, err := h.svc.WeeklyBoard(c.Request.Context(), limit)
	h.respond(c, "weekly board", "", out, err)
}

// AllTimeBoard handles GET /api/v1/admin/leaderboards/alltime?limit=.
func (h *AdminContentHandler) AllTimeBoard(c *gin.Context) {
	limit, ok := intQuery(c, "limit")
	if !ok {
		return
	}
	out, err := h.svc.AllTimeBoard(c.Request.Context(), limit)
	h.respond(c, "all-time board", "", out, err)
}

// WeeklyRewards handles GET /api/v1/admin/leaderboards/rewards?weeks=.
func (h *AdminContentHandler) WeeklyRewards(c *gin.Context) {
	weeks, ok := intQuery(c, "weeks")
	if !ok {
		return
	}
	out, err := h.svc.WeeklyRewardHistory(c.Request.Context(), weeks)
	h.respond(c, "weekly rewards", "", out, err)
}

func (h *AdminContentHandler) respond(c *gin.Context, op, id string, out any, err error) {
	switch {
	case err == nil:
		c.JSON(http.StatusOK, gin.H{"data": out})
	case errors.Is(err, service.ErrReasonRequired):
		adminError(c, http.StatusBadRequest, "reason_required",
			"a reason of "+strconv.Itoa(service.AdminReasonMinRunes)+"-"+strconv.Itoa(service.AdminReasonMaxRunes)+" characters is required")
	case errors.Is(err, service.ErrInvalidDate):
		adminError(c, http.StatusBadRequest, "invalid_date", "date must be YYYY-MM-DD within the allowed range")
	case errors.Is(err, service.ErrInvalidLetter):
		adminError(c, http.StatusBadRequest, "invalid_letter", "start letter must be one letter that enough dictionary words begin with")
	case errors.Is(err, service.ErrInvalidLimit):
		adminError(c, http.StatusBadRequest, "validation_error", "limit is out of range")
	case errors.Is(err, service.ErrDailyNotEditable):
		adminError(c, http.StatusConflict, "date_not_editable", "only future days can be changed")
	case errors.Is(err, service.ErrNoChallenge):
		adminError(c, http.StatusNotFound, "no_daily_challenge", "no challenge exists for that date")
	case errors.Is(err, repository.ErrCatalogItemNotFound):
		adminError(c, http.StatusNotFound, "not_found", "no such entry")
	default:
		slog.Error("admin content request failed", "op", op, "id", id, "error", err)
		adminError(c, http.StatusInternalServerError, "internal_error", "could not complete the request")
	}
}
