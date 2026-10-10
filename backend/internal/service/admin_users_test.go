package service_test

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/service"
	"wordchain/backend/internal/testutil"
)

const (
	uidA = "11111111-1111-1111-1111-111111111111"
	uidB = "22222222-2222-2222-2222-222222222222"
)

// fakeUserStore is an in-memory adminUserStore.
type fakeUserStore struct {
	users    map[string]*repository.AdminUserRow
	lastList repository.AdminUserListParams
	calls    int // mutating calls reaching the store
	banned   map[string]bool
}

func newFakeUserStore() *fakeUserStore {
	return &fakeUserStore{
		users: map[string]*repository.AdminUserRow{
			uidA: {ID: uidA, Username: "ali_player", Phone: "09121234567", Coins: 100, XP: 1500, CreatedAt: time.Now()},
		},
		banned: map[string]bool{},
	}
}

func (f *fakeUserStore) ListUsers(_ context.Context, p repository.AdminUserListParams) ([]repository.AdminUserRow, int, error) {
	f.lastList = p
	out := []repository.AdminUserRow{}
	for _, u := range f.users {
		out = append(out, *u)
	}
	return out, len(out), nil
}

func (f *fakeUserStore) GetUserDetail(_ context.Context, id string) (*repository.AdminUserDetail, error) {
	u, ok := f.users[id]
	if !ok {
		return nil, repository.ErrAdminUserNotFound
	}
	return &repository.AdminUserDetail{AdminUserRow: *u, ReferralCode: "ABC234"}, nil
}

func (f *fakeUserStore) UserReferred(context.Context, string, int) ([]repository.AdminReferred, error) {
	return nil, nil
}
func (f *fakeUserStore) UserRewards(context.Context, string, int) ([]repository.AdminReward, error) {
	return nil, nil
}
func (f *fakeUserStore) UserMatches(context.Context, string, int) ([]repository.AdminUserMatch, error) {
	return nil, nil
}
func (f *fakeUserStore) UserDailyAttempts(context.Context, string, int) ([]repository.AdminDailyAttempt, error) {
	return nil, nil
}

func (f *fakeUserStore) AdjustCoins(_ context.Context, id string, delta int) (int, error) {
	f.calls++
	u, ok := f.users[id]
	if !ok {
		return 0, repository.ErrAdminUserNotFound
	}
	if u.Coins+delta < 0 {
		return 0, repository.ErrInsufficientCoins
	}
	u.Coins += delta
	return u.Coins, nil
}

func (f *fakeUserStore) ExtendPremium(_ context.Context, id string, days int) (time.Time, error) {
	f.calls++
	if _, ok := f.users[id]; !ok {
		return time.Time{}, repository.ErrAdminUserNotFound
	}
	until := time.Now().AddDate(0, 0, days)
	f.users[id].PremiumUntil = &until
	return until, nil
}

func (f *fakeUserStore) RevokePremium(_ context.Context, id string) error {
	f.calls++
	if _, ok := f.users[id]; !ok {
		return repository.ErrAdminUserNotFound
	}
	f.users[id].PremiumUntil = nil
	return nil
}

func (f *fakeUserStore) ClearAvatar(_ context.Context, id string) (string, error) {
	f.calls++
	if _, ok := f.users[id]; !ok {
		return "", repository.ErrAdminUserNotFound
	}
	prev := f.users[id].AvatarID
	f.users[id].AvatarID = ""
	return prev, nil
}

func (f *fakeUserStore) BanUser(_ context.Context, id, _ string) error {
	f.calls++
	if _, ok := f.users[id]; !ok {
		return repository.ErrAdminUserNotFound
	}
	if f.banned[id] {
		return repository.ErrAlreadyBanned
	}
	f.banned[id] = true
	return nil
}

func (f *fakeUserStore) UnbanUser(_ context.Context, id string) error {
	f.calls++
	if !f.banned[id] {
		return repository.ErrNotBanned
	}
	delete(f.banned, id)
	return nil
}

type fakeGranter struct {
	kind, ref string
	coins     int
	n         int
}

func (g *fakeGranter) CreateInboxReward(_ context.Context, _, kind, ref, _ string, coins int) (bool, error) {
	g.kind, g.ref, g.coins = kind, ref, coins
	g.n++
	return true, nil
}

type fakeRenamer struct {
	err error
}

func (r fakeRenamer) UpdateUsername(_ context.Context, _, username string) (string, error) {
	if r.err != nil {
		return "", r.err
	}
	return strings.TrimSpace(username), nil
}

type usersEnv struct {
	svc     *service.AdminUserService
	store   *fakeUserStore
	granter *fakeGranter
	audit   *testutil.FakeAdminStore
}

func newUsersEnv(t *testing.T, renameErr error) *usersEnv {
	t.Helper()
	store := newFakeUserStore()
	granter := &fakeGranter{}
	audit := testutil.NewFakeAdminStore()
	return &usersEnv{
		svc:     service.NewAdminUserService(store, granter, fakeRenamer{renameErr}, service.NewAuditService(audit)),
		store:   store,
		granter: granter,
		audit:   audit,
	}
}

