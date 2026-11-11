package service_test

import (
	"context"
	"errors"
	"strings"
	"sync"
	"testing"

	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/service"
	"wordchain/backend/internal/testutil"
)

const (
	nUserGranted = "eeeeeeee-0000-4000-8000-000000000001"
	nUserDenied  = "eeeeeeee-0000-4000-8000-000000000002"
	nUserNone    = "eeeeeeee-0000-4000-8000-000000000003"
	nUserLegacy  = "eeeeeeee-0000-4000-8000-000000000004"
	nUserBanned  = "eeeeeeee-0000-4000-8000-000000000005"
	nUserPremium = "eeeeeeee-0000-4000-8000-000000000006"
)

type fakeCampaignPush struct {
	mu         sync.Mutex
	configured bool
	got        []service.PushTarget
	title      string
	route      string
}

func (f *fakeCampaignPush) Configured() bool { return f.configured }
func (f *fakeCampaignPush) SendBatch(_ context.Context, t []service.PushTarget, title, _, route string) service.PushResult {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.got, f.title, f.route = t, title, route
	users := map[string]bool{}
	for _, x := range t {
		users[x.UserID] = true
	}
	return service.PushResult{Users: len(users), Devices: len(t), Sent: len(t)}
}

func newNotifSvc(t *testing.T, fcm bool) (*service.AdminNotificationService, *fakeCampaignPush, *repository.AdminRepository, *repository.InboxRepository) {
	t.Helper()
	db := testutil.NewPostgres(t)
	exec := func(q string, args ...any) {
		if _, err := db.Exec(q, args...); err != nil {
			t.Fatalf("%s: %v", q, err)
		}
	}
	for _, u := range []struct{ id, phone, name string }{
		{nUserGranted, "09130000001", "granted"}, {nUserDenied, "09130000002", "denied"},
		{nUserNone, "09130000003", "none"}, {nUserLegacy, "09130000004", "legacy"},
		{nUserBanned, "09130000005", "banned"}, {nUserPremium, "09130000006", "premium"},
	} {
		exec(`INSERT INTO users (id, phone, username, phone_verified_at) VALUES ($1, $2, $3, now())`, u.id, u.phone, u.name)
	}
	exec(`UPDATE users SET banned_at = now() WHERE id = $1`, nUserBanned)
	exec(`UPDATE users SET premium_until = now() + interval '5 days' WHERE id = $1`, nUserPremium)
	exec(`INSERT INTO device_tokens (user_id, token, platform, permission) VALUES
		($1, 'tok-granted', 'android', 'granted'), ($2, 'tok-denied', 'ios', 'denied'),
		($3, 'tok-legacy', 'android', 'unknown'), ($4, 'tok-banned', 'android', 'granted'),
		($5, 'tok-premium', 'android', 'not_determined')`,
		nUserGranted, nUserDenied, nUserLegacy, nUserBanned, nUserPremium)

	repo := repository.NewAdminRepository(db)
	push := &fakeCampaignPush{configured: fcm}
	svc := service.NewAdminNotificationService(repo, push, service.NewAuditService(repo))
	return svc, push, repo, repository.NewInboxRepository(db)
}

var notifActor = service.AuditActor{Name: "tester"}

func TestNotif_PreviewShowsPermissionBreakdown(t *testing.T) {
	svc, _, _, _ := newNotifSvc(t, true)
	p, err := svc.Preview(context.Background(), repository.NotifAudience{Type: "all"})
	if err != nil {
		t.Fatal(err)
	}
	// Banned user excluded: 5 recipients.
	if p.Recipients != 5 || p.Push.Granted != 1 || p.Push.Unknown != 1 || p.Push.Denied != 1 ||
		p.Push.NotDetermined != 1 || p.Push.None != 1 || p.Push.Deliverable != 2 || !p.FCMConfigured {
		t.Fatalf("preview = %+v", p)
	}
}

