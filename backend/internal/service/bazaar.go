package service

import (
	"crypto"
	"crypto/rsa"
	"crypto/sha1" //nolint:gosec // Bazaar signs purchases with SHA1withRSA
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"wordchain/backend/internal/config"
)

// Errors of the store layer.
var (
	// ErrPaymentsUnavailable: the Bazaar RSA public key is not configured.
	ErrPaymentsUnavailable = errors.New("payments_unavailable")
	// ErrPurchaseInvalid: the receipt is forged, malformed, for another app or
	// product, or the purchase was refunded.
	ErrPurchaseInvalid = errors.New("purchase_invalid")
)

// BazaarReceipt is the signed purchase record Bazaar hands the app.
type BazaarReceipt struct {
	ProductID    string
	Token        string
	Payload      string // developer payload: the account id the client set
	PackageName  string
	Purchased    bool // false once refunded
	PurchaseTime time.Time
}

// BazaarVerifier checks a purchase receipt.
type BazaarVerifier interface {
	Configured() bool
	// VerifyReceipt validates signature (base64) over signedData (the exact
	// JSON string Bazaar signed) and returns the parsed receipt.
	VerifyReceipt(signedData, signature string) (*BazaarReceipt, error)
}

// BazaarRSAVerifier verifies receipts with the app's public RSA key from the
// Bazaar panel — the same key Poolakey takes in connect(). Bazaar signs the
// receipt JSON with SHA1withRSA, so a valid signature proves the purchase was
// made through Bazaar for this app; no developer-API credentials are needed.
type BazaarRSAVerifier struct {
	pub     *rsa.PublicKey
	pkgName string
}

// NewBazaarVerifier parses cfg.BazaarRSAPublicKey (base64 X.509 SubjectPublicKeyInfo,
// as shown in the panel; PEM armour is tolerated). A missing or unparsable key
// leaves the verifier unconfigured, so payments answer 503 instead of crediting.
func NewBazaarVerifier(cfg *config.Config) *BazaarRSAVerifier {
	v := &BazaarRSAVerifier{pkgName: cfg.BazaarPackageName}
	raw := cfg.BazaarRSAPublicKey
	for _, junk := range []string{"-----BEGIN PUBLIC KEY-----", "-----END PUBLIC KEY-----"} {
		raw = strings.ReplaceAll(raw, junk, "")
	}
	raw = strings.Join(strings.Fields(raw), "")
	if raw == "" {
		return v
	}
	der, err := base64.StdEncoding.DecodeString(raw)
	if err != nil {
		slog.Error("BAZAAR_RSA_PUBLIC_KEY is not valid base64; payments disabled")
		return v
	}
	key, err := x509.ParsePKIXPublicKey(der)
	if err != nil {
		slog.Error("BAZAAR_RSA_PUBLIC_KEY is not a public key; payments disabled", "error", err)
		return v
	}
	pub, ok := key.(*rsa.PublicKey)
	if !ok {
		slog.Error("BAZAAR_RSA_PUBLIC_KEY is not an RSA key; payments disabled")
		return v
	}
	v.pub = pub
	return v
}

func (v *BazaarRSAVerifier) Configured() bool { return v.pub != nil }

func (v *BazaarRSAVerifier) VerifyReceipt(signedData, signature string) (*BazaarReceipt, error) {
	if v.pub == nil {
		return nil, ErrPaymentsUnavailable
	}
	if signedData == "" || signature == "" || len(signedData) > 4096 || len(signature) > 2048 {
		return nil, ErrPurchaseInvalid
	}
	sig, err := base64.StdEncoding.DecodeString(strings.TrimSpace(signature))
	if err != nil {
		return nil, ErrPurchaseInvalid
	}
	sum := sha1.Sum([]byte(signedData)) //nolint:gosec
	if err := rsa.VerifyPKCS1v15(v.pub, crypto.SHA1, sum[:], sig); err != nil {
		return nil, ErrPurchaseInvalid
	}

	var raw struct {
		ProductID        string `json:"productId"`
		PurchaseToken    string `json:"purchaseToken"`
		DeveloperPayload string `json:"developerPayload"`
		Payload          string `json:"payload"`
		PackageName      string `json:"packageName"`
		PurchaseState    int    `json:"purchaseState"`
		PurchaseTime     int64  `json:"purchaseTime"`
	}
	if err := json.Unmarshal([]byte(signedData), &raw); err != nil {
		return nil, fmt.Errorf("%w: undecodable receipt", ErrPurchaseInvalid)
	}
	if raw.PackageName != v.pkgName {
		return nil, ErrPurchaseInvalid
	}
	payload := raw.DeveloperPayload
	if payload == "" {
		payload = raw.Payload
	}
	return &BazaarReceipt{
		ProductID:    raw.ProductID,
		Token:        raw.PurchaseToken,
		Payload:      payload,
		PackageName:  raw.PackageName,
		Purchased:    raw.PurchaseState == 0,
		PurchaseTime: time.UnixMilli(raw.PurchaseTime),
	}, nil
}
