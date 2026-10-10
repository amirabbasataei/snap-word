package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func adminStatus(configured, header string) int {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.GET("/x", RequireAdmin(configured), func(c *gin.Context) { c.Status(http.StatusOK) })
	req := httptest.NewRequest(http.MethodGet, "/x", nil)
	if header != "" {
		req.Header.Set("X-Admin-Key", header)
	}
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w.Code
}

func TestRequireAdmin(t *testing.T) {
	if got := adminStatus("", "anything"); got != http.StatusNotFound {
		t.Errorf("unset key must hide the routes: got %d", got)
	}
	if got := adminStatus("s3cret", ""); got != http.StatusUnauthorized {
		t.Errorf("missing key: got %d", got)
	}
	if got := adminStatus("s3cret", "wrong"); got != http.StatusUnauthorized {
		t.Errorf("wrong key: got %d", got)
	}
	if got := adminStatus("s3cret", "s3cret"); got != http.StatusOK {
		t.Errorf("right key: got %d", got)
	}
}
