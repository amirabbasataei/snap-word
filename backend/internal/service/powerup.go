package service

import (
	"context"
	"errors"
	"fmt"

	"wordchain/backend/internal/repository"
)

var (
	ErrInsufficientPowerup = errors.New("insufficient_powerup")
	ErrInvalidPowerupType  = errors.New("invalid_powerup_type")
)

var validPowerupTypes = map[string]struct{}{
	"hint":       {},
	"freeze":     {},
	"extra_time": {},
	"shield":     {},
}

// PowerupService handles inventory queries and usage.
type PowerupService struct {
	powerupRepo *repository.PowerupRepository
}

func NewPowerupService(powerupRepo *repository.PowerupRepository) *PowerupService {
	return &PowerupService{powerupRepo: powerupRepo}
}

func (s *PowerupService) GetInventory(ctx context.Context, userID string) ([]*repository.PowerupItem, error) {
	items, err := s.powerupRepo.GetInventory(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("GetInventory: %w", err)
	}
	return items, nil
}

// UseItem deducts one powerup from inventory and returns the remaining quantity.
func (s *PowerupService) UseItem(ctx context.Context, userID, powerupType string) (int, error) {
	if _, ok := validPowerupTypes[powerupType]; !ok {
		return 0, ErrInvalidPowerupType
	}

	remaining, err := s.powerupRepo.DeductOne(ctx, userID, powerupType)
	if errors.Is(err, repository.ErrInsufficientPowerup) {
		return 0, ErrInsufficientPowerup
	}
	if err != nil {
		return 0, fmt.Errorf("UseItem: %w", err)
	}
	return remaining, nil
}
