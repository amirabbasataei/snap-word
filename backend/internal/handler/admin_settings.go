package handler

import (
	"errors"
	"log/slog"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"wordchain/backend/internal/middleware"
	"wordchain/backend/internal/service"
)

// AdminSettingsHandler serves the panel's runtime switches. Reading is open to
// every admin role; changing one is owner-only (mounted behind RequireRole),
// needs a reason and writes an audit row.
type AdminSettingsHandler struct {
	svc *service.SettingsService
}

func NewAdminSettingsHandler(svc *service.SettingsService) *AdminSettingsHandler {
	return &AdminSettingsHandler{svc: svc}
}

// OTP handles GET /api/v1/admin/settings/otp.
func (h *AdminSettingsHandler) OTP(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"data": h.svc.OTPStatus(c.Request.Context())})
}

// SetOTP handles PUT /api/v1/admin/settings/otp {sms_enabled, reason}.
func (h *AdminSettingsHandler) SetOTP(c *gin.Context) {
	var body struct {
		SMSEnabled *bool  `json:"sms_enabled"`
		Reason     string `json:"reason"`
	}
	if !bindBody(c, &body) {
		return
	}
	if body.SMSEnabled == nil {
		adminError(c, http.StatusBadRequest, "validation_error", "sms_enabled is required")
		return
	}
	st, err := h.svc.SetOTPSMSEnabled(c.Request.Context(), middleware.AdminActor(c), *body.SMSEnabled, body.Reason)
	switch {
	case err == nil:
		c.JSON(http.StatusOK, gin.H{"data": st})
	case errors.Is(err, service.ErrReasonRequired):
		adminError(c, http.StatusBadRequest, "reason_required",
			"a reason of "+strconv.Itoa(service.AdminReasonMinRunes)+"-"+strconv.Itoa(service.AdminReasonMaxRunes)+" characters is required")
	default:
		slog.Error("admin set otp setting failed", "error", err)
		adminError(c, http.StatusInternalServerError, "internal_error", "could not complete the request")
	}
}
