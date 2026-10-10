package service_test

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/service"
	"wordchain/backend/internal/testutil"
)

const goodPassword = "correct horse battery"

type adminFixture struct {
	svc   *service.AdminAuthService
	store *testutil.FakeAdminStore
	mr    interface{ FastForward(time.Duration) }
	now   time.Time
}

func newAdminFixture(t *testing.T) *adminFixture {
	t.Helper()
	mr, rdb := testutil.NewRedis(t)
	store := testutil.NewFakeAdminStore()
	svc := service.NewAdminAuthService(store, rdb, &config.Config{AdminSessionTTL: 2 * time.Hour})
	f := &adminFixture{svc: svc, store: store, mr: mr, now: time.Now()}
	svc.SetNow(func() time.Time { return f.now })
	if _, err := svc.CreateAdmin(context.Background(), "Boss", goodPassword, service.AdminRoleOwner); err != nil {
		t.Fatalf("CreateAdmin: %v", err)
	}
	return f
}

// advance moves both the service clock and Redis TTLs forward.
func (f *adminFixture) advance(d time.Duration) {
	f.now = f.now.Add(d)
	f.mr.FastForward(d)
}

func TestAdminLogin_Success(t *testing.T) {
	f := newAdminFixture(t)
	sess, admin, err := f.svc.Login(context.Background(), "1.1.1.1", " BOSS ", goodPassword)
	if err != nil {
		t.Fatalf("Login: %v", err)
	}
	if admin.Username != "boss" || sess.Role != service.AdminRoleOwner || len(sess.Token) != 64 {
		t.Errorf("unexpected session %+v / admin %+v", sess, admin)
	}
	got, err := f.svc.Authenticate(context.Background(), sess.Token)
	if err != nil || got.AdminID != admin.ID {
		t.Errorf("Authenticate: %v, %+v", err, got)
	}
}

func TestAdminLogin_BadCredentialsAreIndistinguishable(t *testing.T) {
	f := newAdminFixture(t)
	ctx := context.Background()
	if err := f.svc.SetDisabled(ctx, "boss", true); err != nil {
		t.Fatal(err)
	}
	if err := f.svc.SetDisabled(ctx, "boss", false); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.CreateAdmin(ctx, "gone", goodPassword, service.AdminRoleViewer); err != nil {
		t.Fatal(err)
	}
	if err := f.svc.SetDisabled(ctx, "gone", true); err != nil {
		t.Fatal(err)
	}
	cases := map[string][2]string{
		"wrong password": {"boss", "not the password"},
		"unknown user":   {"nobody", goodPassword},
		"disabled user":  {"gone", goodPassword},
	}
	for name, c := range cases {
		_, _, err := f.svc.Login(ctx, "2.2.2.2", c[0], c[1])
		if !errors.Is(err, service.ErrAdminInvalidCredentials) {
			t.Errorf("%s: got %v, want ErrAdminInvalidCredentials", name, err)
		}
	}
}

func TestAdminLogin_LockoutPerIP(t *testing.T) {
	f := newAdminFixture(t)
	ctx := context.Background()
	for i := 0; i < config.AdminLoginMaxFailsIP; i++ {
		if _, _, err := f.svc.Login(ctx, "3.3.3.3", "boss", "wrong-password-"+strings.Repeat("x", i)); !errors.Is(err, service.ErrAdminInvalidCredentials) {
			t.Fatalf("attempt %d: %v", i, err)
		}
	}
	// Even the right password is refused while locked out...
	if _, _, err := f.svc.Login(ctx, "3.3.3.3", "boss", goodPassword); !errors.Is(err, service.ErrAdminRateLimited) {
		t.Fatalf("locked-out login: got %v, want ErrAdminRateLimited", err)
	}
	// ...another address is unaffected...
	if _, _, err := f.svc.Login(ctx, "4.4.4.4", "boss", goodPassword); err != nil {
		t.Errorf("other IP: %v", err)
	}
	// ...and the window expires.
	f.advance(config.AdminLoginWindow + time.Second)
	if _, _, err := f.svc.Login(ctx, "3.3.3.3", "boss", goodPassword); err != nil {
		t.Errorf("after window: %v", err)
	}
}

