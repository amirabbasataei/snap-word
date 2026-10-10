package handler

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"wordchain/backend/internal/middleware"
	"wordchain/backend/internal/service"
)

// AdminUsersHandler serves the panel's users pages. Reads are open to every
// admin role; the mutations are mounted behind RequireRole(operator) and each
// one needs a reason and writes an audit row (in the service).
type AdminUsersHandler struct {
	svc *service.AdminUserService
}

func NewAdminUsersHandler(svc *service.AdminUserService) *AdminUsersHandler {
	return &AdminUsersHandler{svc: svc}
}

// List handles GET /api/v1/admin/users?q=&filter=premium|banned|new&sort=&order=&page=&page_size=.
func (h *AdminUsersHandler) List(c *gin.Context) {
	q := service.UserListQuery{
		Q:      c.Query("q"),
		Filter: c.Query("filter"),
		Sort:   c.Query("sort"),
		Desc:   c.DefaultQuery("order", "desc") != "asc",
	}
	var ok bool
	if q.Page, ok = intQuery(c, "page"); !ok {
		return
	}
	if q.PageSize, ok = intQuery(c, "page_size"); !ok {
		return
	}
	out, err := h.svc.List(c.Request.Context(), middleware.AdminRole(c), q)
	if err != nil {
		h.fail(c, "list", "", err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": out})
}

// intQuery reads an optional integer query parameter (0 when absent).
func intQuery(c *gin.Context, name string) (int, bool) {
	raw := c.Query(name)
	if raw == "" {
		return 0, true
	}
	n, err := strconv.Atoi(raw)
	if err != nil {
		adminError(c, http.StatusBadRequest, "validation_error", name+" must be a number")
		return 0, false
	}
	return n, true
}

// Get handles GET /api/v1/admin/users/:id.
func (h *AdminUsersHandler) Get(c *gin.Context) {
	out, err := h.svc.Detail(c.Request.Context(), middleware.AdminRole(c), c.Param("id"))
	if err != nil {
		h.fail(c, "detail", c.Param("id"), err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": out})
}

type coinsBody struct {
	Mode   string `json:"mode"`
	Amount int    `json:"amount"`
	Reason string `json:"reason"`
}

// Coins handles POST /api/v1/admin/users/:id/coins.
func (h *AdminUsersHandler) Coins(c *gin.Context) {
	var body coinsBody
	if !bindBody(c, &body) {
		return
	}
	out, err := h.svc.AdjustCoins(c.Request.Context(), middleware.AdminActor(c), c.Param("id"), body.Mode, body.Amount, body.Reason)
	if err != nil {
		h.fail(c, "coins", c.Param("id"), err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": out})
}

type premiumBody struct {
	Action string `json:"action"` // grant | revoke
	Days   int    `json:"days"`
	Reason string `json:"reason"`
}

// Premium handles POST /api/v1/admin/users/:id/premium.
func (h *AdminUsersHandler) Premium(c *gin.Context) {
	var body premiumBody
	if !bindBody(c, &body) {
		return
	}
	var (
		out *service.PremiumResult
		err error
	)
	ctx, actor, id := c.Request.Context(), middleware.AdminActor(c), c.Param("id")
	switch body.Action {
	case "grant":
		out, err = h.svc.GrantPremium(ctx, actor, id, body.Days, body.Reason)
	case "revoke":
		out, err = h.svc.RevokePremium(ctx, actor, id, body.Reason)
	default:
		adminError(c, http.StatusBadRequest, "validation_error", "action must be grant or revoke")
		return
	}
	if err != nil {
		h.fail(c, "premium", id, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": out})
}

type renameBody struct {
	Username string `json:"username"`
	Reason   string `json:"reason"`
}

// Rename handles PATCH /api/v1/admin/users/:id/username.
func (h *AdminUsersHandler) Rename(c *gin.Context) {
	var body renameBody
	if !bindBody(c, &body) {
		return
	}
	username, err := h.svc.Rename(c.Request.Context(), middleware.AdminActor(c), c.Param("id"), body.Username, body.Reason)
	if err != nil {
		h.fail(c, "rename", c.Param("id"), err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": gin.H{"username": username}})
}

type reasonBody struct {
	Reason string `json:"reason"`
}

// ClearAvatar handles POST /api/v1/admin/users/:id/avatar/clear.
func (h *AdminUsersHandler) ClearAvatar(c *gin.Context) {
	h.reasoned(c, "avatar_clear", h.svc.ClearAvatar)
}

// Ban handles POST /api/v1/admin/users/:id/ban.
func (h *AdminUsersHandler) Ban(c *gin.Context) { h.reasoned(c, "ban", h.svc.Ban) }

// Unban handles POST /api/v1/admin/users/:id/unban.
func (h *AdminUsersHandler) Unban(c *gin.Context) { h.reasoned(c, "unban", h.svc.Unban) }

func (h *AdminUsersHandler) reasoned(c *gin.Context, op string, run func(ctx context.Context, actor service.AuditActor, id, reason string) error) {
	var body reasonBody
	if !bindBody(c, &body) {
		return
	}
	if err := run(c.Request.Context(), middleware.AdminActor(c), c.Param("id"), body.Reason); err != nil {
		h.fail(c, op, c.Param("id"), err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": gin.H{"id": c.Param("id")}})
}

func bindBody(c *gin.Context, dst any) bool {
	if err := c.ShouldBindJSON(dst); err != nil {
		adminError(c, http.StatusBadRequest, "validation_error", "request body is not valid JSON of the expected shape")
		return false
	}
	return true
}

// fail maps service sentinels to the operator-facing error envelope.
func (h *AdminUsersHandler) fail(c *gin.Context, op, id string, err error) {
	switch {
	case errors.Is(err, service.ErrUserNotFound):
		adminError(c, http.StatusNotFound, "user_not_found", "no such user")
	case errors.Is(err, service.ErrReasonRequired):
		adminError(c, http.StatusBadRequest, "reason_required",
			"a reason of "+strconv.Itoa(service.AdminReasonMinRunes)+"-"+strconv.Itoa(service.AdminReasonMaxRunes)+" characters is required")
	case errors.Is(err, service.ErrInvalidAmount):
		adminError(c, http.StatusBadRequest, "invalid_amount", "amount must be a non-zero whole number within ±"+strconv.Itoa(service.AdminMaxCoinAdjust)+" (positive for a gift reward)")
	case errors.Is(err, service.ErrInvalidDays):
		adminError(c, http.StatusBadRequest, "invalid_days", "days must be between 1 and "+strconv.Itoa(service.AdminMaxPremiumDays))
	case errors.Is(err, service.ErrInvalidSort), errors.Is(err, service.ErrInvalidFilter):
		adminError(c, http.StatusBadRequest, "validation_error", "unknown sort or filter")
	case errors.Is(err, service.ErrInvalidUsername):
		adminError(c, http.StatusBadRequest, "invalid_username", "username must be 3-20 letters, digits or underscores")
	case errors.Is(err, service.ErrUsernameTaken):
		adminError(c, http.StatusConflict, "username_taken", "this username is already taken")
	case errors.Is(err, service.ErrInsufficientCoins):
		adminError(c, http.StatusConflict, "insufficient_coins", "the user does not have that many coins")
	case errors.Is(err, service.ErrAlreadyBanned):
		adminError(c, http.StatusConflict, "already_banned", "the user is already banned")
	case errors.Is(err, service.ErrNotBanned):
		adminError(c, http.StatusConflict, "not_banned", "the user is not banned")
	default:
		slog.Error("admin users request failed", "op", op, "userID", id, "error", err)
		adminError(c, http.StatusInternalServerError, "internal_error", "could not complete the request")
	}
}
