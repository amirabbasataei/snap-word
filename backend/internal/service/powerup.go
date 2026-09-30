package service

import (
	"context"
	"errors"
	"fmt"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/repository"
)

var (
	ErrInsufficientPowerup = errors.New("insufficient_powerup")
	ErrInvalidPowerupType  = errors.New("invalid_powerup_type")
)

// PowerupUse describes how one power-up use was paid for.
type PowerupUse struct {
	Remaining  int // inventory left for this type after the use
	CoinsSpent int // 0 when the use came out of inventory
	Coins      int // the player's coin balance after the use
}

// PowerupService handles inventory queries and usage.
type PowerupService struct {
	powerupRepo *repository.PowerupRepository
	userRepo    *repository.UserRepository
}

func NewPowerupService(powerupRepo *repository.PowerupRepository, userRepo *repository.UserRepository) *PowerupService {
	return &PowerupService{powerupRepo: powerupRepo, userRepo: userRepo}
}

func (s *PowerupService) GetInventory(ctx context.Context, userID string) ([]*repository.PowerupItem, error) {
	items, err := s.powerupRepo.GetInventory(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("GetInventory: %w", err)
	}
	return items, nil
}

// UseItem consumes one use of a power-up: from inventory when the player owns
// one, otherwise by spending config.PowerupPrice coins. Returns
// ErrInsufficientPowerup when the player has neither.
func (s *PowerupService) UseItem(ctx context.Context, userID, powerupType string) (PowerupUse, error) {
	price, ok := config.PowerupPrice(powerupType)
	if !ok {
		return PowerupUse{}, ErrInvalidPowerupType
	}

	use := PowerupUse{}
	remaining, err := s.powerupRepo.DeductOne(ctx, userID, powerupType)
	switch {
	case err == nil:
		use.Remaining = remaining
	case errors.Is(err, repository.ErrInsufficientPowerup):
		if err := s.userRepo.SpendCoins(ctx, userID, price); err != nil {
			if errors.Is(err, repository.ErrInsufficientCoins) {
				return PowerupUse{}, ErrInsufficientPowerup
			}
			return PowerupUse{}, fmt.Errorf("UseItem spend coins: %w", err)
		}
		use.CoinsSpent = price
	default:
		return PowerupUse{}, fmt.Errorf("UseItem: %w", err)
	}

	user, err := s.userRepo.GetUserByID(ctx, userID)
	if err != nil {
		return PowerupUse{}, fmt.Errorf("UseItem balance: %w", err)
	}
	use.Coins = user.Coins
	return use, nil
}