var actor = service.AuditActor{AdminID: "admin-1", Name: "tester", IP: "127.0.0.1"}

func TestMaskPhone(t *testing.T) {
	if got := service.MaskPhone("09121234567"); got != "0912*****67" {
		t.Errorf("mask = %q", got)
	}
	if got := service.MaskPhone("123"); got != "***" {
		t.Errorf("short mask = %q", got)
	}
}

func TestAdminUsers_PhoneMaskedForNonOwners(t *testing.T) {
	e := newUsersEnv(t, nil)
	for role, want := range map[string]string{
		service.AdminRoleOwner:    "09121234567",
		service.AdminRoleOperator: "0912*****67",
		service.AdminRoleViewer:   "0912*****67",
	} {
		page, err := e.svc.List(t.Context(), role, service.UserListQuery{})
		if err != nil || page.Items[0].Phone != want {
			t.Errorf("%s list phone = %q err=%v, want %q", role, page.Items[0].Phone, err, want)
		}
		d, err := e.svc.Detail(t.Context(), role, uidA)
		if err != nil || d.Phone != want {
			t.Errorf("%s detail phone = %q err=%v, want %q", role, d.Phone, err, want)
		}
	}
}

func TestAdminUsers_PhoneSearchOwnerOnly(t *testing.T) {
	e := newUsersEnv(t, nil)
	// Persian digits are accepted and normalised for the owner...
	if _, err := e.svc.List(t.Context(), service.AdminRoleOwner, service.UserListQuery{Q: "۰۹۱۲۳۴"}); err != nil {
		t.Fatal(err)
	}
	if e.store.lastList.PhoneDigits != "091234" {
		t.Errorf("owner phone digits = %q", e.store.lastList.PhoneDigits)
	}
	// ...but never searched for anyone else (it would unmask digits).
	for _, role := range []string{service.AdminRoleOperator, service.AdminRoleViewer} {
		if _, err := e.svc.List(t.Context(), role, service.UserListQuery{Q: "091234"}); err != nil {
			t.Fatal(err)
		}
		if e.store.lastList.PhoneDigits != "" {
			t.Errorf("%s searched by phone", role)
		}
		if e.store.lastList.Query != "091234" {
			t.Errorf("%s text query lost: %q", role, e.store.lastList.Query)
		}
	}
}

func TestAdminUsers_ListValidation(t *testing.T) {
	e := newUsersEnv(t, nil)
	if _, err := e.svc.List(t.Context(), "owner", service.UserListQuery{Sort: "password"}); !errors.Is(err, service.ErrInvalidSort) {
		t.Errorf("sort: %v", err)
	}
	if _, err := e.svc.List(t.Context(), "owner", service.UserListQuery{Filter: "all"}); !errors.Is(err, service.ErrInvalidFilter) {
		t.Errorf("filter: %v", err)
	}
	page, err := e.svc.List(t.Context(), "owner", service.UserListQuery{Page: -3, PageSize: 5000})
	if err != nil || page.Page != 1 || page.PageSize != service.AdminUsersMaxPageSize {
		t.Errorf("clamp: %+v %v", page, err)
	}
	if page.Items[0].Level != 2 { // 1500 XP → level 2 (level 2 starts at 1000)
		t.Errorf("level = %d", page.Items[0].Level)
	}
}

func TestAdminUsers_MutationsNeedAReason(t *testing.T) {
	e := newUsersEnv(t, nil)
	ctx := t.Context()
	for _, reason := range []string{"", "  ", "ab"} {
		if _, err := e.svc.AdjustCoins(ctx, actor, uidA, "direct", 10, reason); !errors.Is(err, service.ErrReasonRequired) {
			t.Errorf("coins %q: %v", reason, err)
		}
		if err := e.svc.Ban(ctx, actor, uidA, reason); !errors.Is(err, service.ErrReasonRequired) {
			t.Errorf("ban %q: %v", reason, err)
		}
		if _, err := e.svc.Rename(ctx, actor, uidA, "new_name", reason); !errors.Is(err, service.ErrReasonRequired) {
			t.Errorf("rename %q: %v", reason, err)
		}
	}
	if e.store.calls != 0 || len(e.audit.Audits) != 0 {
		t.Errorf("a rejected action reached the store (%d) or the audit log (%d)", e.store.calls, len(e.audit.Audits))
	}
}

func TestAdminUsers_UnknownOrMalformedID(t *testing.T) {
	e := newUsersEnv(t, nil)
	for _, id := range []string{uidB, "not-a-uuid", "00000000-0000-0000-0000-000000000001"} {
		if _, err := e.svc.Detail(t.Context(), "owner", id); !errors.Is(err, service.ErrUserNotFound) {
			t.Errorf("detail %s: %v", id, err)
		}
		if err := e.svc.Ban(t.Context(), actor, id, "spam account"); !errors.Is(err, service.ErrUserNotFound) {
			t.Errorf("ban %s: %v", id, err)
		}
	}
}

