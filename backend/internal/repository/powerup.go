package repository

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

var ErrInsufficientPowerup = errors.New("insufficient_powerup")

type PowerupItem struct {
	PowerupType string
	Quantity    int
}

type PowerupRepository struct {
	db *sql.DB
}

func NewPowerupRepository(db *sql.DB) *PowerupRepository {
	return &PowerupRepository{db: db}
}

func (r *PowerupRepository) GetInventory(ctx context.Context, userID string) ([]*PowerupItem, error) {
	const q = `
		SELECT powerup_type, quantity
		FROM powerup_inventory
		WHERE user_id = $1
		ORDER BY powerup_type`

	rows, err := r.db.QueryContext(ctx, q, userID)
	if err != nil {
		return nil, fmt.Errorf("GetInventory: %w", err)
	}
	defer rows.Close()

	var items []*PowerupItem
	for rows.Next() {
		item := &PowerupItem{}
		if err := rows.Scan(&item.PowerupType, &item.Quantity); err != nil {
			return nil, fmt.Errorf("GetInventory scan: %w", err)
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("GetInventory rows: %w", err)
	}
	return items, nil
}

// GetItem returns a single powerup item. Returns ErrInsufficientPowerup if the row does not exist.
func (r *PowerupRepository) GetItem(ctx context.Context, userID, powerupType string) (*PowerupItem, error) {
	const q = `SELECT powerup_type, quantity FROM powerup_inventory WHERE user_id = $1 AND powerup_type = $2`

	item := &PowerupItem{}
	err := r.db.QueryRowContext(ctx, q, userID, powerupType).Scan(&item.PowerupType, &item.Quantity)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrInsufficientPowerup
	}
	if err != nil {
		return nil, fmt.Errorf("GetItem: %w", err)
	}
	return item, nil
}

// DeductOne decrements quantity by 1. Returns ErrInsufficientPowerup if quantity is already 0
// or the row does not exist.
func (r *PowerupRepository) DeductOne(ctx context.Context, userID, powerupType string) (int, error) {
	const q = `
		UPDATE powerup_inventory
		SET quantity = quantity - 1
		WHERE user_id = $1 AND powerup_type = $2 AND quantity > 0
		RETURNING quantity`

	var remaining int
	err := r.db.QueryRowContext(ctx, q, userID, powerupType).Scan(&remaining)
	if errors.Is(err, sql.ErrNoRows) {
		return 0, ErrInsufficientPowerup
	}
	if err != nil {
		return 0, fmt.Errorf("DeductOne: %w", err)
	}
	return remaining, nil
}
