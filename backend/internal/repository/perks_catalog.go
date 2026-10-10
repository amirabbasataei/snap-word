package repository

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

// ErrCatalogItemNotFound is returned when a taunt or avatar id does not exist.
var ErrCatalogItemNotFound = errors.New("catalog item not found")

type Taunt struct {
	ID        string
	Text      string
	SortOrder int
}

// Avatar is the catalogue entry without its image bytes.
type Avatar struct {
	ID        string
	SortOrder int
	UpdatedAt time.Time
}

type AvatarImage struct {
	Data        []byte
	ContentType string
	UpdatedAt   time.Time
}

// CatalogRepository stores the premium taunt and avatar catalogues.
type CatalogRepository struct {
	db *sql.DB
}

func NewCatalogRepository(db *sql.DB) *CatalogRepository {
	return &CatalogRepository{db: db}
}

func (r *CatalogRepository) ListTaunts(ctx context.Context) ([]Taunt, error) {
	rows, err := r.db.QueryContext(ctx, `SELECT id, text, sort_order FROM taunts ORDER BY sort_order, created_at, id`)
	if err != nil {
		return nil, fmt.Errorf("ListTaunts: %w", err)
	}
	defer rows.Close()
	var out []Taunt
	for rows.Next() {
		var t Taunt
		if err := rows.Scan(&t.ID, &t.Text, &t.SortOrder); err != nil {
			return nil, fmt.Errorf("ListTaunts scan: %w", err)
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

// UpsertTaunt inserts or updates a taunt. A nil sortOrder appends a new taunt
// at the end and leaves an existing one where it is.
func (r *CatalogRepository) UpsertTaunt(ctx context.Context, id, text string, sortOrder *int) error {
	_, err := r.db.ExecContext(ctx, `
		INSERT INTO taunts (id, text, sort_order)
		VALUES ($1, $2, COALESCE($3::int, (SELECT COALESCE(MAX(sort_order), 0) + 1 FROM taunts)))
		ON CONFLICT (id) DO UPDATE
		SET text = EXCLUDED.text,
		    sort_order = COALESCE($3::int, taunts.sort_order)`,
		id, text, nullableInt(sortOrder))
	if err != nil {
		return fmt.Errorf("UpsertTaunt: %w", err)
	}
	return nil
}

func (r *CatalogRepository) DeleteTaunt(ctx context.Context, id string) error {
	res, err := r.db.ExecContext(ctx, `DELETE FROM taunts WHERE id = $1`, id)
	if err != nil {
		return fmt.Errorf("DeleteTaunt: %w", err)
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrCatalogItemNotFound
	}
	return nil
}

func (r *CatalogRepository) ListAvatars(ctx context.Context) ([]Avatar, error) {
	rows, err := r.db.QueryContext(ctx, `SELECT id, sort_order, updated_at FROM avatars ORDER BY sort_order, created_at, id`)
	if err != nil {
		return nil, fmt.Errorf("ListAvatars: %w", err)
	}
	defer rows.Close()
	var out []Avatar
	for rows.Next() {
		var a Avatar
		if err := rows.Scan(&a.ID, &a.SortOrder, &a.UpdatedAt); err != nil {
			return nil, fmt.Errorf("ListAvatars scan: %w", err)
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

// UpsertAvatar inserts or replaces an avatar image (sortOrder as in UpsertTaunt).
func (r *CatalogRepository) UpsertAvatar(ctx context.Context, id string, data []byte, contentType string, sortOrder *int) error {
	_, err := r.db.ExecContext(ctx, `
		INSERT INTO avatars (id, image, content_type, sort_order)
		VALUES ($1, $2, $3, COALESCE($4::int, (SELECT COALESCE(MAX(sort_order), 0) + 1 FROM avatars)))
		ON CONFLICT (id) DO UPDATE
		SET image = EXCLUDED.image,
		    content_type = EXCLUDED.content_type,
		    sort_order = COALESCE($4::int, avatars.sort_order),
		    updated_at = now()`,
		id, data, contentType, nullableInt(sortOrder))
	if err != nil {
		return fmt.Errorf("UpsertAvatar: %w", err)
	}
	return nil
}

// DeleteAvatar removes an avatar and clears it from every user who had picked it.
func (r *CatalogRepository) DeleteAvatar(ctx context.Context, id string) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("DeleteAvatar begin: %w", err)
	}
	defer tx.Rollback()

	res, err := tx.ExecContext(ctx, `DELETE FROM avatars WHERE id = $1`, id)
	if err != nil {
		return fmt.Errorf("DeleteAvatar: %w", err)
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrCatalogItemNotFound
	}
	if _, err := tx.ExecContext(ctx, `UPDATE users SET avatar_id = NULL WHERE avatar_id = $1`, id); err != nil {
		return fmt.Errorf("DeleteAvatar clear users: %w", err)
	}
	return tx.Commit()
}

func (r *CatalogRepository) GetAvatarImage(ctx context.Context, id string) (*AvatarImage, error) {
	var img AvatarImage
	err := r.db.QueryRowContext(ctx,
		`SELECT image, content_type, updated_at FROM avatars WHERE id = $1`, id,
	).Scan(&img.Data, &img.ContentType, &img.UpdatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrCatalogItemNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("GetAvatarImage: %w", err)
	}
	return &img, nil
}

func nullableInt(v *int) sql.NullInt32 {
	if v == nil {
		return sql.NullInt32{}
	}
	return sql.NullInt32{Int32: int32(*v), Valid: true}
}
