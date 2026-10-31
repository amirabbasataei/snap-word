package repository

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

// ErrPurchaseOwnedByOther: the purchase token was already redeemed by another
// account.
var ErrPurchaseOwnedByOther = errors.New("purchase_owned_by_other")

// PurchaseRepository records store purchases and applies what they deliver.
type PurchaseRepository struct {
	db *sql.DB
}

func NewPurchaseRepository(db *sql.DB) *PurchaseRepository {
	return &PurchaseRepository{db: db}
}

// CreditCoins redeems a consumable coin pack exactly once. credited is false
// when this account had already redeemed the token (nothing is added).
// ErrPurchaseOwnedByOther when another account owns it. Returns the balance.
func (r *PurchaseRepository) CreditCoins(ctx context.Context, store, token, userID, productID string, coins int) (credited bool, balance int, err error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return false, 0, fmt.Errorf("CreditCoins begin: %w", err)
	}
	defer tx.Rollback() //nolint:errcheck

	var id string
	err = tx.QueryRowContext(ctx, `
		INSERT INTO store_purchases (store, purchase_token, user_id, product_id, kind, coins)
		VALUES ($1, $2, $3, $4, 'coins', $5)
		ON CONFLICT (store, purchase_token) DO NOTHING
		RETURNING id`, store, token, userID, productID, coins).Scan(&id)
	switch {
	case err == nil:
		credited = true
		if _, err = tx.ExecContext(ctx, `UPDATE users SET coins = coins + $1 WHERE id = $2`, coins, userID); err != nil {
			return false, 0, fmt.Errorf("CreditCoins credit: %w", err)
		}
	case errors.Is(err, sql.ErrNoRows):
		var owner string
		if err = tx.QueryRowContext(ctx, `SELECT user_id FROM store_purchases WHERE store = $1 AND purchase_token = $2`, store, token).Scan(&owner); err != nil {
			return false, 0, fmt.Errorf("CreditCoins owner: %w", err)
		}
		if owner != userID {
			return false, 0, ErrPurchaseOwnedByOther
		}
	default:
		return false, 0, fmt.Errorf("CreditCoins insert: %w", err)
	}

	if err = tx.QueryRowContext(ctx, `SELECT coins FROM users WHERE id = $1`, userID).Scan(&balance); err != nil {
		return false, 0, fmt.Errorf("CreditCoins balance: %w", err)
	}
	if err = tx.Commit(); err != nil {
		return false, 0, fmt.Errorf("CreditCoins commit: %w", err)
	}
	return credited, balance, nil
}

// ApplyPremium records a subscription purchase and moves users.premium_until
// forward to `until` (never backwards). The token is the same across renewals,
// so repeating the call with a later `until` simply extends it.
func (r *PurchaseRepository) ApplyPremium(ctx context.Context, store, token, userID, productID string, until time.Time) (time.Time, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return time.Time{}, fmt.Errorf("ApplyPremium begin: %w", err)
	}
	defer tx.Rollback() //nolint:errcheck

	var id string
	err = tx.QueryRowContext(ctx, `
		INSERT INTO store_purchases (store, purchase_token, user_id, product_id, kind, premium_until)
		VALUES ($1, $2, $3, $4, 'premium', $5)
		ON CONFLICT (store, purchase_token) DO UPDATE
		   SET premium_until = GREATEST(store_purchases.premium_until, EXCLUDED.premium_until),
		       updated_at = now()
		 WHERE store_purchases.user_id = EXCLUDED.user_id
		RETURNING id`, store, token, userID, productID, until).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		return time.Time{}, ErrPurchaseOwnedByOther
	}
	if err != nil {
		return time.Time{}, fmt.Errorf("ApplyPremium upsert: %w", err)
	}

	var result time.Time
	if err = tx.QueryRowContext(ctx, `
		UPDATE users
		   SET premium_until = GREATEST(COALESCE(premium_until, $2), $2)
		 WHERE id = $1
		RETURNING premium_until`, userID, until).Scan(&result); err != nil {
		return time.Time{}, fmt.Errorf("ApplyPremium user: %w", err)
	}
	if err = tx.Commit(); err != nil {
		return time.Time{}, fmt.Errorf("ApplyPremium commit: %w", err)
	}
	return result, nil
}
