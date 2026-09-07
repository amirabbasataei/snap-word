package engine

import "testing"

func TestIsValid(t *testing.T) {
	tests := []struct {
		word string
		want bool
	}{
		{"کتاب", true},
		{"باران", true},
		{"سلام", true},
		{"دوست", true},
		{"روباه", true},
		{"تهران", true},
		// not in dictionary
		{"زکسلوپ", false},
		{"ژژژژژژ", false},
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
		t.Fatal("dictionary is empty — fa.txt was not embedded correctly")
	}
}
