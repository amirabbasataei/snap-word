package service

import (
	"context"
	"fmt"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/repository"
)

// ErrInsufficientCoins means the player cannot afford the match entry fee.
var ErrInsufficientCoins = repository.ErrInsufficientCoins

// ensureCanAffordEntry rejects a banned player and one whose balance is below
// the entry fee.
// It is a fast pre-check; the authoritative charge happens when the match
// starts (ws.Room.chargeEntryFees).
func ensureCanAffordEntry(ctx context.Context, userRepo *repository.UserRepository, userID string) error {
	user, err := userRepo.GetUserByID(ctx, userID)
	if err != nil {
		return fmt.Errorf("ensureCanAffordEntry: %w", err)
	}
	if user.BannedAt != nil {
		return ErrAccountBanned
	}
	if user.Coins < config.EntryFeeCoins {
		return ErrInsufficientCoins
	}
	return nil
}
