package config

import "testing"

func TestLevelFromXP(t *testing.T) {
	cases := []struct {
		xp    int64
		level int
	}{{0, 1}, {999, 1}, {1000, 2}, {2999, 2}, {3000, 3}, {6000, 4}}
	for _, c := range cases {
		if got := LevelFromXP(c.xp); got != c.level {
			t.Errorf("LevelFromXP(%d) = %d, want %d", c.xp, got, c.level)
		}
	}
}
