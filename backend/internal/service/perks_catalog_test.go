package service

import (
	"bytes"
	"context"
	"errors"
	"strings"
	"testing"

	"wordchain/backend/internal/config"
)

// pngHeader is enough for http.DetectContentType to report image/png.
var pngHeader = []byte{0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0}

// Validation runs before the repository is touched, so a nil repo is safe for
// every case that must be rejected.
func TestSaveTauntValidation(t *testing.T) {
	s := NewCatalogService(nil)
	ctx := context.Background()
	cases := []struct {
		name, id, text string
		want           error
	}{
		{"uppercase id", "Hurry", "زود باش", ErrInvalidCatalogID},
		{"id with space", "hurry up", "زود باش", ErrInvalidCatalogID},
		{"id too short", "a", "زود باش", ErrInvalidCatalogID},
		{"id starts with digit", "1abc", "زود باش", ErrInvalidCatalogID},
		{"empty text", "hurry_up", "   ", ErrInvalidTauntText},
		{"text too long", "hurry_up", strings.Repeat("ا", config.TauntMaxTextRunes+1), ErrInvalidTauntText},
	}
	for _, tc := range cases {
		if err := s.SaveTaunt(ctx, tc.id, tc.text, nil); !errors.Is(err, tc.want) {
			t.Errorf("%s: got %v, want %v", tc.name, err, tc.want)
		}
	}
}

func TestSaveAvatarValidation(t *testing.T) {
	s := NewCatalogService(nil)
	ctx := context.Background()
	cases := []struct {
		name, id string
		data     []byte
		want     error
	}{
		{"bad id", "Lion!", pngHeader, ErrInvalidCatalogID},
		{"id longer than the column", strings.Repeat("a", 25), pngHeader, ErrInvalidCatalogID},
		{"empty image", "lion", nil, ErrInvalidImage},
		{"oversized image", "lion", append(bytes.Clone(pngHeader), make([]byte, config.AvatarMaxBytes)...), ErrInvalidImage},
		{"not an image", "lion", []byte("<html>not an image</html>"), ErrInvalidImage},
		{"gif is not allowed", "lion", []byte("GIF89a\x01\x00\x01\x00"), ErrInvalidImage},
	}
	for _, tc := range cases {
		if err := s.SaveAvatar(ctx, tc.id, tc.data, nil); !errors.Is(err, tc.want) {
			t.Errorf("%s: got %v, want %v", tc.name, err, tc.want)
		}
	}
}