func TestNotif_SegmentFilters(t *testing.T) {
	svc, _, _, _ := newNotifSvc(t, true)
	ctx := context.Background()
	count := func(seg repository.NotifSegment) int {
		p, err := svc.Preview(ctx, repository.NotifAudience{Type: "segment", Segment: &seg})
		if err != nil {
			t.Fatal(err)
		}
		return p.Recipients
	}
	if n := count(repository.NotifSegment{Premium: "yes"}); n != 1 {
		t.Errorf("premium yes = %d, want 1", n)
	}
	if n := count(repository.NotifSegment{Premium: "no"}); n != 4 {
		t.Errorf("premium no = %d, want 4", n)
	}
	if n := count(repository.NotifSegment{Push: "enabled"}); n != 1 {
		t.Errorf("push enabled = %d, want 1 (only a granted device)", n)
	}
	if n := count(repository.NotifSegment{Push: "disabled"}); n != 4 {
		t.Errorf("push disabled = %d, want 4", n)
	}
	// Nobody has played: "inactive for 7 days" is everyone, "active" is nobody.
	if n := count(repository.NotifSegment{Activity: "inactive", Days: 7}); n != 5 {
		t.Errorf("inactive = %d, want 5", n)
	}
	if n := count(repository.NotifSegment{Activity: "active", Days: 7}); n != 0 {
		t.Errorf("active = %d, want 0", n)
	}
	if n := count(repository.NotifSegment{JoinedWithinDays: 1}); n != 5 {
		t.Errorf("joined within 1 day = %d, want 5", n)
	}
	if _, err := svc.Preview(ctx, repository.NotifAudience{Type: "segment", Segment: &repository.NotifSegment{Activity: "active"}}); !errors.Is(err, service.ErrNotifAudience) {
		t.Errorf("activity without days = %v, want ErrNotifAudience", err)
	}
}

func TestNotif_SendPushAndInapp(t *testing.T) {
	svc, push, repo, inbox := newNotifSvc(t, true)
	ctx := context.Background()
	v, err := svc.Send(ctx, notifActor, service.NotifSendInput{
		Title: "سلام", Body: "پیام آزمایشی", Route: "/daily", Channels: []string{"push", "inapp"},
		Audience: repository.NotifAudience{Type: "all"},
	})
	if err != nil {
		t.Fatal(err)
	}
	if v.Recipients != 5 || v.InappDelivered != 5 || v.PushStatus != "sending" {
		t.Fatalf("view = %+v", v)
	}
	svc.Wait()

	// Push went to the granted and legacy devices only — not denied, not_determined, banned.
	toks := map[string]bool{}
	for _, g := range push.got {
		toks[g.Token] = true
	}
	if len(toks) != 2 || !toks["tok-granted"] || !toks["tok-legacy"] || push.route != "/daily" {
		t.Fatalf("pushed to %v route %q", toks, push.route)
	}
	got, err := svc.Get(ctx, v.ID)
	if err != nil || got.PushStatus != "done" || got.PushDevices != 2 || got.PushSent != 2 || got.PushUsers != 2 {
		t.Fatalf("after delivery = %+v, %v", got, err)
	}

	// Every recipient has an unread message; reading one is idempotent and private.
	msgs, err := inbox.ListUnread(ctx, nUserDenied)
	if err != nil || len(msgs) != 1 || msgs[0].Title != "سلام" || msgs[0].Route != "/daily" {
		t.Fatalf("inbox = %+v, %v", msgs, err)
	}
	if ok, _ := inbox.MarkRead(ctx, nUserGranted, msgs[0].ID); ok {
		t.Fatal("another user marked someone else's message read")
	}
	for i := 0; i < 2; i++ {
		if err := service.NewInboxService(inbox).MarkRead(ctx, nUserDenied, msgs[0].ID); err != nil {
			t.Fatal(err)
		}
	}
	if left, _ := inbox.ListUnread(ctx, nUserDenied); len(left) != 0 {
		t.Fatalf("still unread: %+v", left)
	}
	if banned, _ := inbox.ListUnread(ctx, nUserBanned); len(banned) != 0 {
		t.Fatal("banned user got a message")
	}
	d, _ := svc.Get(ctx, v.ID)
	if d.InappRead != 1 {
		t.Fatalf("read count = %d, want 1", d.InappRead)
	}
	_ = repo
}