func TestAdminLogin_LockoutPerUsernameAcrossIPs(t *testing.T) {
	f := newAdminFixture(t)
	ctx := context.Background()
	for i := 0; i < config.AdminLoginMaxFailsUser; i++ {
		ip := "5.5.5." + string(rune('a'+i)) // a new address each time dodges the per-IP cap
		if _, _, err := f.svc.Login(ctx, ip, "boss", "wrong-password"); !errors.Is(err, service.ErrAdminInvalidCredentials) {
			t.Fatalf("attempt %d: %v", i, err)
		}
	}
	if _, _, err := f.svc.Login(ctx, "6.6.6.6", "boss", goodPassword); !errors.Is(err, service.ErrAdminRateLimited) {
		t.Fatalf("got %v, want ErrAdminRateLimited", err)
	}
}

func TestAdminSession_IdleExpiryAndSliding(t *testing.T) {
	f := newAdminFixture(t)
	ctx := context.Background()
	sess, _, _ := f.svc.Login(ctx, "1.1.1.1", "boss", goodPassword)

	f.advance(90 * time.Minute)
	if _, err := f.svc.Authenticate(ctx, sess.Token); err != nil {
		t.Fatalf("within idle window: %v", err)
	}
	f.advance(90 * time.Minute) // 3h total, but activity at 1.5h slid the window
	if _, err := f.svc.Authenticate(ctx, sess.Token); err != nil {
		t.Fatalf("sliding window should keep it alive: %v", err)
	}
	f.advance(2*time.Hour + time.Minute)
	if _, err := f.svc.Authenticate(ctx, sess.Token); !errors.Is(err, service.ErrAdminSessionInvalid) {
		t.Fatalf("idle expiry: got %v", err)
	}
}

func TestAdminSession_AbsoluteExpiry(t *testing.T) {
	f := newAdminFixture(t)
	ctx := context.Background()
	sess, _, _ := f.svc.Login(ctx, "1.1.1.1", "boss", goodPassword)
	// Stay active every 90 minutes; the 12h cap must still end the session.
	var err error
	for elapsed := time.Duration(0); elapsed <= config.AdminSessionAbsoluteTTL+3*time.Hour; elapsed += 90 * time.Minute {
		f.advance(90 * time.Minute)
		if _, err = f.svc.Authenticate(ctx, sess.Token); err != nil {
			break
		}
	}
	if !errors.Is(err, service.ErrAdminSessionInvalid) {
		t.Fatalf("session survived past the absolute cap: %v", err)
	}
	if f.now.Sub(sess.CreatedAt) > config.AdminSessionAbsoluteTTL+90*time.Minute {
		t.Errorf("ended too late: %v after login", f.now.Sub(sess.CreatedAt))
	}
}

func TestAdminSession_RejectsGarbageTokens(t *testing.T) {
	f := newAdminFixture(t)
	for _, tok := range []string{"", "abc", strings.Repeat("g", 64), strings.Repeat("a", 64)} {
		if _, err := f.svc.Authenticate(context.Background(), tok); !errors.Is(err, service.ErrAdminSessionInvalid) {
			t.Errorf("token %q: got %v", tok, err)
		}
	}
}

