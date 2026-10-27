package handler

import (
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/service"
)

// AdminAnalyticsHandler serves the read-only analytics endpoints (any admin role).
type AdminAnalyticsHandler struct {
	svc *service.AdminAnalyticsService
}

func NewAdminAnalyticsHandler(svc *service.AdminAnalyticsService) *AdminAnalyticsHandler {
	return &AdminAnalyticsHandler{svc: svc}
}

func (h *AdminAnalyticsHandler) fail(c *gin.Context, what string, err error) {
	if errors.Is(err, service.ErrInvalidAnalyticsQuery) {
		adminError(c, http.StatusBadRequest, "validation_error", "invalid analytics query")
		return
	}
	slog.Error("admin analytics failed", "what", what, "error", err)
	adminError(c, http.StatusInternalServerError, "internal_error", "could not load analytics")
}

// daysParam reads ?days=, defaulting to 30. ok=false means a 400 was written.
func daysParam(c *gin.Context) (int, bool) {
	raw := c.Query("days")
	if raw == "" {
		return service.DefaultAnalyticsDays, true
	}
	n, err := strconv.Atoi(raw)
	if err != nil {
		adminError(c, http.StatusBadRequest, "validation_error", "days must be a number")
		return 0, false
	}
	return n, true
}

func (h *AdminAnalyticsHandler) Overview(c *gin.Context) {
	days, ok := daysParam(c)
	if !ok {
		return
	}
	out, err := h.svc.Overview(c.Request.Context(), days)
	if err != nil {
		h.fail(c, "overview", err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": out})
}

// Retention handles GET /analytics/retention?from=YYYY-MM-DD&to=YYYY-MM-DD&by=install|user.
func (h *AdminAnalyticsHandler) Retention(c *gin.Context) {
	to := config.IranDate(time.Now())
	from := to.AddDate(0, 0, -(service.DefaultAnalyticsDays - 1))
	for _, f := range []struct {
		q   string
		dst *time.Time
	}{{"from", &from}, {"to", &to}} {
		if raw := c.Query(f.q); raw != "" {
			t, err := time.Parse("2006-01-02", raw)
			if err != nil {
				adminError(c, http.StatusBadRequest, "validation_error", f.q+" must be YYYY-MM-DD")
				return
			}
			*f.dst = t
		}
	}
	by := c.DefaultQuery("by", "install")
	out, err := h.svc.Retention(c.Request.Context(), from, to, by)
	if err != nil {
		h.fail(c, "retention", err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": out})
}

// Funnel handles GET /analytics/funnel?steps=app_open,game_start,signup&days=30.
func (h *AdminAnalyticsHandler) Funnel(c *gin.Context) {
	days, ok := daysParam(c)
	if !ok {
		return
	}
	out, err := h.svc.Funnel(c.Request.Context(), splitCSV(c.Query("steps")), days)
	if err != nil {
		h.fail(c, "funnel", err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": gin.H{"steps": out}})
}

func (h *AdminAnalyticsHandler) Screens(c *gin.Context) {
	days, ok := daysParam(c)
	if !ok {
		return
	}
	out, err := h.svc.Screens(c.Request.Context(), days)
	if err != nil {
		h.fail(c, "screens", err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": gin.H{"screens": out}})
}

func (h *AdminAnalyticsHandler) Events(c *gin.Context) {
	days, ok := daysParam(c)
	if !ok {
		return
	}
	out, err := h.svc.Events(c.Request.Context(), days, splitCSV(c.Query("names")))
	if err != nil {
		h.fail(c, "events", err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": gin.H{"events": out}})
}

// UserTimeline / InstallTimeline handle GET /analytics/{users|installs}/:id/timeline?before=&limit=.
func (h *AdminAnalyticsHandler) UserTimeline(c *gin.Context)    { h.timeline(c, true) }
func (h *AdminAnalyticsHandler) InstallTimeline(c *gin.Context) { h.timeline(c, false) }

func (h *AdminAnalyticsHandler) timeline(c *gin.Context, byUser bool) {
	var before time.Time
	if raw := c.Query("before"); raw != "" {
		t, err := time.Parse(time.RFC3339Nano, raw)
		if err != nil {
			adminError(c, http.StatusBadRequest, "validation_error", "before must be an RFC 3339 time")
			return
		}
		before = t
	}
	limit := 0
	if raw := c.Query("limit"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil {
			adminError(c, http.StatusBadRequest, "validation_error", "limit must be a number")
			return
		}
		limit = n
	}
	out, err := h.svc.Timeline(c.Request.Context(), byUser, c.Param("id"), before, limit)
	if err != nil {
		h.fail(c, "timeline", err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": out})
}

func splitCSV(s string) []string {
	if s == "" {
		return nil
	}
	var out []string
	for _, p := range strings.Split(s, ",") {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}
