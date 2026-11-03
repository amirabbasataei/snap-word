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

// PurchaseService verifies Cafe Bazaar receipts and delivers the purchase.
type PurchaseService struct {
	repo  *repository.PurchaseRepository
	store BazaarVerifier
	now   func() time.Time
}

func NewPurchaseService(repo *repository.PurchaseRepository, store BazaarVerifier) *PurchaseService {
	return &PurchaseService{repo: repo, store: store, now: time.Now}
}

// VerifyBazaar checks the RSA-signed receipt Bazaar gave the app (signedData is
// the exact JSON string, signature its base64 signature) and delivers the
// product. Safe to repeat: coin packs credit once per purchase token,
// subscriptions only ever extend.
func (s *PurchaseService) VerifyBazaar(ctx context.Context, userID, productID, signedData, signature string) (*PurchaseResult, error) {
	product, ok := config.StoreProducts[productID]
	if !ok {
		return nil, ErrUnknownProduct
	}
	if !s.store.Configured() {
		return nil, ErrPaymentsUnavailable
	}
	rc, err := s.store.VerifyReceipt(signedData, signature)
	if err != nil {
		return nil, err
	}
	token := strings.TrimSpace(rc.Token)
	// The signed receipt, not the request, says what was bought.
	if rc.ProductID != productID || token == "" || len(token) > 512 || !rc.Purchased {
		return nil, ErrPurchaseInvalid
	}
	// The client sets the payload to the account id: a receipt bought while
	// signed in as someone else is not redeemable here.
	if rc.Payload != "" && rc.Payload != userID {
		return nil, ErrPurchaseWrongRecipient
	}

	switch product.Kind {
	case config.StoreProductCoins:
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
		// The receipt has no expiry. The app only reports subscriptions Bazaar
		// still lists as active, so premium runs a short window past each
		// report (see config.PremiumReverifyWindow).
		until, err := s.repo.ApplyPremium(ctx, config.StoreBazaar, token, userID, productID, s.now().Add(config.PremiumReverifyWindow))
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
