package middleware

import (
	"crypto/subtle"
	"net/http"

	"github.com/gin-gonic/gin"
)

// RequireAdmin guards operator endpoints with a shared secret in X-Admin-Key.
// An empty configured key disables the endpoints entirely (404), so a server
// without ADMIN_API_KEY exposes no admin surface.
func RequireAdmin(key string) gin.HandlerFunc {
	return func(c *gin.Context) {
		if key == "" {
			c.AbortWithStatus(http.StatusNotFound)
			return
		}
		if subtle.ConstantTimeCompare([]byte(c.GetHeader("X-Admin-Key")), []byte(key)) != 1 {
			c.AbortWithStatusJSON(http.StatusUnauthorized, errorEnvelope("invalid_admin_key", "admin key is missing or wrong"))
			return
		}
		c.Next()
	}
}
