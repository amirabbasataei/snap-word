package middleware

import (
	"context"
	"crypto/subtle"
	"errors"
	"log/slog"
	"net"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/service"
)

const (
	ContextKeyAdminActor   = "adminActor"   // service.AuditActor
	ContextKeyAdminRole    = "adminRole"    // string
	ContextKeyAdminSession = "adminSession" // *service.AdminSession; absent for X-Admin-Key requests

	// AdminScriptActor is the audit actor for requests authenticated by X-Admin-Key.
	AdminScriptActor = "script"
)

// AdminSessions is what RequireAdmin needs from service.AdminAuthService.
type AdminSessions interface {
	Enabled(ctx context.Context) bool
	Authenticate(ctx context.Context, token string) (*service.AdminSession, error)
}

// AdminEnabled reports whether the admin surface should exist at all: an
// X-Admin-Key is configured or at least one admin account exists. When it is
// not, admin routes return 404 so a bare server exposes nothing.
func AdminEnabled(ctx context.Context, key string, sessions AdminSessions) bool {
	return key != "" || (sessions != nil && sessions.Enabled(ctx))
}

// RequireAdmin guards operator endpoints. It accepts either a panel session
// cookie (zanjir_admin) or the shared secret in X-Admin-Key, which scripts use
// and which acts as an owner with actor "script". Cookie-authenticated
// requests that change state must also carry X-Requested-With: zanjir-admin
// (CSRF guard on top of SameSite=Strict); key requests carry no ambient
// credentials, so they are exempt.
func RequireAdmin(key string, sessions AdminSessions) gin.HandlerFunc {
	return func(c *gin.Context) {
		if !AdminEnabled(c.Request.Context(), key, sessions) {
			c.AbortWithStatus(http.StatusNotFound)
			return
		}

		if token, err := c.Cookie(config.AdminCookieName); err == nil && token != "" && sessions != nil {
			sess, err := sessions.Authenticate(c.Request.Context(), token)
			switch {
			case err == nil:
				if !csrfOK(c) {
					c.AbortWithStatusJSON(http.StatusForbidden, errorEnvelope("csrf_required", "missing X-Requested-With header"))
					return
				}
				c.Set(ContextKeyAdminActor, service.AuditActor{AdminID: sess.AdminID, Name: sess.Username, IP: c.ClientIP()})
				c.Set(ContextKeyAdminRole, sess.Role)
				c.Set(ContextKeyAdminSession, sess)
				c.Next()
				return
			case errors.Is(err, service.ErrAdminSessionInvalid):
				ClearAdminCookie(c)
			default:
				slog.Error("admin session check failed", "error", err)
				c.AbortWithStatusJSON(http.StatusInternalServerError, errorEnvelope("internal_error", "session check failed"))
				return
			}
		}

		if supplied := c.GetHeader("X-Admin-Key"); supplied != "" {
			if key == "" || subtle.ConstantTimeCompare([]byte(supplied), []byte(key)) != 1 {
				c.AbortWithStatusJSON(http.StatusUnauthorized, errorEnvelope("invalid_admin_key", "admin key is missing or wrong"))
				return
			}
			c.Set(ContextKeyAdminActor, service.AuditActor{Name: AdminScriptActor, IP: c.ClientIP()})
			c.Set(ContextKeyAdminRole, service.AdminRoleOwner)
			c.Next()
			return
		}

		c.AbortWithStatusJSON(http.StatusUnauthorized, errorEnvelope("admin_unauthorized", "sign in required"))
	}
}

func csrfOK(c *gin.Context) bool {
	switch c.Request.Method {
	case http.MethodGet, http.MethodHead, http.MethodOptions:
		return true
	}
	return c.GetHeader("X-Requested-With") == config.AdminCSRFHeaderValue
}

// RequireCSRFHeader applies the CSRF guard to a route that is reachable without
// a session (login), where RequireAdmin does not run.
func RequireCSRFHeader() gin.HandlerFunc {
	return func(c *gin.Context) {
		if !csrfOK(c) {
			c.AbortWithStatusJSON(http.StatusForbidden, errorEnvelope("csrf_required", "missing X-Requested-With header"))
			return
		}
		c.Next()
	}
}

// RequireRole rejects requests whose admin role ranks below min. It must run
// after RequireAdmin.
func RequireRole(min string) gin.HandlerFunc {
	return func(c *gin.Context) {
		if !service.AdminRoleAtLeast(AdminRole(c), min) {
			c.AbortWithStatusJSON(http.StatusForbidden, errorEnvelope("insufficient_role", "your role cannot perform this action"))
			return
		}
		c.Next()
	}
}

// AdminRole returns the authenticated admin's role ("" if RequireAdmin has not run).
func AdminRole(c *gin.Context) string {
	role, _ := c.Get(ContextKeyAdminRole)
	s, _ := role.(string)
	return s
}

// AdminActor returns who the request acts as, for the audit trail.
func AdminActor(c *gin.Context) service.AuditActor {
	if v, ok := c.Get(ContextKeyAdminActor); ok {
		if a, ok := v.(service.AuditActor); ok {
			return a
		}
	}
	return service.AuditActor{IP: c.ClientIP()}
}

// AdminSessionFrom returns the panel session, or nil for X-Admin-Key requests.
func AdminSessionFrom(c *gin.Context) *service.AdminSession {
	if v, ok := c.Get(ContextKeyAdminSession); ok {
		s, _ := v.(*service.AdminSession)
		return s
	}
	return nil
}

// SetAdminCookie issues the session cookie: httpOnly, SameSite=Strict, Secure
// whenever the request arrived over TLS (directly or via a proxy).
func SetAdminCookie(c *gin.Context, token string, maxAgeSec int) {
	secure := c.Request.TLS != nil || strings.EqualFold(c.GetHeader("X-Forwarded-Proto"), "https")
	c.SetSameSite(http.SameSiteStrictMode)
	c.SetCookie(config.AdminCookieName, token, maxAgeSec, "/", "", secure, true)
}

func ClearAdminCookie(c *gin.Context) {
	SetAdminCookie(c, "", -1)
}

// RequireAdminIP limits the admin surface to the given IPs/CIDRs (empty list =
// no restriction). The client address comes from gin's ClientIP, so behind a
// proxy it is only as trustworthy as the proxy's forwarding headers.
func RequireAdminIP(allowlist string) gin.HandlerFunc {
	var nets []*net.IPNet
	for _, item := range strings.Split(allowlist, ",") {
		item = strings.TrimSpace(item)
		if item == "" {
			continue
		}
		if !strings.Contains(item, "/") {
			if strings.Contains(item, ":") {
				item += "/128"
			} else {
				item += "/32"
			}
		}
		_, n, err := net.ParseCIDR(item)
		if err != nil {
			slog.Error("ignoring bad ADMIN_IP_ALLOWLIST entry", "entry", item)
			continue
		}
		nets = append(nets, n)
	}
	return func(c *gin.Context) {
		if len(nets) == 0 {
			c.Next()
			return
		}
		if ip := net.ParseIP(c.ClientIP()); ip != nil {
			for _, n := range nets {
				if n.Contains(ip) {
					c.Next()
					return
				}
			}
		}
		c.AbortWithStatus(http.StatusNotFound)
	}
}
