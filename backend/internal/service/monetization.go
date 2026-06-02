package service

import (
	"context"
	"errors"
	"fmt"

	"wordchain/backend/internal/repository"
)

var ErrMonetizationInsufficientCoins = errors.New("insufficient_coins")

// MonetizationService handles coin economy and IAP receipt validation.
type MonetizationService struct {
	userRepo *repository.UserRepository
}

func NewMonetizationService(userRepo *repository.UserRepository) *MonetizationService {
	return &MonetizationService{userRepo: userRepo}
}

// AwardCoins adds amount coins to the user's balance (e.g., rewarded ad, streak milestone).
func (s *MonetizationService) AwardCoins(ctx context.Context, userID string, amount int) error {
	if amount <= 0 {
		return fmt.Errorf("AwardCoins: amount must be positive, got %d", amount)
	}
	if err := s.userRepo.AwardCoins(ctx, userID, amount); err != nil {
		return fmt.Errorf("AwardCoins: %w", err)
	}
	return nil
}

// SpendCoins deducts amount coins from the user's balance atomically.
// Returns ErrMonetizationInsufficientCoins if the balance is too low.
func (s *MonetizationService) SpendCoins(ctx context.Context, userID string, amount int) error {
	if amount <= 0 {
		return fmt.Errorf("SpendCoins: amount must be positive, got %d", amount)
	}
	err := s.userRepo.SpendCoins(ctx, userID, amount)
	if errors.Is(err, repository.ErrInsufficientCoins) {
		return ErrMonetizationInsufficientCoins
	}
	if err != nil {
		return fmt.Errorf("SpendCoins: %w", err)
	}
	return nil
}

// ValidateReceipt is a stub for production Apple/Google IAP receipt validation.
// In production: call the Apple/Google receipt validation API and verify the purchase.
func (s *MonetizationService) ValidateReceipt(_ context.Context, _, _ string) error {
	return nil
}
