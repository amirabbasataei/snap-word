package handler

import (
	"errors"
	"log/slog"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"wordchain/backend/internal/service"
)

// AdminDashboardHandler serves the read-only dashboard endpoints (any admin role).
type AdminDashboardHandler struct {
	svc *service.AdminDashboardService
}

func NewAdminDashboardHandler(svc *service.AdminDashboardService) *AdminDashboardHandler {
	return &AdminDashboardHandler{svc: svc}
}

// Summary handles GET /api/v1/admin/dashboard/summary.
func (h *AdminDashboardHandler) Summary(c *gin.Context) {
	out, err := h.svc.Summary(c.Request.Context())
	if err != nil {
		slog.Error("admin dashboard summary failed", "error", err)
		adminError(c, http.StatusInternalServerError, "internal_error", "could not load the dashboard")
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": out})
}

// Timeseries handles GET /api/v1/admin/dashboard/timeseries?days=30.
func (h *AdminDashboardHandler) Timeseries(c *gin.Context) {
	days := service.DefaultDashboardDays
	if raw := c.Query("days"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil {
			adminError(c, http.StatusBadRequest, "validation_error", "days must be a number")
			return
		}
		days = n
	}
	out, err := h.svc.Timeseries(c.Request.Context(), days)
	switch {
	case errors.Is(err, service.ErrInvalidDashboardRange):
		adminError(c, http.StatusBadRequest, "validation_error", "days must be between 1 and 90")
		return
	case err != nil:
		slog.Error("admin dashboard timeseries failed", "error", err)
		adminError(c, http.StatusInternalServerError, "internal_error", "could not load the dashboard")
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": gin.H{"days": out}})
}
