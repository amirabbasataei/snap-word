package service

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"regexp"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/repository"
)

var (
	ErrInvalidCatalogID = errors.New("invalid_id")
	ErrInvalidTauntText = errors.New("invalid_text")
	ErrInvalidImage     = errors.New("invalid_image")
	ErrCatalogNotFound  = repository.ErrCatalogItemNotFound
	ErrCatalogChanged   = repository.ErrCatalogChanged

	tauntIDRe  = regexp.MustCompile(`^[a-z][a-z0-9_]{1,31}$`)
	avatarIDRe = regexp.MustCompile(`^[a-z][a-z0-9_]{1,23}$`)

	allowedImageTypes = map[string]bool{"image/png": true, "image/jpeg": true, "image/webp": true}
)

// catalogCacheTTL bounds how stale another process' (or a manual SQL) edit can
// look; edits made through this service invalidate the cache immediately.
const catalogCacheTTL = 30 * time.Second

// CatalogService manages the premium taunt and avatar catalogues. Reads (the
// hot path: every taunt send, every avatar pick) are served from a short-lived
// in-memory copy.
type CatalogService struct {
	repo *repository.CatalogRepository

	mu        sync.RWMutex
	loadedAt  time.Time
	taunts    []repository.Taunt
	tauntByID map[string]string
	avatars   []repository.Avatar
	avatarIDs map[string]bool
}

func NewCatalogService(repo *repository.CatalogRepository) *CatalogService {
	return &CatalogService{repo: repo}
}

func (s *CatalogService) ensureLoaded(ctx context.Context) error {
	s.mu.RLock()
	fresh := time.Since(s.loadedAt) < catalogCacheTTL
	s.mu.RUnlock()
	if fresh {
		return nil
	}

	taunts, err := s.repo.ListTaunts(ctx)
	if err == nil {
		var avatars []repository.Avatar
		if avatars, err = s.repo.ListAvatars(ctx); err == nil {
			byID := make(map[string]string, len(taunts))
			for _, t := range taunts {
				byID[t.ID] = t.Text
			}
			ids := make(map[string]bool, len(avatars))
			for _, a := range avatars {
				ids[a.ID] = true
			}
			s.mu.Lock()
			s.taunts, s.tauntByID, s.avatars, s.avatarIDs = taunts, byID, avatars, ids
			s.loadedAt = time.Now()
			s.mu.Unlock()
			return nil
		}
	}

	// Keep serving the previous copy through a DB blip.
	s.mu.RLock()
	hadData := !s.loadedAt.IsZero()
	s.mu.RUnlock()
	if hadData {
		slog.Warn("perks catalog: refresh failed, serving stale copy", "error", err)
		return nil
	}
	return fmt.Errorf("perks catalog load: %w", err)
}

func (s *CatalogService) invalidate() {
	s.mu.Lock()
	s.loadedAt = time.Time{}
	s.mu.Unlock()
}

func (s *CatalogService) Taunts(ctx context.Context) ([]repository.Taunt, error) {
	if err := s.ensureLoaded(ctx); err != nil {
		return nil, err
	}
	s.mu.RLock()
	defer s.mu.RUnlock()
	return append([]repository.Taunt(nil), s.taunts...), nil
}

func (s *CatalogService) Avatars(ctx context.Context) ([]repository.Avatar, error) {
	if err := s.ensureLoaded(ctx); err != nil {
		return nil, err
	}
	s.mu.RLock()
	defer s.mu.RUnlock()
	return append([]repository.Avatar(nil), s.avatars...), nil
}

// TauntText returns the Persian text of a taunt, and false for an unknown id
// (or when the catalogue cannot be read).
func (s *CatalogService) TauntText(ctx context.Context, id string) (string, bool) {
	if err := s.ensureLoaded(ctx); err != nil {
		slog.Error("perks catalog unavailable", "error", err)
		return "", false
	}
	s.mu.RLock()
	defer s.mu.RUnlock()
	text, ok := s.tauntByID[id]
	return text, ok
}

func (s *CatalogService) AvatarExists(ctx context.Context, id string) bool {
	if err := s.ensureLoaded(ctx); err != nil {
		slog.Error("perks catalog unavailable", "error", err)
		return false
	}
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.avatarIDs[id]
}

func (s *CatalogService) AvatarImage(ctx context.Context, id string) (*repository.AvatarImage, error) {
	return s.repo.GetAvatarImage(ctx, id)
}

// SaveTaunt creates or updates a taunt. Text is plain Persian (emoji allowed);
// it is shown to the opponent verbatim, so it is length-limited and trimmed.
func (s *CatalogService) SaveTaunt(ctx context.Context, id, text string, sortOrder *int) error {
	if !tauntIDRe.MatchString(id) {
		return ErrInvalidCatalogID
	}
	text = strings.TrimSpace(text)
	if n := utf8.RuneCountInString(text); n == 0 || n > config.TauntMaxTextRunes {
		return ErrInvalidTauntText
	}
	if err := s.repo.UpsertTaunt(ctx, id, text, sortOrder); err != nil {
		return err
	}
	s.invalidate()
	return nil
}

// Taunt reads one taunt uncached, for the audit trail's "before" value.
func (s *CatalogService) Taunt(ctx context.Context, id string) (*repository.Taunt, error) {
	return s.repo.GetTaunt(ctx, id)
}

// ReorderTaunts sets the picker order to ids (which must be every taunt once).
func (s *CatalogService) ReorderTaunts(ctx context.Context, ids []string) error {
	if err := s.repo.ReorderTaunts(ctx, ids); err != nil {
		return err
	}
	s.invalidate()
	return nil
}

func (s *CatalogService) DeleteTaunt(ctx context.Context, id string) error {
	if err := s.repo.DeleteTaunt(ctx, id); err != nil {
		return err
	}
	s.invalidate()
	return nil
}

// SaveAvatar creates or replaces an avatar. The image type is sniffed from the
// bytes (never trusted from the upload) and the size capped.
func (s *CatalogService) SaveAvatar(ctx context.Context, id string, data []byte, sortOrder *int) error {
	if !avatarIDRe.MatchString(id) {
		return ErrInvalidCatalogID
	}
	if len(data) == 0 || len(data) > config.AvatarMaxBytes {
		return ErrInvalidImage
	}
	contentType := http.DetectContentType(data)
	if !allowedImageTypes[contentType] {
		return ErrInvalidImage
	}
	if err := s.repo.UpsertAvatar(ctx, id, data, contentType, sortOrder); err != nil {
		return err
	}
	s.invalidate()
	return nil
}

// DeleteAvatar removes an avatar and returns how many users had it picked
// (their avatar is cleared in the same transaction).
func (s *CatalogService) DeleteAvatar(ctx context.Context, id string) (int, error) {
	cleared, err := s.repo.DeleteAvatar(ctx, id)
	if err != nil {
		return 0, err
	}
	s.invalidate()
	return cleared, nil
}
