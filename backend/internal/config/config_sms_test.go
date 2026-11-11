package config

import "testing"

func TestSMSKeyForEnv(t *testing.T) {
	cases := []struct {
		env, key, want string
	}{
		{"prod", "k", "k"},
		{"dev", "k", ""},
		{"", "k", ""},
		{"staging", "k", ""},
		{"prod", "", ""},
	}
	for _, c := range cases {
		if got := smsKeyForEnv(c.env, c.key); got != c.want {
			t.Errorf("smsKeyForEnv(%q, %q) = %q, want %q", c.env, c.key, got, c.want)
		}
	}
}

func TestLoadIgnoresSMSKeyOutsideProd(t *testing.T) {
	t.Setenv("ENV", "dev")
	t.Setenv("KAVENEGAR_API_KEY", "secret")
	if got := Load().KavenegarAPIKey; got != "" {
		t.Fatalf("dev KavenegarAPIKey = %q, want empty", got)
	}
	t.Setenv("ENV", "prod")
	if got := Load().KavenegarAPIKey; got != "secret" {
		t.Fatalf("prod KavenegarAPIKey = %q, want secret", got)
	}
}
