package config

import (
	"testing"
	"time"
)

func TestIranDate(t *testing.T) {
	cases := []struct {
		in   time.Time
		want string
	}{
		{time.Date(2026, 9, 30, 20, 29, 0, 0, time.UTC), "2026-09-30"}, // 23:59 Iran
		{time.Date(2026, 9, 30, 20, 30, 0, 0, time.UTC), "2026-10-01"}, // 00:00 Iran
		{time.Date(2026, 10, 2, 20, 30, 0, 0, time.UTC), "2026-10-03"}, // Friday night → Saturday
	}
	for _, c := range cases {
		if got := IranDate(c.in).Format("2006-01-02"); got != c.want {
			t.Errorf("IranDate(%v) = %s, want %s", c.in, got, c.want)
		}
	}
	// 2026-10-03 is a Saturday: the weekly reset moment.
	if IranDate(time.Date(2026, 10, 2, 20, 30, 0, 0, time.UTC)).Weekday() != time.Saturday {
		t.Error("expected Saturday")
	}
}
