package repository

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

// Setting is one row of app_settings.
type Setting struct {
	Value     string
	UpdatedAt time.Time
	UpdatedBy string
}

// SettingsRepository reads and writes the app_settings key/value table.
type SettingsRepository struct {
	db *sql.DB
}

func NewSettingsRepository(db *sql.DB) *SettingsRepository {
	return &SettingsRepository{db: db}
}

// Get returns the setting for key, or (nil, nil) when it has never been set.
func (r *SettingsRepository) Get(ctx context.Context, key string) (*Setting, error) {
	var s Setting
	err := r.db.QueryRowContext(ctx,
		`SELECT value, updated_at, updated_by FROM app_settings WHERE key = $1`, key,
	).Scan(&s.Value, &s.UpdatedAt, &s.UpdatedBy)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("SettingsRepository.Get %s: %w", key, err)
	}
	return &s, nil
}

// Set upserts a setting.
func (r *SettingsRepository) Set(ctx context.Context, key, value, updatedBy string) error {
	_, err := r.db.ExecContext(ctx,
		`INSERT INTO app_settings (key, value, updated_at, updated_by) VALUES ($1, $2, now(), $3)
		 ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now(), updated_by = EXCLUDED.updated_by`,
		key, value, updatedBy)
	if err != nil {
		return fmt.Errorf("SettingsRepository.Set %s: %w", key, err)
	}
	return nil
}
