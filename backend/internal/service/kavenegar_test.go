package service_test

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/service"
)

func kavenegarAgainst(t *testing.T, h http.HandlerFunc) *service.KavenegarClient {
	t.Helper()
	srv := httptest.NewServer(h)
	t.Cleanup(srv.Close)
	k := service.NewKavenegarClient(&config.Config{KavenegarAPIKey: "KEY123", KavenegarOTPTemplate: "zanjir"})
	k.SetBaseURL(srv.URL)
	return k
}

func TestKavenegar_SendOTP_RequestShape(t *testing.T) {
	var gotPath string
	var gotQuery map[string]string
	k := kavenegarAgainst(t, func(w http.ResponseWriter, r *http.Request) {
		gotPath = r.URL.Path
		gotQuery = map[string]string{}
		for key := range r.URL.Query() {
			gotQuery[key] = r.URL.Query().Get(key)
		}
		w.Write([]byte(`{"return":{"status":200,"message":"تایید شد"},"entries":[{"messageid":1,"receptor":"09123456789"}]}`))
	})
	if err := k.SendOTP(context.Background(), "09123456789", "4821"); err != nil {
		t.Fatalf("SendOTP: %v", err)
	}
	if gotPath != "/v1/KEY123/verify/lookup.json" {
		t.Errorf("path = %q", gotPath)
	}
	want := map[string]string{"receptor": "09123456789", "token": "4821", "template": "zanjir", "type": "sms"}
	for key, v := range want {
		if gotQuery[key] != v {
			t.Errorf("query %s = %q, want %q", key, gotQuery[key], v)
		}
	}
}

func TestKavenegar_SendOTP_ProviderErrors(t *testing.T) {
	cases := []struct {
		name       string
		httpStatus int
		body       string
		want       int
	}{
		{"template not found", 424, `{"return":{"status":424,"message":"قالب یافت نشد"}}`, 424},
		{"no credit", 418, `{"return":{"status":418,"message":"اعتبار حساب شما کافی نیست"}}`, 418},
		{"bad key, empty body", 403, ``, 403},
		{"200 http but error status", 200, `{"return":{"status":411,"message":"x"}}`, 411},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			k := kavenegarAgainst(t, func(w http.ResponseWriter, r *http.Request) {
				w.WriteHeader(tc.httpStatus)
				w.Write([]byte(tc.body))
			})
			err := k.SendOTP(context.Background(), "09123456789", "4821")
			var ke *service.KavenegarError
			if !errors.As(err, &ke) || ke.Code != tc.want {
				t.Fatalf("got %v, want KavenegarError{%d}", err, tc.want)
			}
		})
	}
}

func TestKavenegar_SendOTP_NetworkErrorDoesNotLeakKey(t *testing.T) {
	k := service.NewKavenegarClient(&config.Config{KavenegarAPIKey: "SECRETKEY", KavenegarOTPTemplate: "zanjir"})
	k.SetBaseURL("http://127.0.0.1:1") // nothing listens
	err := k.SendOTP(context.Background(), "09123456789", "4821")
	if err == nil {
		t.Fatal("expected an error")
	}
	if strings.Contains(err.Error(), "SECRETKEY") || strings.Contains(err.Error(), "4821") {
		t.Errorf("error leaks key or code: %v", err)
	}
}

func TestKavenegar_NotConfiguredIsNoop(t *testing.T) {
	k := service.NewKavenegarClient(&config.Config{})
	if k.Configured() {
		t.Fatal("empty key must not be configured")
	}
	if err := k.SendOTP(context.Background(), "09123456789", "1111"); err != nil {
		t.Fatalf("no-op send returned %v", err)
	}
}
