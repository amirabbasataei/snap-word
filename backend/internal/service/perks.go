package service

import (
	"context"
	"errors"
	"fmt"
	"time"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/repository"
)

var (
	ErrInvalidAvatar = errors.New("invalid_avatar")
	ErrNotPremium    = repository.ErrNotPremium
)

// PerksService exposes premium status and avatar selection. Premium itself is
// granted server-side only (premium_until); no client call can set it.
type PerksService struct {
	userRepo *repository.UserRepository
}

func NewPerksService(userRepo *repository.UserRepository) *PerksService {
	return &PerksService{userRepo: userRepo}
}

// PerksStatus is what GET /profile/perks returns.
type PerksStatus struct {
	IsPremium    bool
	PremiumUntil *time.Time
	AvatarID     string
}

func (s *PerksService) Status(ctx context.Context, userID string) (*PerksStatus, error) {
	until, err := s.userRepo.GetPremiumUntil(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("perks status: %w", err)
	}
	perks, err := s.userRepo.GetPerks(ctx, []string{userID})
	if err != nil {
		return nil, fmt.Errorf("perks status: %w", err)
	}
	p := perks[userID]
	return &PerksStatus{IsPremium: p.Premium, PremiumUntil: until, AvatarID: p.AvatarID}, nil
}

// SetAvatar validates the avatar against the catalogue and stores it for an
// active premium user (ErrNotPremium otherwise).
func (s *PerksService) SetAvatar(ctx context.Context, userID, avatarID string) error {
	if !config.AvatarIDs[avatarID] {
		return ErrInvalidAvatar
	}
	return s.userRepo.SetAvatar(ctx, userID, avatarID)
}