func TestAdminUsers_DirectCoinsAudited(t *testing.T) {
	e := newUsersEnv(t, nil)
	res, err := e.svc.AdjustCoins(t.Context(), actor, uidA, "direct", -40, "refund for a bug")
	if err != nil || res.Balance == nil || *res.Balance != 60 {
		t.Fatalf("res=%+v err=%v", res, err)
	}
	if got := e.audit.AuditActions(); len(got) != 1 || got[0] != "user.coins" {
		t.Fatalf("audit = %v", got)
	}
	a := e.audit.Audits[0]
	p := a.Payload.(map[string]any)
	if a.TargetType != "user" || a.TargetID != uidA || a.Actor != "tester" ||
		p["balance_before"] != 100 || p["balance_after"] != 60 || p["reason"] != "refund for a bug" {
		t.Errorf("audit row = %+v", a)
	}
	if _, ok := p["phone"]; ok {
		t.Error("audit payload must not carry the phone number")
	}

	if _, err := e.svc.AdjustCoins(t.Context(), actor, uidA, "direct", -61, "too greedy"); !errors.Is(err, service.ErrInsufficientCoins) {
		t.Errorf("overdraw: %v", err)
	}
	if len(e.audit.Audits) != 1 {
		t.Error("a failed deduction was audited")
	}
	for _, bad := range []int{0, service.AdminMaxCoinAdjust + 1, -service.AdminMaxCoinAdjust - 1} {
		if _, err := e.svc.AdjustCoins(t.Context(), actor, uidA, "direct", bad, "bad amount"); !errors.Is(err, service.ErrInvalidAmount) {
			t.Errorf("amount %d: %v", bad, err)
		}
	}
}

func TestAdminUsers_RewardModeCreatesInboxGift(t *testing.T) {
	e := newUsersEnv(t, nil)
	if _, err := e.svc.AdjustCoins(t.Context(), actor, uidA, "reward", -5, "negative gift"); !errors.Is(err, service.ErrInvalidAmount) {
		t.Errorf("negative reward: %v", err)
	}
	res, err := e.svc.AdjustCoins(t.Context(), actor, uidA, "reward", 50, "contest prize")
	if err != nil || res.Mode != "reward" || res.Balance != nil {
		t.Fatalf("res=%+v err=%v", res, err)
	}
	if e.granter.kind != repository.RewardAdminGift || e.granter.coins != 50 || e.granter.ref == "" {
		t.Errorf("granter = %+v", e.granter)
	}
	if e.store.users[uidA].Coins != 100 {
		t.Error("a gift reward must not change the balance until claimed")
	}
	if got := e.audit.AuditActions(); len(got) != 1 {
		t.Errorf("audit = %v", got)
	}
}

func TestAdminUsers_PremiumRenameAvatarBan(t *testing.T) {
	e := newUsersEnv(t, nil)
	ctx := t.Context()

	if _, err := e.svc.GrantPremium(ctx, actor, uidA, 0, "zero days"); !errors.Is(err, service.ErrInvalidDays) {
		t.Errorf("0 days: %v", err)
	}
	if r, err := e.svc.GrantPremium(ctx, actor, uidA, 30, "support gift"); err != nil || !r.Premium {
		t.Errorf("grant: %+v %v", r, err)
	}
	if r, err := e.svc.RevokePremium(ctx, actor, uidA, "chargeback"); err != nil || r.Premium {
		t.Errorf("revoke: %+v %v", r, err)
	}
	if name, err := e.svc.Rename(ctx, actor, uidA, " fixed_name ", "offensive name"); err != nil || name != "fixed_name" {
		t.Errorf("rename: %q %v", name, err)
	}
	if err := e.svc.ClearAvatar(ctx, actor, uidA, "offensive avatar"); err != nil {
		t.Errorf("avatar: %v", err)
	}

	if err := e.svc.Unban(ctx, actor, uidA, "not banned yet"); !errors.Is(err, service.ErrNotBanned) {
		t.Errorf("unban unbanned: %v", err)
	}
	if err := e.svc.Ban(ctx, actor, uidA, "cheating"); err != nil {
		t.Errorf("ban: %v", err)
	}
	if err := e.svc.Ban(ctx, actor, uidA, "cheating again"); !errors.Is(err, service.ErrAlreadyBanned) {
		t.Errorf("double ban: %v", err)
	}
	if err := e.svc.Unban(ctx, actor, uidA, "appeal accepted"); err != nil {
		t.Errorf("unban: %v", err)
	}

	want := []string{"user.premium_grant", "user.premium_revoke", "user.rename", "user.avatar_clear", "user.ban", "user.unban"}
	got := e.audit.AuditActions()
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Errorf("audit actions\n got %v\nwant %v", got, want)
	}
}

func TestAdminUsers_RenameErrorsPassThrough(t *testing.T) {
	e := newUsersEnv(t, service.ErrUsernameTaken)
	if _, err := e.svc.Rename(t.Context(), actor, uidA, "taken", "rename request"); !errors.Is(err, service.ErrUsernameTaken) {
		t.Errorf("taken: %v", err)
	}
	if len(e.audit.Audits) != 0 {
		t.Error("a failed rename was audited")
	}
}
