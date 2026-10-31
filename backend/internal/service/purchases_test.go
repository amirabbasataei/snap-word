package service_test

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/service"
	"wordchain/backend/internal/testutil"
)

type fakeBazaar struct {
	purchase *service.BazaarPurchase
	sub      *service.BazaarSubscription
	err      error
	off      bool
}

func (f *fakeBazaar) Configured() bool { return !f.off }
func (f *fakeBazaar) ValidatePurchase(context.Context, string, string) (*service.BazaarPurchase, error) {
	return f.purchase, f.err
}
func (f *fakeBazaar) ValidateSubscription(context.Context, string, string) (*service.BazaarSubscription, error) {
	return f.sub, f.err
}

const (
	payA = "eeeeeeee-0000-4000-8000-00000000000a"
	payB = "eeeeeeee-0000-4000-8000-00000000000b"
)

func newPurchaseSvc(t *testing.T, f *fakeBazaar) (*service.PurchaseService, func(id string) (int, *time.Time)) {
	t.Helper()
	db := testutil.NewPostgres(t)
	for i, id := range []string{payA, payB} {
		if _, err := db.Exec(`INSERT INTO users (id, phone, coins) VALUES ($1, $2, 10)`, id, "0913000000"+string(rune('1'+i))); err != nil {
			t.Fatal(err)
		}
	}
	read := func(id string) (int, *time.Time) {
		var coins int
		var until *time.Time
		if err := db.QueryRow(`SELECT coins, premium_until FROM users WHERE id=$1`, id).Scan(&coins, &until); err != nil {
			t.Fatal(err)
		}
		return coins, until
	}
	return service.NewPurchaseService(repository.NewPurchaseRepository(db), f), read
}

func TestVerifyBazaar_CoinsCreditedOnce(t *testing.T) {
	f := &fakeBazaar{purchase: &service.BazaarPurchase{Purchased: true, DeveloperPayload: payA}}
	svc, read := newPurchaseSvc(t, f)
	ctx := context.Background()

	r, err := svc.VerifyBazaar(ctx, payA, "coins_350", "tok-1")
	if err != nil || r.CoinsAwarded != 350 || r.Coins != 360 || r.AlreadyProcessed {
		t.Fatalf("first = %+v, %v", r, err)
	}
	// A retry of the same token pays nothing but succeeds, so the client can consume.
	r, err = svc.VerifyBazaar(ctx, payA, "coins_350", "tok-1")
	if err != nil || r.CoinsAwarded != 0 || !r.AlreadyProcessed || r.Coins != 360 {
		t.Fatalf("retry = %+v, %v", r, err)
	}
	if c, _ := read(payA); c != 360 {
		t.Fatalf("balance = %d, want 360", c)
	}
	// Another account cannot redeem that token (payload binds it to A too).
	f.purchase.DeveloperPayload = ""
	if _, err = svc.VerifyBazaar(ctx, payB, "coins_350", "tok-1"); !errors.Is(err, service.ErrPurchaseOwnedByOther) {
		t.Fatalf("other account err = %v", err)
	}
	if c, _ := read(payB); c != 10 {
		t.Fatalf("B balance = %d, want 10", c)
	}
}

