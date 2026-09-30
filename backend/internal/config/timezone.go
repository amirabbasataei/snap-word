package config

import "time"

// IranLocation is Iran Standard Time, UTC+03:30. Iran abolished DST in 2022,
// so a fixed offset is exact and needs no tzdata in the container.
var IranLocation = time.FixedZone("IRST", 3*3600+30*60)

// IranDate returns the Iran calendar day containing t, as midnight UTC of
// that Y-M-D — the representation used for every DATE column and date key.
func IranDate(t time.Time) time.Time {
	l := t.In(IranLocation)
	return time.Date(l.Year(), l.Month(), l.Day(), 0, 0, 0, 0, time.UTC)
}
