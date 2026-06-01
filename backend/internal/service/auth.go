package service

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"time"
	"unicode"

	"github.com/golang-jwt/jwt/v5"
	"github.com/lib/pq"
	"golang.org/x/crypto/bcrypt"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/repository"
)

var (
	ErrUserExists          = errors.New("user_already_exists")
	ErrInvalidCredentials  = errors.New("invalid_credentials")
	ErrInvalidToken        = errors.New("invalid_token")
	ErrWeakPassword        = errors.New("weak_password")
	ErrInvalidUsername     = errors.New("invalid_username")
	ErrInvalidEmail        = errors.New("invalid_email")
)

var usernameRe = regexp.MustCompile(`^[a-zA-Z0-9_]{3,32}$`)
var emailRe = regexp.MustCompile(`^[^@\s]+@[^@\s]+\.[^@\s]+$`)

// TokenPair holds an access token and a refresh token.
type TokenPair struct {
	AccessToken  string
	RefreshToken string
}

type claims struct {
	UserID   string `json:"sub"`
	Username string `json:"username"`
	Type     string `json:"type"` // "access" | "refresh"
	jwt.RegisteredClaims
}

// AuthService handles registration, login, and token refresh.
type AuthService struct {
	userRepo *repository.UserRepository
	cfg      *config.Config
}

func NewAuthService(userRepo *repository.UserRepository, cfg *config.Config) *AuthService {
	return &AuthService{userRepo: userRepo, cfg: cfg}
}

// Register validates inputs, hashes the password, persists the user, and returns a token pair.
func (s *AuthService) Register(ctx context.Context, username, email, password string) (*TokenPair, error) {
	if !usernameRe.MatchString(username) {
		return nil, ErrInvalidUsername
	}
	if !emailRe.MatchString(email) {
		return nil, ErrInvalidEmail
	}
	if err := validatePassword(password); err != nil {
		return nil, err
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return nil, fmt.Errorf("bcrypt: %w", err)
	}

	user, err := s.userRepo.CreateUser(ctx, username, email, string(hash))
	if err != nil {
		var pqErr *pq.Error
		if errors.As(err, &pqErr) && pqErr.Code == "23505" {
			return nil, ErrUserExists
		}
		return nil, fmt.Errorf("Register: %w", err)
	}

	return s.generateTokenPair(user.ID, user.Username)
}

// Login verifies credentials and returns a fresh token pair.
func (s *AuthService) Login(ctx context.Context, email, password string) (*TokenPair, error) {
	user, err := s.userRepo.GetUserByEmail(ctx, email)
	if errors.Is(err, repository.ErrUserNotFound) {
		return nil, ErrInvalidCredentials
	}
	if err != nil {
		return nil, fmt.Errorf("Login: %w", err)
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(password)); err != nil {
		return nil, ErrInvalidCredentials
	}

	return s.generateTokenPair(user.ID, user.Username)
}

// RefreshToken validates a refresh token and returns a new token pair.
func (s *AuthService) RefreshToken(ctx context.Context, rawToken string) (*TokenPair, error) {
	c, err := s.parseToken(rawToken)
	if err != nil || c.Type != "refresh" {
		return nil, ErrInvalidToken
	}

	// Verify user still exists.
	user, err := s.userRepo.GetUserByID(ctx, c.UserID)
	if err != nil {
		return nil, ErrInvalidToken
	}

	return s.generateTokenPair(user.ID, user.Username)
}

func (s *AuthService) generateTokenPair(userID, username string) (*TokenPair, error) {
	now := time.Now()

	access, err := s.sign(&claims{
		UserID:   userID,
		Username: username,
		Type:     "access",
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   userID,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(s.cfg.JWTAccessTTL)),
		},
	})
	if err != nil {
		return nil, fmt.Errorf("sign access token: %w", err)
	}

	refresh, err := s.sign(&claims{
		UserID:   userID,
		Username: username,
		Type:     "refresh",
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   userID,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(s.cfg.JWTRefreshTTL)),
		},
	})
	if err != nil {
		return nil, fmt.Errorf("sign refresh token: %w", err)
	}

	return &TokenPair{AccessToken: access, RefreshToken: refresh}, nil
}

func (s *AuthService) sign(c *claims) (string, error) {
	return jwt.NewWithClaims(jwt.SigningMethodHS256, c).SignedString([]byte(s.cfg.JWTSecret))
}

// ParseAccessToken parses and validates an access token, returning (userID, username, error).
func (s *AuthService) ParseAccessToken(raw string) (string, string, error) {
	c, err := s.parseToken(raw)
	if err != nil || c.Type != "access" {
		return "", "", ErrInvalidToken
	}
	return c.UserID, c.Username, nil
}

func (s *AuthService) parseToken(raw string) (*claims, error) {
	tok, err := jwt.ParseWithClaims(raw, &claims{}, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, ErrInvalidToken
		}
		return []byte(s.cfg.JWTSecret), nil
	})
	if err != nil || !tok.Valid {
		return nil, ErrInvalidToken
	}
	c, ok := tok.Claims.(*claims)
	if !ok {
		return nil, ErrInvalidToken
	}
	return c, nil
}

// validatePassword enforces: min 8 chars, ≥1 letter, ≥1 digit.
func validatePassword(p string) error {
	if len(p) < 8 {
		return ErrWeakPassword
	}
	var hasLetter, hasDigit bool
	for _, r := range p {
		if unicode.IsLetter(r) {
			hasLetter = true
		}
		if unicode.IsDigit(r) {
			hasDigit = true
		}
	}
	if !hasLetter || !hasDigit {
		return ErrWeakPassword
	}
	return nil
}
