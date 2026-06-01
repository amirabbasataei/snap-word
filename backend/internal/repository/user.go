package repository

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
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
