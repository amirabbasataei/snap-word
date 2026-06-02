package ws

import (
	"encoding/json"
	"fmt"
	"log/slog"
	"math/rand"
	"time"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/engine"
)

// NewAIClient creates a virtual Client that drives AI moves within the room.
// The AI goroutine starts immediately. Pass the returned *Client to room.Join.
func NewAIClient(room *Room, userID, difficulty string) *Client {
	c := &Client{
		room:   room,
		userID: userID,
		conn:   nil,
		send:   make(chan []byte, 256),
	}
	go runAI(c, difficulty)
	return c
}

// runAI processes server→AI messages and fires a word submission on each
// turn_change event addressed to the AI player.
func runAI(c *Client, difficulty string) {
	cfg, ok := config.AIDifficulties[difficulty]
	if !ok {
		cfg = config.AIDifficulties["easy"]
	}

	usedWords := make(map[string]bool)
	var requiredLetter byte

	for rawMsg := range c.send {
		var m outMsg
		if err := json.Unmarshal(rawMsg, &m); err != nil {
			continue
		}
		switch m.Type {
		case "game_start":
			if m.State != nil {
				for _, w := range m.State.Chain {
					usedWords[w] = true
				}
				if n := len(m.State.Chain); n > 0 {
					last := m.State.Chain[n-1]
					requiredLetter = last[len(last)-1]
				}
			}
		case "word_accepted":
			if m.Word != "" {
				usedWords[m.Word] = true
				requiredLetter = m.Word[len(m.Word)-1]
			}
		case "turn_change":
			if m.PlayerID != c.userID {
				continue
			}
			letter := requiredLetter
			usedCopy := make(map[string]bool, len(usedWords))
			for k := range usedWords {
				usedCopy[k] = true
			}
			go aiSubmit(c, letter, usedCopy, cfg)
		}
	}
}

// aiSubmit waits the AI's configured delay then submits a word to the room.
func aiSubmit(c *Client, letter byte, usedWords map[string]bool, cfg config.AIDifficulty) {
	time.Sleep(time.Duration(cfg.DelayMs) * time.Millisecond)

	var word string
	if rand.Float64() < cfg.MistakeRate {
		word = "zqxvj" // guaranteed invalid — not in ENABLE wordlist
	} else {
		word = engine.SelectAIWord(letter, usedWords, cfg.MinWordLength, cfg.TrapPref, cfg.PreferLongest)
		if word == "" {
			word = "zqxvj" // no eligible word found — concede via invalid submission
		}
	}

	slog.Debug("ai: submitting word", "userID", c.userID, "letter", string(letter), "word", word)
	msg := fmt.Sprintf(`{"type":"submit_word","word":%q}`, word)
	c.room.handleMessage(c, []byte(msg))
}
