package middleware

import (
	"log/slog"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"wordchain/backend/internal/service"
)

const (
	ContextKeyUserID   = "userID"
	ContextKeyUsername = "username"
)

// RequireAuth is a Gin middleware that validates a Bearer JWT on the Authorization header.
// On success it stores userID and username in the gin context for downstream handlers.
func RequireAuth(authSvc *service.AuthService) gin.HandlerFunc {
	return func(c *gin.Context) {
		header := c.GetHeader("Authorization")
		if header == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, errorEnvelope("missing_token", "authorization header is required"))
			return
		}

		parts := strings.SplitN(header, " ", 2)
		if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
			c.AbortWithStatusJSON(http.StatusUnauthorized, errorEnvelope("malformed_token", "authorization header must be 'Bearer <token>'"))
			return
		}

		userID, username, err := authSvc.ParseAccessToken(parts[1])
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, errorEnvelope("invalid_token", "token is invalid or expired"))
			return
		}

		banned, err := authSvc.IsBanned(c.Request.Context(), userID)
		if err != nil {
			slog.Error("ban check failed", "userID", userID, "error", err)
			c.AbortWithStatusJSON(http.StatusInternalServerError, errorEnvelope("internal_error", "could not verify the account"))
			return
		}
		if banned {
			c.AbortWithStatusJSON(http.StatusForbidden, errorEnvelope("account_banned", "this account has been suspended"))
			return
		}

		c.Set(ContextKeyUserID, userID)
		c.Set(ContextKeyUsername, username)
		c.Next()
	}
}

func errorEnvelope(code, message string) any {
	return map[string]any{"error": map[string]any{"code": code, "message": message}}
}
