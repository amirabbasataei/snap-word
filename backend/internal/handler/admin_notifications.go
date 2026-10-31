package handler

import (
	"errors"
	"log/slog"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/middleware"
	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/service"
)

// AdminNotificationsHandler serves the panel's «اعلان‌ها» page. Reads (reach,
// preview, history) are open to every admin role; sending is mounted behind
// RequireRole(operator).
type AdminNotificationsHandler struct {
	svc *service.AdminNotificationService
}

func NewAdminNotificationsHandler(svc *service.AdminNotificationService) *AdminNotificationsHandler {
	return &AdminNotificationsHandler{svc: svc}
}

type audienceBody struct {
	Type    string                   `json:"type"`
	Segment *repository.NotifSegment `json:"segment"`
	UserIDs []string                 `json:"user_ids"`
}

func (a audienceBody) model() repository.NotifAudience {
	return repository.NotifAudience{Type: a.Type, Segment: a.Segment, UserIDs: a.UserIDs}
}

// Reach handles GET /api/v1/admin/notifications/reach.
func (h *AdminNotificationsHandler) Reach(c *gin.Context) {
	out, err := h.svc.Reach(c.Request.Context())
	h.respond(c, "notifications reach", out, err)
}

// Preview handles POST /api/v1/admin/notifications/preview {audience}.
func (h *AdminNotificationsHandler) Preview(c *gin.Context) {
	var body struct {
		Audience audienceBody `json:"audience"`
	}
	if !bindBody(c, &body) {
		return
	}
	out, err := h.svc.Preview(c.Request.Context(), body.Audience.model())
	h.respond(c, "notifications preview", out, err)
}

// Send handles POST /api/v1/admin/notifications
// {title, body, route, channels: ["push","inapp"], audience}.
func (h *AdminNotificationsHandler) Send(c *gin.Context) {
	var body struct {
		Title    string       `json:"title"`
		Body     string       `json:"body"`
		Route    string       `json:"route"`
		Channels []string     `json:"channels"`
		Audience audienceBody `json:"audience"`
	}
	if !bindBody(c, &body) {
		return
	}
	out, err := h.svc.Send(c.Request.Context(), middleware.AdminActor(c), service.NotifSendInput{
		Title: body.Title, Body: body.Body, Route: body.Route, Channels: body.Channels, Audience: body.Audience.model(),
	})
	h.respond(c, "notifications send", out, err)
}

// List handles GET /api/v1/admin/notifications?page=&page_size=.
func (h *AdminNotificationsHandler) List(c *gin.Context) {
	page, ok := intQuery(c, "page")
	if !ok {
		return
	}
	size, ok := intQuery(c, "page_size")
	if !ok {
		return
	}
	out, err := h.svc.List(c.Request.Context(), page, size)
	h.respond(c, "notifications list", out, err)
}

// Get handles GET /api/v1/admin/notifications/:id.
func (h *AdminNotificationsHandler) Get(c *gin.Context) {
	out, err := h.svc.Get(c.Request.Context(), c.Param("id"))
	h.respond(c, "notifications get", out, err)
}

func (h *AdminNotificationsHandler) respond(c *gin.Context, op string, out any, err error) {
	switch {
	case err == nil:
		c.JSON(http.StatusOK, gin.H{"data": out})
	case errors.Is(err, service.ErrNotifTitle):
		adminError(c, http.StatusBadRequest, "invalid_title", "title must be 1-"+strconv.Itoa(config.NotifTitleMaxRunes)+" characters")
	case errors.Is(err, service.ErrNotifBody):
		adminError(c, http.StatusBadRequest, "invalid_body", "body must be 1-"+strconv.Itoa(config.NotifBodyMaxRunes)+" characters")
	case errors.Is(err, service.ErrNotifChannels):
		adminError(c, http.StatusBadRequest, "invalid_channels", "channels must be push, inapp, or both")
	case errors.Is(err, service.ErrNotifRoute):
		adminError(c, http.StatusBadRequest, "invalid_route", "unknown deep link")
	case errors.Is(err, service.ErrNotifAudience):
		adminError(c, http.StatusBadRequest, "invalid_audience", "the audience is not valid")
	case errors.Is(err, service.ErrNotifUnknownUser):
		adminError(c, http.StatusBadRequest, "unknown_user", "one of the addressed users does not exist or is banned")
	case errors.Is(err, service.ErrNotifFCMOff):
		adminError(c, http.StatusConflict, "fcm_not_configured", "push delivery is not configured on the server")
	case errors.Is(err, service.ErrNotifNoRecipients):
		adminError(c, http.StatusConflict, "no_recipients", "the audience matches nobody")
	case errors.Is(err, service.ErrNotifNoDeliverable):
		adminError(c, http.StatusConflict, "no_push_recipients", "nobody in the audience has notifications enabled")
	case errors.Is(err, service.ErrNotifDuplicate):
		adminError(c, http.StatusConflict, "duplicate_recent", "an identical notification was just sent")
	case errors.Is(err, service.ErrNotifNotFound):
		adminError(c, http.StatusNotFound, "not_found", "no such notification")
	default:
		slog.Error("admin notifications request failed", "op", op, "error", err)
		adminError(c, http.StatusInternalServerError, "internal_error", "could not complete the request")
	}
}
