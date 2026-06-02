package repository

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/lib/pq"
)

var ErrUserNotFound = errors.New("user not found")

type User struct {
	ID           string
	Username     string
	Email        string
	PasswordHash string
	Coins        int
	CreatedAt    time.Time
}

type UserRepository struct {
	db *sql.DB
}

func NewUserRepository(db *sql.DB) *UserRepository {
	return &UserRepository{db: db}
}

func (r *UserRepository) CreateUser(ctx context.Context, username, email, passwordHash string) (*User, error) {
	const q = `
		INSERT INTO users (username, email, password_hash)
		VALUES ($1, $2, $3)
		RETURNING id, username, email, password_hash, coins, created_at`

	u := &User{}
	err := r.db.QueryRowContext(ctx, q, username, email, passwordHash).
		Scan(&u.ID, &u.Username, &u.Email, &u.PasswordHash, &u.Coins, &u.CreatedAt)
	if err != nil {
		return nil, fmt.Errorf("CreateUser: %w", err)
	}
	return u, nil
}

func (r *UserRepository) GetUserByEmail(ctx context.Context, email string) (*User, error) {
	const q = `
		SELECT id, username, email, password_hash, coins, created_at
		FROM users WHERE email = $1`

	u := &User{}
	err := r.db.QueryRowContext(ctx, q, email).
		Scan(&u.ID, &u.Username, &u.Email, &u.PasswordHash, &u.Coins, &u.CreatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrUserNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("GetUserByEmail: %w", err)
	}
	return u, nil
}

func (r *UserRepository) GetUserByID(ctx context.Context, id string) (*User, error) {
	const q = `
		SELECT id, username, email, password_hash, coins, created_at
		FROM users WHERE id = $1`

	u := &User{}
	err := r.db.QueryRowContext(ctx, q, id).
		Scan(&u.ID, &u.Username, &u.Email, &u.PasswordHash, &u.Coins, &u.CreatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrUserNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("GetUserByID: %w", err)
	}
	return u, nil
}

// AwardCoins atomically adds amount to a user's coin balance.
func (r *UserRepository) AwardCoins(ctx context.Context, userID string, amount int) error {
	const q = `UPDATE users SET coins = coins + $1 WHERE id = $2`
	_, err := r.db.ExecContext(ctx, q, amount, userID)
	if err != nil {
		return fmt.Errorf("AwardCoins: %w", err)
	}
	return nil
}

// GetUserByUsername returns the user with the given username.
func (r *UserRepository) GetUserByUsername(ctx context.Context, username string) (*User, error) {
	const q = `
		SELECT id, username, email, password_hash, coins, created_at
		FROM users WHERE username = $1`

	u := &User{}
	err := r.db.QueryRowContext(ctx, q, username).
		Scan(&u.ID, &u.Username, &u.Email, &u.PasswordHash, &u.Coins, &u.CreatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrUserNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("GetUserByUsername: %w", err)
	}
	return u, nil
}

// GetUsernames returns a map of userID → username for the given IDs.
// Missing IDs are silently omitted from the result.
func (r *UserRepository) GetUsernames(ctx context.Context, userIDs []string) (map[string]string, error) {
	if len(userIDs) == 0 {
		return map[string]string{}, nil
	}
	const q = `SELECT id, username FROM users WHERE id = ANY($1)`
	rows, err := r.db.QueryContext(ctx, q, pq.Array(userIDs))
	if err != nil {
		return nil, fmt.Errorf("GetUsernames: %w", err)
	}
	defer rows.Close()

	result := make(map[string]string, len(userIDs))
	for rows.Next() {
		var id, username string
		if err := rows.Scan(&id, &username); err != nil {
			return nil, fmt.Errorf("GetUsernames scan: %w", err)
		}
		result[id] = username
	}
	return result, rows.Err()
}
