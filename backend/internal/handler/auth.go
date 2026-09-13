package handler

import (
	"errors"
	"log/slog"
	"net/http"

	"github.com/gin-gonic/gin"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/middleware"
	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/service"
)

// AuthHandler exposes the OTP auth and referral endpoints.
type AuthHandler struct {
	authSvc *service.AuthService
	cfg     *config.Config
}

func NewAuthHandler(authSvc *service.AuthService, cfg *config.Config) *AuthHandler {
	return &AuthHandler{authSvc: authSvc, cfg: cfg}
}

type sendOTPRequest struct {
	Phone string `json:"phone" binding:"required"`
	Voice bool   `json:"voice"`
}

type sendOTPResponse struct {
	ExpiresInSeconds      int `json:"expires_in_seconds"`
	ResendCooldownSeconds int `json:"resend_cooldown_seconds"`
}

type verifyOTPRequest struct {
	Phone        string `json:"phone" binding:"required"`
	Code         string `json:"code" binding:"required,len=4"`
	ReferralCode string `json:"referral_code"`
}

type verifyOTPResponse struct {
	AccessToken     string `json:"access_token"`
	RefreshToken    string `json:"refresh_token"`
	UserID          string `json:"user_id"`
	Username        string `json:"username"`
	Coins           int    `json:"coins"`
	IsNewUser       bool   `json:"is_new_user"`
	ReferralWarning string `json:"referral_warning,omitempty"`
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

type redeemReferralRequest struct {
	ReferralCode string `json:"referral_code" binding:"required,len=6"`
}

type redeemReferralResponse struct {
	CoinsAwarded int `json:"coins_awarded"`
}

// SendOTP handles POST /api/v1/auth/send-otp.
func (h *AuthHandler) SendOTP(c *gin.Context) {
	var req sendOTPRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		respondError(c, http.StatusBadRequest, "validation_error", err.Error())
		return
	}

	slog.Info("send-otp attempt", "voice", req.Voice)

	if err := h.authSvc.SendOTP(c.Request.Context(), req.Phone, req.Voice); err != nil {
		respondAuthError(c, err)
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": sendOTPResponse{
		ExpiresInSeconds:      int(h.cfg.OTPCodeTTL.Seconds()),
		ResendCooldownSeconds: int(h.cfg.OTPResendCooldown.Seconds()),
	}})
}

// VerifyOTP handles POST /api/v1/auth/verify-otp.
func (h *AuthHandler) VerifyOTP(c *gin.Context) {
	var req verifyOTPRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		respondError(c, http.StatusBadRequest, "validation_error", err.Error())
		return
	}

	pair, result, err := h.authSvc.VerifyOTP(c.Request.Context(), req.Phone, req.Code, req.ReferralCode)
	if err != nil {
		respondAuthError(c, err)
		return
	}

	slog.Info("verify-otp success", "userID", result.UserID, "isNewUser", result.IsNewUser)
	c.JSON(http.StatusOK, gin.H{"data": verifyOTPResponse{
		AccessToken:     pair.AccessToken,
		RefreshToken:    pair.RefreshToken,
		UserID:          pair.UserID,
		Username:        result.Username,
		Coins:           result.Coins,
		IsNewUser:       result.IsNewUser,
		ReferralWarning: result.ReferralWarning,
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

// RedeemReferral handles POST /api/v1/referral/redeem (protected). This is
// entry point (b): an already-authenticated user submitting a referral code
// after the fact, one-time only.
func (h *AuthHandler) RedeemReferral(c *gin.Context) {
	userID := c.GetString(middleware.ContextKeyUserID)

	var req redeemReferralRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		respondError(c, http.StatusBadRequest, "validation_error", err.Error())
		return
	}

	coins, err := h.authSvc.RedeemReferral(c.Request.Context(), userID, req.ReferralCode)
	if err != nil {
		respondAuthError(c, err)
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": redeemReferralResponse{CoinsAwarded: coins}})
}

// respondAuthError maps service/repository sentinel errors to HTTP status codes.
func respondAuthError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, service.ErrInvalidPhone):
		respondError(c, http.StatusBadRequest, "invalid_phone", "phone number is not a valid Iran mobile number")
	case errors.Is(err, service.ErrResendCooldown):
		respondError(c, http.StatusTooManyRequests, "resend_cooldown", "please wait before requesting another code")
	case errors.Is(err, service.ErrOTPRateLimited):
		respondError(c, http.StatusTooManyRequests, "rate_limited", "too many code requests for this number today")
	case errors.Is(err, service.ErrOTPNotRequested):
		respondError(c, http.StatusBadRequest, "otp_not_requested", "no code was requested for this number")
	case errors.Is(err, service.ErrInvalidOTP):
		respondError(c, http.StatusBadRequest, "invalid_code", "the code you entered is incorrect")
	case errors.Is(err, service.ErrOTPExpired):
		respondError(c, http.StatusBadRequest, "code_expired", "this code has expired, request a new one")
	case errors.Is(err, service.ErrOTPMaxAttempts):
		respondError(c, http.StatusTooManyRequests, "too_many_attempts", "too many incorrect attempts, request a new code")
	case errors.Is(err, service.ErrSelfReferral):
		respondError(c, http.StatusBadRequest, "self_referral", "you cannot use your own referral code")
	case errors.Is(err, service.ErrReferralNotFound):
		respondError(c, http.StatusNotFound, "referral_not_found", "referral code not found")
	case errors.Is(err, repository.ErrReferralAlreadyUsed):
		respondError(c, http.StatusConflict, "referral_already_used", "a referral code has already been used on this account")
	case errors.Is(err, service.ErrInvalidToken):
		respondError(c, http.StatusUnauthorized, "invalid_token", "token is invalid or expired")
	default:
		slog.Error("auth error", "error", err)
		respondError(c, http.StatusInternalServerError, "internal_error", "an unexpected error occurred")
	}
}

// respondError writes the standard { "error": { "code": "...", "message": "..." } } envelope.
func respondError(c *gin.Context, status int, code, message string) {
	c.JSON(status, gin.H{"error": gin.H{"code": code, "message": message}})
}