func TestVerifyBazaar_Rejections(t *testing.T) {
	f := &fakeBazaar{purchase: &service.BazaarPurchase{Purchased: true}}
	svc, read := newPurchaseSvc(t, f)
	ctx := context.Background()

	if _, err := svc.VerifyBazaar(ctx, payA, "remove_ads", "t"); !errors.Is(err, service.ErrUnknownProduct) {
		t.Fatalf("remove_ads must not be sellable, err = %v", err)
	}
	if _, err := svc.VerifyBazaar(ctx, payA, "coins_100", " "); !errors.Is(err, service.ErrPurchaseInvalid) {
		t.Fatalf("blank token err = %v", err)
	}
	f.purchase = &service.BazaarPurchase{Purchased: false} // refunded
	if _, err := svc.VerifyBazaar(ctx, payA, "coins_100", "t2"); !errors.Is(err, service.ErrPurchaseInvalid) {
		t.Fatalf("refunded err = %v", err)
	}
	f.purchase = &service.BazaarPurchase{Purchased: true, DeveloperPayload: payB}
	if _, err := svc.VerifyBazaar(ctx, payA, "coins_100", "t3"); !errors.Is(err, service.ErrPurchaseWrongRecipient) {
		t.Fatalf("wrong payload err = %v", err)
	}
	f.err = service.ErrPurchaseInvalid
	if _, err := svc.VerifyBazaar(ctx, payA, "coins_100", "t4"); !errors.Is(err, service.ErrPurchaseInvalid) {
		t.Fatalf("store 404 err = %v", err)
	}
	f.err, f.off = nil, true
	if _, err := svc.VerifyBazaar(ctx, payA, "coins_100", "t5"); !errors.Is(err, service.ErrPaymentsUnavailable) {
		t.Fatalf("unconfigured err = %v", err)
	}
	if c, _ := read(payA); c != 10 {
		t.Fatalf("balance changed on rejected purchases: %d", c)
	}
}

func TestVerifyBazaar_SubscriptionExtendsNeverShortens(t *testing.T) {
	later := time.Now().Add(30 * 24 * time.Hour).Truncate(time.Second)
	f := &fakeBazaar{sub: &service.BazaarSubscription{ValidUntil: later}}
	svc, read := newPurchaseSvc(t, f)
	ctx := context.Background()

	r, err := svc.VerifyBazaar(ctx, payA, "premium_monthly", "sub-1")
	if err != nil || r.PremiumUntil == nil || !r.PremiumUntil.Equal(later) {
		t.Fatalf("first = %+v, %v", r, err)
	}
	// Renewal: same token, later expiry.
	renewed := later.Add(30 * 24 * time.Hour)
	f.sub = &service.BazaarSubscription{ValidUntil: renewed}
	if r, err = svc.VerifyBazaar(ctx, payA, "premium_monthly", "sub-1"); err != nil || !r.PremiumUntil.Equal(renewed) {
		t.Fatalf("renew = %+v, %v", r, err)
	}
	// A stale answer never shortens it.
	f.sub = &service.BazaarSubscription{ValidUntil: later}
	if r, err = svc.VerifyBazaar(ctx, payA, "premium_monthly", "sub-1"); err != nil || !r.PremiumUntil.Equal(renewed) {
		t.Fatalf("stale = %+v, %v", r, err)
	}
	if _, u := read(payA); u == nil || !u.Equal(renewed) {
		t.Fatalf("premium_until = %v", u)
	}
	// Someone else's token, and an already-expired one.
	if _, err = svc.VerifyBazaar(ctx, payB, "premium_monthly", "sub-1"); !errors.Is(err, service.ErrPurchaseOwnedByOther) {
		t.Fatalf("other account err = %v", err)
	}
	f.sub = &service.BazaarSubscription{ValidUntil: time.Now().Add(-time.Hour)}
	if _, err = svc.VerifyBazaar(ctx, payB, "premium_monthly", "sub-2"); !errors.Is(err, service.ErrSubscriptionExpired) {
		t.Fatalf("expired err = %v", err)
	}
}

func bazaarServer(t *testing.T, tokenCalls *int32, validate http.HandlerFunc) *service.BazaarClient {
	t.Helper()
	mux := http.NewServeMux()
	mux.HandleFunc("/devapi/v2/auth/token/", func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(tokenCalls, 1)
		_ = r.ParseForm()
		if r.Form.Get("grant_type") != "refresh_token" || r.Form.Get("refresh_token") != "rt" || r.Form.Get("client_id") != "cid" {
			http.Error(w, `{"error":"invalid_grant"}`, http.StatusBadRequest)
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"access_token": "at", "expires_in": 3600})
	})
	mux.HandleFunc("/devapi/v2/api/", validate)
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	return service.NewBazaarClientForTest(&config.Config{
		BazaarPackageName: "com.ataei.zanjir", BazaarClientID: "cid", BazaarClientSecret: "cs", BazaarRefreshToken: "rt",
	}, srv.URL)
}

