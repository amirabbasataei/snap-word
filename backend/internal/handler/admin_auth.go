package handler

import (
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/middleware"
	"wordchain/backend/internal/service"
)

// AdminAuthHandler serves the panel's sign-in, sign-out and "who am I" routes.
type AdminAuthHandler struct {
	auth   *service.AdminAuthService
	audit  *service.AuditService
	apiKey string
}

func NewAdminAuthHandler(auth *service.AdminAuthService, audit *service.AuditService, apiKey string) *AdminAuthHandler {
	return &AdminAuthHandler{auth: auth, audit: audit, apiKey: apiKey}
}

type adminJSON struct {
	ID          string     `json:"id"`
	Username    string     `json:"username"`
	Role        string     `json:"role"`
	LastLoginAt *time.Time `json:"last_login_at"`
	Via         string     `json:"via"` // "session" or "key"
}

// Login handles POST /api/v1/admin/auth/login with {"username", "password"}.
// It is reachable without a session, so it carries its own 404-when-disabled
// and CSRF checks.
func (h *AdminAuthHandler) Login(c *gin.Context) {
	if !middleware.AdminEnabled(c.Request.Context(), h.apiKey, h.auth) {
		c.Status(http.StatusNotFound)
		return
	}
	var req struct {
		Username string `json:"username" binding:"required"`
		Password string `json:"password" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		adminError(c, http.StatusBadRequest, "validation_error", "username and password are required")
		return
	}

	ctx := c.Request.Context()
	ip := c.ClientIP()
	sess, admin, err := h.auth.Login(ctx, ip, req.Username, req.Password)
	switch {
	case errors.Is(err, service.ErrAdminRateLimited):
		h.audit.LogRecord(ctx, service.AuditActor{Name: req.Username, IP: ip}, "auth.login_blocked", service.AuditTarget{}, nil)
		c.Header("Retry-After", strconv.Itoa(int(config.AdminLoginWindow.Seconds())))
		adminError(c, http.StatusTooManyRequests, "rate_limited", "too many failed attempts, try again later")
		return
	case errors.Is(err, service.ErrAdminInvalidCredentials):
		h.audit.LogRecord(ctx, service.AuditActor{Name: req.Username, IP: ip}, "auth.login_failed", service.AuditTarget{}, nil)
		adminError(c, http.StatusUnauthorized, "invalid_credentials", "wrong username or password")
		return
	case err != nil:
		slog.Error("admin login failed", "error", err)
		adminError(c, http.StatusInternalServerError, "internal_error", "login failed")
		return
	}

	middleware.SetAdminCookie(c, sess.Token, int(h.auth.AbsoluteTTL().Seconds()))
	h.audit.LogRecord(ctx, service.AuditActor{AdminID: admin.ID, Name: admin.Username, IP: ip}, "auth.login", service.AuditTarget{Type: "admin", ID: admin.ID}, nil)
	c.JSON(http.StatusOK, gin.H{"data": gin.H{"admin": adminJSON{
		ID: admin.ID, Username: admin.Username, Role: admin.Role, LastLoginAt: admin.LastLoginAt, Via: "session",
	}}})
}

// Logout handles POST /api/v1/admin/auth/logout (ends the panel session).
func (h *AdminAuthHandler) Logout(c *gin.Context) {
	if sess := middleware.AdminSessionFrom(c); sess != nil {
		h.auth.Logout(c.Request.Context(), sess)
		h.audit.LogRecord(c.Request.Context(), middleware.AdminActor(c), "auth.logout", service.AuditTarget{Type: "admin", ID: sess.AdminID}, nil)
	}
	middleware.ClearAdminCookie(c)
	c.JSON(http.StatusOK, gin.H{"data": gin.H{"ok": true}})
}

// Me handles GET /api/v1/admin/auth/me.
func (h *AdminAuthHandler) Me(c *gin.Context) {
	actor := middleware.AdminActor(c)
	out := adminJSON{ID: actor.AdminID, Username: actor.Name, Role: middleware.AdminRole(c), Via: "key"}
	if sess := middleware.AdminSessionFrom(c); sess != nil {
		out.Via = "session"
	}
	c.JSON(http.StatusOK, gin.H{"data": gin.H{"admin": out}})
}
