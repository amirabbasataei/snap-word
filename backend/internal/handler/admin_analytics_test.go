package handler_test

import (
	"net/http"
	"testing"

	"wordchain/backend/internal/handler"
	"wordchain/backend/internal/middleware"
	"wordchain/backend/internal/service"
)

// Analytics is read-only (any admin role) and every bad parameter is a 400
// validation_error, never a 500. Validation fails before the store is touched,
// so a nil store is enough here.
func TestAdminAnalytics_ViewerReachableAndValidated(t *testing.T) {
	e := newAdminEnv(t, "", true)
	h := handler.NewAdminAnalyticsHandler(service.NewAdminAnalyticsService(nil, nil))
	g := e.router.Group("/api/v1/admin/analytics", middleware.RequireAdmin("", e.auth))
	g.GET("/overview", h.Overview)
	g.GET("/retention", h.Retention)
	g.GET("/funnel", h.Funnel)
	g.GET("/users/:id/timeline", h.UserTimeline)
	viewer := e.login(t, "peek")

	for _, p := range []string{
		"/overview?days=0", "/overview?days=abc", "/overview?days=91",
		"/retention?by=weird", "/retention?from=yesterday",
		"/funnel?steps=app_open", "/funnel?steps=app_open,bogus",
		"/users/not-a-uuid/timeline", "/users/aaaaaaaa-0000-4000-8000-000000000001/timeline?before=x",
	} {
		w := e.do(call{method: "GET", path: "/api/v1/admin/analytics" + p, cookie: viewer})
		if w.Code != http.StatusBadRequest || errCode(t, w) != "validation_error" {
			t.Errorf("%s: %d %s", p, w.Code, w.Body)
		}
	}
	if w := e.do(call{method: "GET", path: "/api/v1/admin/analytics/overview?days=7"}); w.Code != http.StatusUnauthorized {
		t.Errorf("anonymous: %d", w.Code)
	}
}
