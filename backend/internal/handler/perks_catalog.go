package handler

import (
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/middleware"
	"wordchain/backend/internal/service"
)

// CatalogHandler serves the premium taunt/avatar catalogues to players and lets
// operators add and remove entries (admin routes, X-Admin-Key).
type CatalogHandler struct {
	svc   *service.CatalogService
	audit *service.AuditService
}

func NewCatalogHandler(svc *service.CatalogService, audit *service.AuditService) *CatalogHandler {
	return &CatalogHandler{svc: svc, audit: audit}
}

// record appends an audit row for a catalogue change that just succeeded.
func (h *CatalogHandler) record(c *gin.Context, action, targetType, id string, payload any) {
	h.audit.LogRecord(c.Request.Context(), middleware.AdminActor(c), action, service.AuditTarget{Type: targetType, ID: id}, payload)
}

// Get handles GET /api/v1/perks/catalog (public, ordered as the picker shows them).
func (h *CatalogHandler) Get(c *gin.Context) {
	taunts, err := h.svc.Taunts(c.Request.Context())
	if err != nil {
		slog.Error("perks catalog failed", "error", err)
		respondError(c, http.StatusInternalServerError, "internal_error", "failed to load catalog")
		return
	}
	avatars, err := h.svc.Avatars(c.Request.Context())
	if err != nil {
		slog.Error("perks catalog failed", "error", err)
		respondError(c, http.StatusInternalServerError, "internal_error", "failed to load catalog")
		return
	}
	type tauntOut struct {
		ID   string `json:"id"`
		Text string `json:"text"`
	}
	type avatarOut struct {
		ID string `json:"id"`
	}
	out := struct {
		Taunts  []tauntOut  `json:"taunts"`
		Avatars []avatarOut `json:"avatars"`
	}{Taunts: []tauntOut{}, Avatars: []avatarOut{}}
	for _, t := range taunts {
		out.Taunts = append(out.Taunts, tauntOut{ID: t.ID, Text: t.Text})
	}
	for _, a := range avatars {
		out.Avatars = append(out.Avatars, avatarOut{ID: a.ID})
	}
	c.JSON(http.StatusOK, gin.H{"data": out})
}

// AvatarImage handles GET /api/v1/avatars/:id/image (public; the client loads
// it with a plain image request).
func (h *CatalogHandler) AvatarImage(c *gin.Context) {
	img, err := h.svc.AvatarImage(c.Request.Context(), c.Param("id"))
	switch {
	case errors.Is(err, service.ErrCatalogNotFound):
		respondError(c, http.StatusNotFound, "avatar_not_found", "unknown avatar")
		return
	case err != nil:
		slog.Error("avatar image failed", "id", c.Param("id"), "error", err)
		respondError(c, http.StatusInternalServerError, "internal_error", "failed to load avatar")
		return
	}
	etag := `"` + strconv.FormatInt(img.UpdatedAt.UnixNano(), 36) + `"`
	c.Header("ETag", etag)
	c.Header("Cache-Control", "public, max-age=86400")
	if c.GetHeader("If-None-Match") == etag {
		c.Status(http.StatusNotModified)
		return
	}
	c.Data(http.StatusOK, img.ContentType, img.Data)
}

// adminError is the operator-facing error envelope. These codes are English on
// purpose: they never reach a player, so they stay out of error_messages.dart.
func adminError(c *gin.Context, status int, code, message string) {
	c.JSON(status, gin.H{"error": gin.H{"code": code, "message": message}})
}

// catalogReason validates the audit reason of a catalogue change. Panel
// sessions must give one; the X-Admin-Key script (perks_admin.sh) may omit it.
func catalogReason(c *gin.Context, raw string) (string, bool) {
	reason, err := service.ReasonFor(middleware.AdminActor(c), raw)
	if err != nil {
		adminError(c, http.StatusBadRequest, "reason_required",
			"a reason of "+strconv.Itoa(service.AdminReasonMinRunes)+"-"+strconv.Itoa(service.AdminReasonMaxRunes)+" characters is required")
		return "", false
	}
	return reason, true
}

func (h *CatalogHandler) adminResult(c *gin.Context, action string, id string, err error) {
	switch {
	case err == nil:
		c.JSON(http.StatusOK, gin.H{"data": gin.H{"id": id}})
	case errors.Is(err, service.ErrInvalidCatalogID):
		adminError(c, http.StatusBadRequest, "invalid_id", "id must be lowercase letters, digits or _, starting with a letter")
	case errors.Is(err, service.ErrInvalidTauntText):
		adminError(c, http.StatusBadRequest, "invalid_text", "text must be 1-"+strconv.Itoa(config.TauntMaxTextRunes)+" characters")
	case errors.Is(err, service.ErrInvalidImage):
		adminError(c, http.StatusBadRequest, "invalid_image", "image must be a PNG, JPEG or WebP of at most "+strconv.Itoa(config.AvatarMaxBytes)+" bytes")
	case errors.Is(err, service.ErrCatalogNotFound):
		adminError(c, http.StatusNotFound, "not_found", "no such entry")
	case errors.Is(err, service.ErrCatalogChanged):
		adminError(c, http.StatusConflict, "catalog_changed", "the catalogue changed since the list was loaded")
	default:
		slog.Error("catalog admin failed", "action", action, "id", id, "error", err)
		adminError(c, http.StatusInternalServerError, "internal_error", "failed to "+action)
	}
}

