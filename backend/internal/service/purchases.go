package service

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/repository"
)

var (
	ErrUnknownProduct         = errors.New("unknown_product")
	ErrPurchaseOwnedByOther   = errors.New("purchase_owned_by_other")
	ErrSubscriptionExpired    = errors.New("subscription_expired")
	ErrPurchaseWrongRecipient = errors.New("purchase_wrong_recipient")
)

// PurchaseResult is what a verified purchase delivered.
type PurchaseResult struct {
	ProductID    string
	Kind         config.StoreProductKind
	CoinsAwarded int // 0 when the token had already been redeemed
	Coins        int // balance after (coin packs)
	// AlreadyProcessed: this account redeemed the token before; the client may
	// safely consume the purchase.
	AlreadyProcessed bool
	PremiumUntil     *time.Time
}

// PurchaseService verifies store purchases with Bazaar and delivers them.
type PurchaseService struct {
	repo  *repository.PurchaseRepository
	store BazaarAPI
	now   func() time.Time
}

func NewPurchaseService(repo *repository.PurchaseRepository, store BazaarAPI) *PurchaseService {
	return &PurchaseService{repo: repo, store: store, now: time.Now}
}

// VerifyBazaar checks productID/token against Bazaar and delivers the product.
// Safe to repeat: coin packs credit once per token, subscriptions only extend.
func (s *PurchaseService) VerifyBazaar(ctx context.Context, userID, productID, token string) (*PurchaseResult, error) {
	product, ok := config.StoreProducts[productID]
	if !ok {
		return nil, ErrUnknownProduct
	}
	token = strings.TrimSpace(token)
	if token == "" || len(token) > 512 {
		return nil, ErrPurchaseInvalid
	}
	if !s.store.Configured() {
		return nil, ErrPaymentsUnavailable
	}

	switch product.Kind {
	case config.StoreProductCoins:
		p, err := s.store.ValidatePurchase(ctx, productID, token)
		if err != nil {
			return nil, err
		}
		if !p.Purchased {
			return nil, ErrPurchaseInvalid
		}
		// The client sets the payload to the account id: a token bought while
		// signed in as someone else is not redeemable here.
		if p.DeveloperPayload != "" && p.DeveloperPayload != userID {
			return nil, ErrPurchaseWrongRecipient
		}
		credited, balance, err := s.repo.CreditCoins(ctx, config.StoreBazaar, token, userID, productID, product.Coins)
		if errors.Is(err, repository.ErrPurchaseOwnedByOther) {
			return nil, ErrPurchaseOwnedByOther
		}
		if err != nil {
			return nil, fmt.Errorf("VerifyBazaar credit: %w", err)
		}
		res := &PurchaseResult{ProductID: productID, Kind: product.Kind, Coins: balance, AlreadyProcessed: !credited}
		if credited {
			res.CoinsAwarded = product.Coins
			slog.Info("store purchase credited", "userID", userID, "product", productID, "coins", product.Coins)
		}
		return res, nil

	case config.StoreProductPremium:
		sub, err := s.store.ValidateSubscription(ctx, productID, token)
		if err != nil {
			return nil, err
		}
		if !sub.ValidUntil.After(s.now()) {
			return nil, ErrSubscriptionExpired
		}
		until, err := s.repo.ApplyPremium(ctx, config.StoreBazaar, token, userID, productID, sub.ValidUntil)
		if errors.Is(err, repository.ErrPurchaseOwnedByOther) {
			return nil, ErrPurchaseOwnedByOther
		}
		if err != nil {
			return nil, fmt.Errorf("VerifyBazaar premium: %w", err)
		}
		slog.Info("store subscription applied", "userID", userID, "product", productID, "until", until)
		return &PurchaseResult{ProductID: productID, Kind: product.Kind, PremiumUntil: &until}, nil
	}
	return nil, ErrUnknownProduct
}