func TestBazaarClient_Validate(t *testing.T) {
	var tokenCalls int32
	var gotPath, gotAuth string
	c := bazaarServer(t, &tokenCalls, func(w http.ResponseWriter, r *http.Request) {
		gotPath, gotAuth = r.URL.Path, r.Header.Get("Authorization")
		switch {
		case strings.Contains(r.URL.Path, "/inapp/coins_100/purchases/good/"):
			_, _ = w.Write([]byte(`{"purchaseState":0,"consumptionState":1,"developerPayload":"u1"}`))
		case strings.Contains(r.URL.Path, "/inapp/coins_100/purchases/refunded/"):
			_, _ = w.Write([]byte(`{"purchaseState":1}`))
		case strings.Contains(r.URL.Path, "/subscriptions/premium_monthly/purchases/sub/"):
			_, _ = w.Write([]byte(`{"validUntilTimestampMsec":1900000000000}`))
		default:
			http.Error(w, `{"error":"not_found"}`, http.StatusNotFound)
		}
	})
	ctx := context.Background()

	p, err := c.ValidatePurchase(ctx, "coins_100", "good")
	if err != nil || !p.Purchased || p.DeveloperPayload != "u1" {
		t.Fatalf("good = %+v, %v", p, err)
	}
	if gotPath != "/devapi/v2/api/validate/com.ataei.zanjir/inapp/coins_100/purchases/good/" || gotAuth != "Bearer at" {
		t.Fatalf("request = %q auth %q", gotPath, gotAuth)
	}
	if p, _ = c.ValidatePurchase(ctx, "coins_100", "refunded"); p == nil || p.Purchased {
		t.Fatalf("refunded = %+v", p)
	}
	if _, err = c.ValidatePurchase(ctx, "coins_100", "nope"); !errors.Is(err, service.ErrPurchaseInvalid) {
		t.Fatalf("404 err = %v", err)
	}
	s, err := c.ValidateSubscription(ctx, "premium_monthly", "sub")
	if err != nil || s.ValidUntil.UnixMilli() != 1900000000000 {
		t.Fatalf("sub = %+v, %v", s, err)
	}
	if n := atomic.LoadInt32(&tokenCalls); n != 1 {
		t.Fatalf("access token fetched %d times, want 1 (cached)", n)
	}
}

func TestBazaarClient_RefreshesOn401AndHandlesBadCredentials(t *testing.T) {
	var tokenCalls, hits int32
	c := bazaarServer(t, &tokenCalls, func(w http.ResponseWriter, r *http.Request) {
		if atomic.AddInt32(&hits, 1) == 1 {
			http.Error(w, `{}`, http.StatusUnauthorized)
			return
		}
		_, _ = w.Write([]byte(`{"purchaseState":0}`))
	})
	if p, err := c.ValidatePurchase(context.Background(), "coins_100", "x"); err != nil || !p.Purchased {
		t.Fatalf("after 401 retry = %+v, %v", p, err)
	}
	if atomic.LoadInt32(&tokenCalls) != 2 {
		t.Fatalf("token calls = %d, want 2", tokenCalls)
	}

	bad := service.NewBazaarClientForTest(&config.Config{BazaarClientID: "cid", BazaarClientSecret: "cs", BazaarRefreshToken: "wrong"},
		"http://127.0.0.1:1")
	if _, err := bad.ValidatePurchase(context.Background(), "coins_100", "x"); !errors.Is(err, service.ErrStoreUnavailable) {
		t.Fatalf("unreachable store err = %v", err)
	}
	none := service.NewBazaarClient(&config.Config{})
	if _, err := none.ValidatePurchase(context.Background(), "coins_100", "x"); !errors.Is(err, service.ErrPaymentsUnavailable) {
		t.Fatalf("unconfigured err = %v", err)
	}
}
