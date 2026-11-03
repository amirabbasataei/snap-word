package service_test

import (
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha1" //nolint:gosec
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"errors"
	"testing"
	"time"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/service"
	"wordchain/backend/internal/testutil"
)

const (
	payA = "eeeeeeee-0000-4000-8000-00000000000a"
	payB = "eeeeeeee-0000-4000-8000-00000000000b"
	pkg  = "com.ataei.zanjir"
)

// bazaarKeys plays Cafe Bazaar: it signs receipts with a private key whose
// public half is what the server is configured with.
type bazaarKeys struct {
	priv   *rsa.PrivateKey
	pubB64 string
}

func newBazaarKeys(t *testing.T) *bazaarKeys {
	t.Helper()
	priv, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	der, err := x509.MarshalPKIXPublicKey(&priv.PublicKey)
	if err != nil {
		t.Fatal(err)
	}
	return &bazaarKeys{priv: priv, pubB64: base64.StdEncoding.EncodeToString(der)}
}

type receipt struct {
	ProductID        string `json:"productId"`
	PurchaseToken    string `json:"purchaseToken"`
	DeveloperPayload string `json:"developerPayload"`
	PackageName      string `json:"packageName"`
	PurchaseState    int    `json:"purchaseState"`
	PurchaseTime     int64  `json:"purchaseTime"`
	OrderID          string `json:"orderId"`
}

func (k *bazaarKeys) sign(t *testing.T, r receipt) (data, sig string) {
	t.Helper()
	if r.PackageName == "" {
		r.PackageName = pkg
	}
	if r.PurchaseTime == 0 {
		r.PurchaseTime = time.Now().UnixMilli()
	}
	b, _ := json.Marshal(r)
	sum := sha1.Sum(b) //nolint:gosec
	raw, err := rsa.SignPKCS1v15(rand.Reader, k.priv, crypto.SHA1, sum[:])
	if err != nil {
		t.Fatal(err)
	}
	return string(b), base64.StdEncoding.EncodeToString(raw)
}

func newPurchaseSvc(t *testing.T) (*service.PurchaseService, *bazaarKeys, func(id string) (int, *time.Time)) {
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
	keys := newBazaarKeys(t)
	verifier := service.NewBazaarVerifier(&config.Config{BazaarPackageName: pkg, BazaarRSAPublicKey: keys.pubB64})
	return service.NewPurchaseService(repository.NewPurchaseRepository(db), verifier), keys, read
}

func TestVerifyBazaar_CoinsCreditedOnce(t *testing.T) {
	svc, keys, read := newPurchaseSvc(t)
	ctx := context.Background()
	data, sig := keys.sign(t, receipt{ProductID: "coins_350", PurchaseToken: "tok-1", DeveloperPayload: payA})

	r, err := svc.VerifyBazaar(ctx, payA, "coins_350", data, sig)
	if err != nil || r.CoinsAwarded != 350 || r.Coins != 360 || r.AlreadyProcessed {
		t.Fatalf("first = %+v, %v", r, err)
	}
	// A retry of the same receipt pays nothing but succeeds, so the client can consume.
	r, err = svc.VerifyBazaar(ctx, payA, "coins_350", data, sig)
	if err != nil || r.CoinsAwarded != 0 || !r.AlreadyProcessed || r.Coins != 360 {
		t.Fatalf("retry = %+v, %v", r, err)
	}
	if c, _ := read(payA); c != 360 {
		t.Fatalf("balance = %d, want 360", c)
	}
	// The payload binds the receipt to A; with no payload the token ledger still stops B.
	data2, sig2 := keys.sign(t, receipt{ProductID: "coins_350", PurchaseToken: "tok-1"})
	if _, err = svc.VerifyBazaar(ctx, payB, "coins_350", data2, sig2); !errors.Is(err, service.ErrPurchaseOwnedByOther) {
		t.Fatalf("other account err = %v", err)
	}
	if c, _ := read(payB); c != 10 {
		t.Fatalf("B balance = %d, want 10", c)
	}
}