// optionalSortOrder parses an optional integer; ok is false on a malformed value.
func optionalSortOrder(raw string) (order *int, ok bool) {
	if raw == "" {
		return nil, true
	}
	n, err := strconv.Atoi(raw)
	if err != nil {
		return nil, false
	}
	return &n, true
}

// PutTaunt handles PUT /api/v1/admin/taunts/:id with {"text": "...", "sort_order": 3, "reason": "..."}.
func (h *CatalogHandler) PutTaunt(c *gin.Context) {
	var req struct {
		Text      string `json:"text"`
		SortOrder *int   `json:"sort_order"`
		Reason    string `json:"reason"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		adminError(c, http.StatusBadRequest, "validation_error", err.Error())
		return
	}
	reason, ok := catalogReason(c, req.Reason)
	if !ok {
		return
	}
	id := c.Param("id")
	ctx := c.Request.Context()
	// Best effort: the audit row shows what was overwritten.
	var before gin.H
	if old, err := h.svc.Taunt(ctx, id); err == nil {
		before = gin.H{"text": old.Text, "sort_order": old.SortOrder}
	}
	err := h.svc.SaveTaunt(ctx, id, req.Text, req.SortOrder)
	if err == nil {
		h.record(c, "taunt.save", "taunt", id, gin.H{
			"text": strings.TrimSpace(req.Text), "sort_order": req.SortOrder, "created": before == nil, "before": before, "reason": reason,
		})
	}
	h.adminResult(c, "save taunt", id, err)
}

type reasonOnly struct {
	Reason string `json:"reason"`
}

// bindOptionalReason reads {"reason": "..."} from a DELETE/POST body; an empty
// body is fine (the key-authenticated script sends none).
func bindOptionalReason(c *gin.Context) (string, bool) {
	var body reasonOnly
	if c.Request.ContentLength != 0 {
		if err := c.ShouldBindJSON(&body); err != nil {
			adminError(c, http.StatusBadRequest, "validation_error", "request body is not valid JSON of the expected shape")
			return "", false
		}
	}
	return catalogReason(c, body.Reason)
}

func (h *CatalogHandler) DeleteTaunt(c *gin.Context) {
	reason, ok := bindOptionalReason(c)
	if !ok {
		return
	}
	id := c.Param("id")
	ctx := c.Request.Context()
	var before gin.H
	if old, err := h.svc.Taunt(ctx, id); err == nil {
		before = gin.H{"text": old.Text, "sort_order": old.SortOrder}
	}
	err := h.svc.DeleteTaunt(ctx, id)
	if err == nil {
		h.record(c, "taunt.delete", "taunt", id, gin.H{"before": before, "reason": reason})
	}
	h.adminResult(c, "delete taunt", id, err)
}

// ReorderTaunts handles POST /api/v1/admin/taunts/reorder with {"ids": [...], "reason": "..."}:
// the new picker order, which must list every taunt exactly once.
func (h *CatalogHandler) ReorderTaunts(c *gin.Context) {
	var req struct {
		IDs    []string `json:"ids"`
		Reason string   `json:"reason"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || len(req.IDs) == 0 {
		adminError(c, http.StatusBadRequest, "validation_error", "ids must be a non-empty list of taunt ids")
		return
	}
	reason, ok := catalogReason(c, req.Reason)
	if !ok {
		return
	}
	err := h.svc.ReorderTaunts(c.Request.Context(), req.IDs)
	if err == nil {
		h.record(c, "taunt.reorder", "taunt", "", gin.H{"ids": req.IDs, "reason": reason})
	}
	h.adminResult(c, "reorder taunts", "", err)
}

// PutAvatar handles PUT /api/v1/admin/avatars/:id as multipart/form-data with
// an `image` file and optional `sort_order` and `reason` fields.
func (h *CatalogHandler) PutAvatar(c *gin.Context) {
	order, ok := optionalSortOrder(c.PostForm("sort_order"))
	if !ok {
		adminError(c, http.StatusBadRequest, "validation_error", "sort_order must be an integer")
		return
	}
	reason, ok := catalogReason(c, c.PostForm("reason"))
	if !ok {
		return
	}
	fh, err := c.FormFile("image")
	if err != nil {
		adminError(c, http.StatusBadRequest, "validation_error", "multipart field `image` is required")
		return
	}
	f, err := fh.Open()
	if err != nil {
		adminError(c, http.StatusBadRequest, "validation_error", "cannot read image")
		return
	}
	defer f.Close()
	// Read one byte past the cap so an oversized upload is rejected, not truncated.
	data, err := io.ReadAll(io.LimitReader(f, int64(config.AvatarMaxBytes)+1))
	if err != nil {
		adminError(c, http.StatusBadRequest, "validation_error", "cannot read image")
		return
	}
	id := c.Param("id")
	err = h.svc.SaveAvatar(c.Request.Context(), id, data, order)
	if err == nil {
		h.record(c, "avatar.save", "avatar", id, gin.H{"bytes": len(data), "sort_order": order, "reason": reason})
	}
	h.adminResult(c, "save avatar", id, err)
}

func (h *CatalogHandler) DeleteAvatar(c *gin.Context) {
	reason, ok := bindOptionalReason(c)
	if !ok {
		return
	}
	id := c.Param("id")
	cleared, err := h.svc.DeleteAvatar(c.Request.Context(), id)
	if err == nil {
		h.record(c, "avatar.delete", "avatar", id, gin.H{"users_cleared": cleared, "reason": reason})
		c.JSON(http.StatusOK, gin.H{"data": gin.H{"id": id, "users_cleared": cleared}})
		return
	}
	h.adminResult(c, "delete avatar", id, err)
}
