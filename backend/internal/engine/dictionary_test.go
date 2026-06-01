package engine

import "testing"

func TestIsValid(t *testing.T) {
	tests := []struct {
		word string
		want bool
	}{
		{"apple", true},
		{"eagle", true},
		{"game", true},
		{"play", true},
		{"run", true},
		{"zoo", true},
		{"hello", true},
		{"elephant", true},
		// IsValid expects pre-normalised lowercase input
		{"APPLE", false},
		{"Apple", false},
		// not in ENABLE
		{"zzzxxx", false},
		{"xyzzy", false},
		{"", false},
	}

	for _, tt := range tests {
		t.Run(tt.word, func(t *testing.T) {
			if got := IsValid(tt.word); got != tt.want {
				t.Errorf("IsValid(%q) = %v, want %v", tt.word, got, tt.want)
			}
		})
	}
}

func TestDictionaryLoaded(t *testing.T) {
	if len(dictionary) == 0 {
		t.Fatal("dictionary is empty — enable.txt was not embedded correctly")
	}
}