func TestVerifyBazaar_Rejections(t *testing.T) {
	svc, keys, read := newPurchaseSvc(t)
	ctx := context.Background()
	good := receipt{ProductID: "coins_100", PurchaseToken: "t", DeveloperPayload: payA}

	if _, err := svc.VerifyBazaar(ctx, payA, "remove_ads", "x", "y"); !errors.Is(err, service.ErrUnknownProduct) {
		t.Fatalf("remove_ads must not be sellable, err = %v", err)
	}
	// Forged: signed by someone else's key.
	other := newBazaarKeys(t)
	d, s := other.sign(t, good)
	if _, err := svc.VerifyBazaar(ctx, payA, "coins_100", d, s); !errors.Is(err, service.ErrPurchaseInvalid) {
		t.Fatalf("forged err = %v", err)
	}
	// Tampered: valid signature, edited body.
	d, s = keys.sign(t, good)
	if _, err := svc.VerifyBazaar(ctx, payA, "coins_100", d+" ", s); !errors.Is(err, service.ErrPurchaseInvalid) {
		t.Fatalf("tampered err = %v", err)
	}
	for name, mutate := range map[string]func(*receipt){
		"refunded":      func(r *receipt) { r.PurchaseState = 1 },
		"other package": func(r *receipt) { r.PackageName = "com.other.app" },
		"other product": func(r *receipt) { r.ProductID = "coins_1500" }, // signed for a bigger pack than the request
		"blank token":   func(r *receipt) { r.PurchaseToken = " " },
	} {
		r := good
		mutate(&r)
		d, s := keys.sign(t, r)
		if _, err := svc.VerifyBazaar(ctx, payA, "coins_100", d, s); !errors.Is(err, service.ErrPurchaseInvalid) {
			t.Fatalf("%s err = %v", name, err)
		}
	}
	r := good
	r.DeveloperPayload = payB
	d, s = keys.sign(t, r)
	if _, err := svc.VerifyBazaar(ctx, payA, "coins_100", d, s); !errors.Is(err, service.ErrPurchaseWrongRecipient) {
		t.Fatalf("wrong payload err = %v", err)
	}
	if _, err := svc.VerifyBazaar(ctx, payA, "coins_100", "", ""); !errors.Is(err, service.ErrPurchaseInvalid) {
		t.Fatalf("empty receipt err = %v", err)
	}
	if c, _ := read(payA); c != 10 {
		t.Fatalf("balance changed on rejected purchases: %d", c)
	}
}

func TestVerifyBazaar_Unconfigured(t *testing.T) {
	db := testutil.NewPostgres(t)
	svc := service.NewPurchaseService(repository.NewPurchaseRepository(db), service.NewBazaarVerifier(&config.Config{BazaarPackageName: pkg}))
	if _, err := svc.VerifyBazaar(context.Background(), payA, "coins_100", "d", "s"); !errors.Is(err, service.ErrPaymentsUnavailable) {
		t.Fatalf("no key err = %v", err)
	}
	bad := service.NewBazaarVerifier(&config.Config{BazaarRSAPublicKey: "not a key"})
	if bad.Configured() {
		t.Fatal("garbage key must leave payments off")
	}
}

func TestVerifyBazaar_SubscriptionPeriod(t *testing.T) {
	svc, keys, read := newPurchaseSvc(t)
	ctx := context.Background()
	near := func(got time.Time, want time.Duration) bool {
		d := time.Until(got) - want
		return d > -time.Minute && d < time.Minute
	}

	// A fresh purchase is worth the full period from its purchase time.
	data, sig := keys.sign(t, receipt{ProductID: "premium_monthly", PurchaseToken: "sub-1", DeveloperPayload: payA})
	r, err := svc.VerifyBazaar(ctx, payA, "premium_monthly", data, sig)
	if err != nil || r.PremiumUntil == nil || !near(*r.PremiumUntil, config.PremiumPeriod) {
		t.Fatalf("first = %+v, %v", r, err)
	}
	first := *r.PremiumUntil
	// Re-reporting it (the next resume) never shortens it.
	time.Sleep(10 * time.Millisecond)
	if r, err = svc.VerifyBazaar(ctx, payA, "premium_monthly", data, sig); err != nil || r.PremiumUntil.Before(first) {
		t.Fatalf("repeat = %+v, %v", r, err)
	}
	if _, u := read(payA); u == nil || u.Before(first) {
		t.Fatalf("premium_until = %v", u)
	}

	// An old receipt of a still-listed subscription (a renewal that kept the
	// old purchase time) keeps premium only the short re-verify window ahead.
	old := time.Now().Add(-40 * 24 * time.Hour).UnixMilli()
	data, sig = keys.sign(t, receipt{ProductID: "premium_monthly", PurchaseToken: "sub-old", DeveloperPayload: payB, PurchaseTime: old})
	if r, err = svc.VerifyBazaar(ctx, payB, "premium_monthly", data, sig); err != nil || !near(*r.PremiumUntil, config.PremiumReverifyWindow) {
		t.Fatalf("old receipt = %+v, %v", r, err)
	}
	// A purchase time in the future (clock skew) is capped at now.
	future := time.Now().Add(10 * 24 * time.Hour).UnixMilli()
	data, sig = keys.sign(t, receipt{ProductID: "premium_monthly", PurchaseToken: "sub-future", DeveloperPayload: payB, PurchaseTime: future})
	if r, err = svc.VerifyBazaar(ctx, payB, "premium_monthly", data, sig); err != nil || r.PremiumUntil.After(time.Now().Add(config.PremiumPeriod+time.Minute)) {
		t.Fatalf("future receipt = %+v, %v", r, err)
	}
	// Someone else's subscription token.
	data2, sig2 := keys.sign(t, receipt{ProductID: "premium_monthly", PurchaseToken: "sub-1"})
	if _, err = svc.VerifyBazaar(ctx, payB, "premium_monthly", data2, sig2); !errors.Is(err, service.ErrPurchaseOwnedByOther) {
		t.Fatalf("other account err = %v", err)
	}
}