func TestAdminSession_LogoutAndRevocation(t *testing.T) {
	f := newAdminFixture(t)
	ctx := context.Background()

	a, _, _ := f.svc.Login(ctx, "1.1.1.1", "boss", goodPassword)
	f.svc.Logout(ctx, a)
	if _, err := f.svc.Authenticate(ctx, a.Token); !errors.Is(err, service.ErrAdminSessionInvalid) {
		t.Errorf("after logout: %v", err)
	}

	b, _, _ := f.svc.Login(ctx, "1.1.1.1", "boss", goodPassword)
	c, _, _ := f.svc.Login(ctx, "1.1.1.1", "boss", goodPassword)
	if err := f.svc.SetPassword(ctx, "boss", "another long password"); err != nil {
		t.Fatal(err)
	}
	for _, s := range []*service.AdminSession{b, c} {
		if _, err := f.svc.Authenticate(ctx, s.Token); !errors.Is(err, service.ErrAdminSessionInvalid) {
			t.Errorf("session survived password change: %v", err)
		}
	}
	if _, _, err := f.svc.Login(ctx, "1.1.1.1", "boss", goodPassword); !errors.Is(err, service.ErrAdminInvalidCredentials) {
		t.Errorf("old password still works: %v", err)
	}
	if _, _, err := f.svc.Login(ctx, "1.1.1.1", "boss", "another long password"); err != nil {
		t.Errorf("new password: %v", err)
	}
}

func TestAdminSession_DisabledAndRoleChangeApplyImmediately(t *testing.T) {
	f := newAdminFixture(t)
	ctx := context.Background()
	sess, admin, _ := f.svc.Login(ctx, "1.1.1.1", "boss", goodPassword)

	f.store.SetRole(admin.ID, service.AdminRoleViewer)
	got, err := f.svc.Authenticate(ctx, sess.Token)
	if err != nil || got.Role != service.AdminRoleViewer {
		t.Fatalf("role change not picked up: %+v, %v", got, err)
	}

	if err := f.svc.SetDisabled(ctx, "boss", true); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.Authenticate(ctx, sess.Token); !errors.Is(err, service.ErrAdminSessionInvalid) {
		t.Errorf("disabled admin kept access: %v", err)
	}
}

func TestAdminEnabled(t *testing.T) {
	_, rdb := testutil.NewRedis(t)
	store := testutil.NewFakeAdminStore()
	svc := service.NewAdminAuthService(store, rdb, &config.Config{})
	now := time.Now()
	svc.SetNow(func() time.Time { return now })
	ctx := context.Background()

	if svc.Enabled(ctx) {
		t.Fatal("enabled with no admins")
	}
	if _, err := svc.CreateAdmin(ctx, "boss", goodPassword, service.AdminRoleOwner); err != nil {
		t.Fatal(err)
	}
	now = now.Add(10 * time.Second) // past the cache
	if !svc.Enabled(ctx) {
		t.Fatal("not enabled after the first admin was created")
	}
}

func TestCreateAdmin_Validation(t *testing.T) {
	f := newAdminFixture(t)
	ctx := context.Background()
	cases := []struct {
		name, user, pass, role string
		want                   error
	}{
		{"short username", "ab", goodPassword, "owner", service.ErrAdminInvalidUsername},
		{"bad chars", "bad name", goodPassword, "owner", service.ErrAdminInvalidUsername},
		{"digit first", "1admin", goodPassword, "owner", service.ErrAdminInvalidUsername},
		{"short password", "newadmin", "short", "owner", service.ErrAdminWeakPassword},
		{"password over bcrypt limit", "newadmin", strings.Repeat("a", 73), "owner", service.ErrAdminWeakPassword},
		{"bad role", "newadmin", goodPassword, "root", service.ErrAdminInvalidRole},
		{"duplicate", "boss", goodPassword, "owner", service.ErrAdminUsernameTaken},
	}
	for _, c := range cases {
		if _, err := f.svc.CreateAdmin(ctx, c.user, c.pass, c.role); !errors.Is(err, c.want) {
			t.Errorf("%s: got %v, want %v", c.name, err, c.want)
		}
	}
}

func TestAdminRoleAtLeast(t *testing.T) {
	cases := []struct {
		role, min string
		want      bool
	}{
		{"owner", "operator", true},
		{"operator", "operator", true},
		{"viewer", "operator", false},
		{"operator", "owner", false},
		{"viewer", "viewer", true},
		{"", "viewer", false},
		{"owner", "bogus", false},
	}
	for _, c := range cases {
		if got := service.AdminRoleAtLeast(c.role, c.min); got != c.want {
			t.Errorf("AdminRoleAtLeast(%q,%q)=%v", c.role, c.min, got)
		}
	}
}
