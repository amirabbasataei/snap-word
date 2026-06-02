package handler

import (
	"errors"
	"log/slog"
	"net/http"

	"github.com/gin-gonic/gin"

	"wordchain/backend/internal/service"
)

// AuthHandler exposes the three auth endpoints.
type AuthHandler struct {
	authSvc *service.AuthService
}

func NewAuthHandler(authSvc *service.AuthService) *AuthHandler {
	return &AuthHandler{authSvc: authSvc}
}

type registerRequest struct {
	Username string `json:"username" binding:"required"`
	Email    string `json:"email"    binding:"required"`
	Password string `json:"password" binding:"required"`
}

type loginRequest struct {
	Email    string `json:"email"    binding:"required"`
	Password string `json:"password" binding:"required"`
}

type refreshRequest struct {
	RefreshToken string `json:"refresh_token" binding:"required"`
}

type tokenResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	UserID       string `json:"user_id"`
	Username     string `json:"username"`
}

// Register handles POST /api/v1/auth/register.
func (h *AuthHandler) Register(c *gin.Context) {
	var req registerRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		respondError(c, http.StatusBadRequest, "validation_error", err.Error())
		return
	}

	slog.Info("register attempt", "username", req.Username, "email", req.Email)

	pair, err := h.authSvc.Register(c.Request.Context(), req.Username, req.Email, req.Password)
	if err != nil {
		respondAuthError(c, err)
		return
	}

	slog.Info("user registered", "username", req.Username)
	c.JSON(http.StatusCreated, gin.H{"data": tokenResponse{
		AccessToken:  pair.AccessToken,
		RefreshToken: pair.RefreshToken,
		UserID:       pair.UserID,
		Username:     pair.Username,
	}})
}

// Login handles POST /api/v1/auth/login.
func (h *AuthHandler) Login(c *gin.Context) {
	var req loginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		respondError(c, http.StatusBadRequest, "validation_error", err.Error())
		return
	}

	slog.Info("login attempt", "email", req.Email)

	pair, err := h.authSvc.Login(c.Request.Context(), req.Email, req.Password)
	if err != nil {
		respondAuthError(c, err)
		return
	}

	slog.Info("login success", "email", req.Email)
	c.JSON(http.StatusOK, gin.H{"data": tokenResponse{
		AccessToken:  pair.AccessToken,
		RefreshToken: pair.RefreshToken,
		UserID:       pair.UserID,
		Username:     pair.Username,
	}})
}

// Refresh handles POST /api/v1/auth/refresh.
func (h *AuthHandler) Refresh(c *gin.Context) {
	var req refreshRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		respondError(c, http.StatusBadRequest, "validation_error", err.Error())
		return
	}

	pair, err := h.authSvc.RefreshToken(c.Request.Context(), req.RefreshToken)
	if err != nil {
		respondAuthError(c, err)
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": tokenResponse{
		AccessToken:  pair.AccessToken,
		RefreshToken: pair.RefreshToken,
		UserID:       pair.UserID,
		Username:     pair.Username,
	}})
}

// respondAuthError maps service sentinel errors to HTTP status codes.
func respondAuthError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, service.ErrUserExists):
		respondError(c, http.StatusConflict, "user_already_exists", "username or email already taken")
	case errors.Is(err, service.ErrInvalidCredentials):
		respondError(c, http.StatusUnauthorized, "invalid_credentials", "email or password is incorrect")
	case errors.Is(err, service.ErrInvalidToken):
		respondError(c, http.StatusUnauthorized, "invalid_token", "token is invalid or expired")
	case errors.Is(err, service.ErrWeakPassword):
		respondError(c, http.StatusBadRequest, "weak_password", "password must be at least 8 characters and contain at least one letter and one digit")
	case errors.Is(err, service.ErrInvalidUsername):
		respondError(c, http.StatusBadRequest, "invalid_username", "username must be 3–32 characters and contain only letters, digits, and underscores")
	case errors.Is(err, service.ErrInvalidEmail):
		respondError(c, http.StatusBadRequest, "invalid_email", "email address is not valid")
	default:
		slog.Error("auth error", "error", err)
		respondError(c, http.StatusInternalServerError, "internal_error", "an unexpected error occurred")
	}
}

// respondError writes the standard { "error": { "code": "...", "message": "..." } } envelope.
func respondError(c *gin.Context, status int, code, message string) {
	c.JSON(status, gin.H{"error": gin.H{"code": code, "message": message}})
}