func TestNotif_SpecificUsers(t *testing.T) {
	svc, push, _, inbox := newNotifSvc(t, true)
	ctx := context.Background()
	v, err := svc.Send(ctx, notifActor, service.NotifSendInput{
		Title: "فقط تو", Body: "پیام شخصی", Channels: []string{"inapp"},
		Audience: repository.NotifAudience{Type: "users", UserIDs: []string{nUserNone, strings.ToUpper(nUserNone)}},
	})
	if err != nil || v.Recipients != 1 {
		t.Fatalf("send = %+v, %v", v, err)
	}
	if msgs, _ := inbox.ListUnread(ctx, nUserNone); len(msgs) != 1 {
		t.Fatalf("recipient inbox = %+v", msgs)
	}
	if msgs, _ := inbox.ListUnread(ctx, nUserGranted); len(msgs) != 0 {
		t.Fatal("a user who was not addressed got the message")
	}
	svc.Wait()
	if len(push.got) != 0 {
		t.Fatal("in-app only send pushed")
	}
	d, _ := svc.Get(ctx, v.ID)
	if len(d.Users) != 1 || d.Users[0].Username != "none" {
		t.Fatalf("detail users = %+v", d.Users)
	}
	// Banned and unknown accounts cannot be addressed.
	for _, id := range []string{nUserBanned, "eeeeeeee-0000-4000-8000-0000000000ff"} {
		_, err := svc.Send(ctx, notifActor, service.NotifSendInput{
			Title: "x", Body: "y", Channels: []string{"inapp"}, Audience: repository.NotifAudience{Type: "users", UserIDs: []string{id}},
		})
		if !errors.Is(err, service.ErrNotifUnknownUser) {
			t.Errorf("addressing %s = %v, want ErrNotifUnknownUser", id, err)
		}
	}
}

func TestNotif_Validation(t *testing.T) {
	svc, _, _, _ := newNotifSvc(t, false)
	ctx := context.Background()
	all := repository.NotifAudience{Type: "all"}
	cases := []struct {
		name string
		in   service.NotifSendInput
		want error
	}{
		{"empty title", service.NotifSendInput{Title: " ", Body: "b", Channels: []string{"inapp"}, Audience: all}, service.ErrNotifTitle},
		{"long body", service.NotifSendInput{Title: "t", Body: strings.Repeat("ا", 241), Channels: []string{"inapp"}, Audience: all}, service.ErrNotifBody},
		{"no channel", service.NotifSendInput{Title: "t", Body: "b", Audience: all}, service.ErrNotifChannels},
		{"bad channel", service.NotifSendInput{Title: "t", Body: "b", Channels: []string{"sms"}, Audience: all}, service.ErrNotifChannels},
		{"bad route", service.NotifSendInput{Title: "t", Body: "b", Route: "/admin", Channels: []string{"inapp"}, Audience: all}, service.ErrNotifRoute},
		{"push without fcm", service.NotifSendInput{Title: "t", Body: "b", Channels: []string{"push"}, Audience: all}, service.ErrNotifFCMOff},
		{"bad audience", service.NotifSendInput{Title: "t", Body: "b", Channels: []string{"inapp"}, Audience: repository.NotifAudience{Type: "everyone"}}, service.ErrNotifAudience},
		{"empty users", service.NotifSendInput{Title: "t", Body: "b", Channels: []string{"inapp"}, Audience: repository.NotifAudience{Type: "users"}}, service.ErrNotifAudience},
	}
	for _, c := range cases {
		if _, err := svc.Send(ctx, notifActor, c.in); !errors.Is(err, c.want) {
			t.Errorf("%s: err = %v, want %v", c.name, err, c.want)
		}
	}
}

