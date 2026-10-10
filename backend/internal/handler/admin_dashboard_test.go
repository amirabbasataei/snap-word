package handler_test

import (
	"net/http"
	"testing"

	"wordchain/backend/internal/handler"
	"wordchain/backend/internal/middleware"
	"wordchain/backend/internal/service"
)

// The dashboard is read-only, so the weakest role (viewer) must reach it, and
// a bad window must be a 400 validation_error rather than a 500.
func TestAdminDashboard_TimeseriesValidation(t *testing.T) {
	e := newAdminEnv(t, "", true)
	h := handler.NewAdminDashboardHandler(service.NewAdminDashboardService(nil, nil, nil, nil))
	e.router.GET("/api/v1/admin/dashboard/timeseries", middleware.RequireAdmin("", e.auth), h.Timeseries)
	viewer := e.login(t, "peek")

	for _, q := range []string{"?days=0", "?days=91", "?days=abc"} {
		w := e.do(call{method: "GET", path: "/api/v1/admin/dashboard/timeseries" + q, cookie: viewer})
		if w.Code != http.StatusBadRequest || errCode(t, w) != "validation_error" {
			t.Errorf("%s: %d %s", q, w.Code, w.Body)
		}
	}
	if w := e.do(call{method: "GET", path: "/api/v1/admin/dashboard/timeseries?days=7"}); w.Code != http.StatusUnauthorized {
		t.Errorf("anonymous: %d", w.Code)
	}
}