func TestNotif_PushNeedsADeliverableDeviceAndDuplicatesAreRefused(t *testing.T) {
	svc, _, _, _ := newNotifSvc(t, true)
	ctx := context.Background()
	// The denied user cannot be pushed.
	_, err := svc.Send(ctx, notifActor, service.NotifSendInput{
		Title: "t", Body: "b", Channels: []string{"push"}, Audience: repository.NotifAudience{Type: "users", UserIDs: []string{nUserDenied}},
	})
	if !errors.Is(err, service.ErrNotifNoDeliverable) {
		t.Fatalf("push to denied user = %v, want ErrNotifNoDeliverable", err)
	}
	in := service.NotifSendInput{Title: "یکسان", Body: "متن", Channels: []string{"inapp"}, Audience: repository.NotifAudience{Type: "all"}}
	if _, err := svc.Send(ctx, notifActor, in); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Send(ctx, notifActor, in); !errors.Is(err, service.ErrNotifDuplicate) {
		t.Fatalf("second identical send = %v, want ErrNotifDuplicate", err)
	}
}

func TestNotif_ReachAndHistory(t *testing.T) {
	svc, _, repo, _ := newNotifSvc(t, true)
	ctx := context.Background()
	r, err := svc.Reach(ctx)
	if err != nil || r.Users != 5 || r.Granted != 1 || r.Unknown != 1 || r.Deliverable != 2 || len(r.Devices) == 0 {
		t.Fatalf("reach = %+v, %v", r, err)
	}
	if _, err := svc.Send(ctx, notifActor, service.NotifSendInput{Title: "a", Body: "b", Channels: []string{"inapp"}, Audience: repository.NotifAudience{Type: "all"}}); err != nil {
		t.Fatal(err)
	}
	// The history also lists the seeded signup-gift campaign (migration 021), oldest.
	page, err := svc.List(ctx, 1, 20)
	if err != nil || page.Total != 2 || page.Items[0].Title != "a" || page.Items[0].CreatedBy != "tester" {
		t.Fatalf("history = %+v, %v", page, err)
	}
	if _, err := svc.Get(ctx, "eeeeeeee-0000-4000-8000-0000000000ff"); !errors.Is(err, service.ErrNotifNotFound) {
		t.Fatalf("missing campaign = %v", err)
	}
	devs, _ := repo.UserPushDevices(ctx, nUserGranted)
	if service.PushStateOf(devs) != "granted" || service.PushStateOf(nil) != "none" {
		t.Fatalf("PushStateOf = %q / %q", service.PushStateOf(devs), service.PushStateOf(nil))
	}
}

func TestNotif_RegisterTokenKeepsKnownPermission(t *testing.T) {
	db := testutil.NewPostgres(t)
	if _, err := db.Exec(`INSERT INTO users (id, phone) VALUES ($1, '09130000009')`, nUserGranted); err != nil {
		t.Fatal(err)
	}
	repo := repository.NewNotificationRepository(db)
	ctx := context.Background()
	read := func() string {
		var p string
		if err := db.QueryRow(`SELECT permission FROM device_tokens WHERE token = 't'`).Scan(&p); err != nil {
			t.Fatal(err)
		}
		return p
	}
	_ = repo.RegisterToken(ctx, nUserGranted, "t", "android", repository.PermDenied)
	if read() != "denied" {
		t.Fatalf("permission = %s", read())
	}
	// An old client (no permission field) must not erase what we know.
	_ = repo.RegisterToken(ctx, nUserGranted, "t", "android", repository.PermUnknown)
	if read() != "denied" {
		t.Fatalf("old client overwrote permission: %s", read())
	}
	_ = repo.RegisterToken(ctx, nUserGranted, "t", "android", repository.PermGranted)
	if read() != "granted" {
		t.Fatalf("permission = %s", read())
	}
}
