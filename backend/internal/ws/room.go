package ws

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"sync"
	"time"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/engine"
	"wordchain/backend/internal/repository"
)

const maxPlayers = 2

type roomState string

const (
	stateWaiting     roomState = "waiting"
	stateActive      roomState = "active"
	stateContinueWin roomState = "continue_window"
	stateFinished    roomState = "finished"
)

// inMsg is the JSON envelope for client→server messages.
type inMsg struct {
	Type    string `json:"type"`
	Word    string `json:"word"`
	Powerup string `json:"powerup"`
	Method  string `json:"method"` // "ad" | "coins" for continue
}

// outMsg is the JSON envelope for server→client messages.
// Fields are omitted when zero-valued except those that can legitimately be zero.
type outMsg struct {
	Type        string          `json:"type"`
	Word        string          `json:"word,omitempty"`
	Score       int             `json:"score,omitempty"`
	NextLetter  string          `json:"next_letter,omitempty"`
	PlayerID    string          `json:"player_id,omitempty"`
	Reason      string          `json:"reason,omitempty"`
	RemainingMs int64           `json:"remaining_ms,omitempty"`
	DeadlineMs  int64           `json:"deadline_ms,omitempty"`
	Decision    string          `json:"decision,omitempty"`
	Powerup     string          `json:"powerup,omitempty"`
	By          string          `json:"by,omitempty"`
	Winner      string          `json:"winner,omitempty"`
	Scores      map[string]int  `json:"scores,omitempty"`
	State       *gameStartState `json:"state,omitempty"`
	Hint        string          `json:"hint,omitempty"`
}

type gameStartState struct {
	MatchID     string         `json:"match_id"`
	Mode        string         `json:"mode"`
	Players     []string       `json:"players"`
	CurrentTurn string         `json:"current_turn"`
	Chain       []string       `json:"chain"`
	Scores      map[string]int `json:"scores"`
	NextLetter  string         `json:"next_letter,omitempty"`
}

// PowerupDeductor deducts one power-up use from a player's inventory.
// Implemented by service.PowerupService — defined here as an interface so the
// ws package does not need to import the service package.
type PowerupDeductor interface {
	UseItem(ctx context.Context, userID, powerupType string) (int, error)
}

// RoomDeps holds the external dependencies a room needs for DB interactions.
// All fields may be nil in tests that exercise in-memory logic only.
type RoomDeps struct {
	MatchRepo  *repository.MatchRepository
	PowerupSvc PowerupDeductor
}

// Room manages a single multiplayer game session.
// All mutable state is guarded by mu; broadcast / sendTo write only to buffered
// channels and are therefore safe to call while mu is held.
type Room struct {
	id   string
	mode string
	hub  *Hub
	deps RoomDeps

	mu sync.Mutex

	state       roomState
	playerOrder []string           // len=2 once the game starts; determines turn order
	clients     map[string]*Client // userID → currently connected client

	// 30-second reconnect grace: cancel func keyed by disconnected userID
	disconnectCancel map[string]context.CancelFunc

	// game state
	chain         []string
	usedWords     map[string]bool
	scores        map[string]int
	streaks       map[string]int
	continueUsed  map[string]bool
	currentTurn   int       // index into playerOrder
	turnStartTime time.Time
	turnDeadline  time.Time

	// powerup state
	powerupUsedInMatch map[string]map[string]bool // userID → type → used this match
	shieldActive       map[string]bool
	freezePending      string // userID whose next turn gets +5 s

	// continue state
	pendingLossPlayer string

	// stale-timer guards: incremented to invalidate sleeping goroutines
	turnSeq     int
	matchSeq    int
	continueSeq int

	// cancel func for the periodic timer-update goroutine
	timerUpdateCancel context.CancelFunc
}

func newRoom(id, mode string, hub *Hub, deps RoomDeps) *Room {
	return &Room{
		id:                 id,
		mode:               mode,
		hub:                hub,
		deps:               deps,
		state:              stateWaiting,
		clients:            make(map[string]*Client),
		disconnectCancel:   make(map[string]context.CancelFunc),
		chain:              []string{},
		usedWords:          make(map[string]bool),
		scores:             make(map[string]int),
		streaks:            make(map[string]int),
		continueUsed:       make(map[string]bool),
		powerupUsedInMatch: make(map[string]map[string]bool),
		shieldActive:       make(map[string]bool),
	}
}

// Join registers a client with the room. On the second player it starts the game.
// Reconnecting players (already in playerOrder) receive the current game state.
func (r *Room) Join(client *Client) error {
	r.mu.Lock()
	defer r.mu.Unlock()

	// Reconnect path
	for _, pid := range r.playerOrder {
		if pid == client.userID {
			if cancel, ok := r.disconnectCancel[client.userID]; ok {
				cancel()
				delete(r.disconnectCancel, client.userID)
			}
			r.clients[client.userID] = client
			slog.Info("ws: player reconnected", "room", r.id, "userID", client.userID)
			if r.state != stateFinished {
				r.sendCurrentState(client)
			}
			return nil
		}
	}

	// New player
	if r.state == stateFinished {
		return fmt.Errorf("room is finished")
	}
	if len(r.playerOrder) >= maxPlayers {
		return fmt.Errorf("room is full")
	}

	r.playerOrder = append(r.playerOrder, client.userID)
	r.clients[client.userID] = client
	r.scores[client.userID] = 0
	r.streaks[client.userID] = 0
	r.continueUsed[client.userID] = false
	r.powerupUsedInMatch[client.userID] = make(map[string]bool)

	slog.Info("ws: player joined", "room", r.id, "userID", client.userID, "count", len(r.playerOrder))

	if len(r.playerOrder) == maxPlayers {
		r.startGame()
	}
	return nil
}

// leave is called by the client's ReadPump when its connection closes.
func (r *Room) leave(client *Client) {
	r.mu.Lock()
	defer r.mu.Unlock()

	// Ignore stale client references (already replaced by a reconnect)
	if r.clients[client.userID] != client {
		return
	}
	delete(r.clients, client.userID)
	slog.Info("ws: player disconnected", "room", r.id, "userID", client.userID)

	if r.state == stateFinished || r.state == stateWaiting {
		return
	}

	r.broadcastExcept(client.userID, mustMarshal(outMsg{Type: "opponent_disconnected"}))

	// 30-second reconnect grace window
	ctx, cancel := context.WithCancel(context.Background())
	r.disconnectCancel[client.userID] = cancel
	userID := client.userID

	go func() {
		timer := time.NewTimer(30 * time.Second)
		defer timer.Stop()
		select {
		case <-ctx.Done():
			// Reconnected in time — nothing to do.
		case <-timer.C:
			r.mu.Lock()
			defer r.mu.Unlock()
			if r.state == stateFinished {
				return
			}
			r.resolveGame(r.opponentOf(userID))
		}
	}()
}

// handleMessage routes a raw JSON message from a client to the appropriate handler.
func (r *Room) handleMessage(client *Client, raw []byte) {
	var msg inMsg
	if err := json.Unmarshal(raw, &msg); err != nil {
		slog.Warn("ws: malformed message", "userID", client.userID, "error", err)
		return
	}
	switch msg.Type {
	case "submit_word":
		r.processSubmitWord(client, msg.Word)
	case "use_powerup":
		r.processUsePowerup(client, msg.Powerup)
	case "continue":
		r.processContinue(client, msg.Method)
	case "ping":
		r.sendTo(client.userID, mustMarshal(outMsg{Type: "pong"}))
	default:
		slog.Warn("ws: unknown message type", "type", msg.Type, "userID", client.userID)
	}
}

// ---- client event handlers ----

func (r *Room) processSubmitWord(client *Client, word string) {
	r.mu.Lock()
	defer r.mu.Unlock()

	if r.state != stateActive {
		return
	}
	if client.userID != r.currentPlayerID() {
		return
	}

	word = strings.ToLower(strings.TrimSpace(word))

	prevWord := ""
	if len(r.chain) > 0 {
		prevWord = r.chain[len(r.chain)-1]
	}

	if err := engine.ValidateMove(prevWord, word, r.usedWords); err != nil {
		r.broadcast(mustMarshal(outMsg{
			Type:     "word_rejected",
			Word:     word,
			Reason:   lossReason(err),
			PlayerID: client.userID,
		}))
		r.turnSeq++
		r.cancelTimerUpdates()
		r.handleLoss(client.userID, "invalid_word")
		return
	}

	// Word accepted
	responseTimeSec := time.Since(r.turnStartTime).Seconds()
	streak := r.streaks[client.userID]
	score := engine.CalculateScore(word, responseTimeSec, streak, r.turnTimerSec())

	r.chain = append(r.chain, word)
	r.usedWords[word] = true
	r.scores[client.userID] += score
	r.streaks[client.userID]++

	nextLetter := string(word[len(word)-1])

	r.turnSeq++
	r.cancelTimerUpdates()

	r.broadcast(mustMarshal(outMsg{
		Type:       "word_accepted",
		Word:       word,
		Score:      score,
		NextLetter: nextLetter,
		PlayerID:   client.userID,
	}))

	r.currentTurn = (r.currentTurn + 1) % len(r.playerOrder)
	r.startTurn()
}

func (r *Room) processUsePowerup(client *Client, powerupType string) {
	r.mu.Lock()
	defer r.mu.Unlock()

	if r.state != stateActive {
		return
	}

	switch powerupType {
	case "hint", "freeze", "extra_time", "shield":
	default:
		slog.Warn("ws: invalid powerup type", "type", powerupType, "userID", client.userID)
		return
	}

	// extra_time is only meaningful on the player's own turn
	if powerupType == "extra_time" && client.userID != r.currentPlayerID() {
		return
	}

	// Per-match limit: one use per type per player
	if r.powerupUsedInMatch[client.userID][powerupType] {
		slog.Warn("ws: powerup already used this match", "type", powerupType, "userID", client.userID)
		return
	}

	// Deduct from DB inventory
	if r.deps.PowerupSvc != nil {
		if _, err := r.deps.PowerupSvc.UseItem(context.Background(), client.userID, powerupType); err != nil {
			slog.Warn("ws: powerup deduction failed", "type", powerupType, "userID", client.userID, "error", err)
			return
		}
	}
	r.powerupUsedInMatch[client.userID][powerupType] = true

	switch powerupType {
	case "hint":
		var letter byte
		if len(r.chain) > 0 {
			last := r.chain[len(r.chain)-1]
			letter = last[len(last)-1]
		}
		hint := ""
		if letter != 0 {
			hint = engine.SuggestWord(letter, r.usedWords)
		}
		// Send hint word only to the requester; broadcast usage to everyone.
		r.sendTo(client.userID, mustMarshal(outMsg{
			Type:    "powerup_used",
			Powerup: "hint",
			By:      client.userID,
			Hint:    hint,
		}))
		r.broadcastExcept(client.userID, mustMarshal(outMsg{
			Type:    "powerup_used",
			Powerup: "hint",
			By:      client.userID,
		}))
		return

	case "freeze":
		r.freezePending = r.opponentOf(client.userID)

	case "extra_time":
		remaining := time.Until(r.turnDeadline)
		newDur := remaining + 8*time.Second
		if newDur < 0 {
			newDur = 0
		}
		r.turnDeadline = time.Now().Add(newDur)
		r.turnSeq++
		seq := r.turnSeq
		playerID := client.userID
		deadline := r.turnDeadline

		r.cancelTimerUpdates()
		go func() {
			time.Sleep(newDur)
			r.triggerTurnTimeout(seq, playerID)
		}()
		ctx, cancel := context.WithCancel(context.Background())
		r.timerUpdateCancel = cancel
		go sendTimerUpdates(r, ctx, playerID, deadline)

	case "shield":
		r.shieldActive[client.userID] = true
	}

	r.broadcast(mustMarshal(outMsg{
		Type:    "powerup_used",
		Powerup: powerupType,
		By:      client.userID,
	}))
}

func (r *Room) processContinue(client *Client, method string) {
	r.mu.Lock()
	defer r.mu.Unlock()

	if r.state != stateContinueWin || client.userID != r.pendingLossPlayer {
		return
	}
	if method != "ad" && method != "coins" {
		return
	}

	// Invalidate the continue-timeout goroutine
	r.continueSeq++

	r.continueUsed[client.userID] = true
	if r.deps.MatchRepo != nil {
		go func() {
			if err := r.deps.MatchRepo.SetContinueUsed(context.Background(), r.id, client.userID); err != nil {
				slog.Warn("ws: SetContinueUsed failed", "room", r.id, "userID", client.userID, "error", err)
			}
		}()
	}

	r.broadcast(mustMarshal(outMsg{
		Type:     "continue_decision",
		PlayerID: client.userID,
		Decision: "continue",
	}))

	r.state = stateActive
	r.pendingLossPlayer = ""
	r.startTurn() // same player's turn continues
}

// ---- game lifecycle ----

func (r *Room) startGame() {
	// Must be called with r.mu held.
	r.state = stateActive
	r.currentTurn = 0

	scoresCopy := make(map[string]int, len(r.scores))
	for k, v := range r.scores {
		scoresCopy[k] = v
	}

	r.broadcast(mustMarshal(outMsg{
		Type: "game_start",
		State: &gameStartState{
			MatchID:     r.id,
			Mode:        r.mode,
			Players:     append([]string{}, r.playerOrder...),
			CurrentTurn: r.playerOrder[0],
			Chain:       []string{},
			Scores:      scoresCopy,
		},
	}))

	// Time Attack: start the 90-second match timer.
	if r.mode == "time_attack" {
		r.matchSeq++
		seq := r.matchSeq
		go func() {
			time.Sleep(time.Duration(config.TimeAttackMatchSec) * time.Second)
			r.handleMatchTimeout(seq)
		}()
	}

	r.startTurn()
}

func (r *Room) startTurn() {
	// Must be called with r.mu held.
	playerID := r.currentPlayerID()
	turnSec := r.turnTimerSec()

	// Apply freeze bonus to this player's timer if pending.
	extraSec := 0.0
	if r.freezePending == playerID {
		extraSec = 5
		r.freezePending = ""
	}

	totalDur := time.Duration((turnSec+extraSec)*1000) * time.Millisecond
	r.turnDeadline = time.Now().Add(totalDur)
	r.turnStartTime = time.Now()
	r.turnSeq++
	seq := r.turnSeq

	r.cancelTimerUpdates()

	r.broadcast(mustMarshal(outMsg{
		Type:        "turn_change",
		PlayerID:    playerID,
		RemainingMs: totalDur.Milliseconds(),
	}))

	go func() {
		time.Sleep(totalDur)
		r.triggerTurnTimeout(seq, playerID)
	}()

	ctx, cancel := context.WithCancel(context.Background())
	r.timerUpdateCancel = cancel
	go sendTimerUpdates(r, ctx, playerID, r.turnDeadline)
}

func (r *Room) triggerTurnTimeout(seq int, playerID string) {
	r.mu.Lock()
	defer r.mu.Unlock()

	if r.turnSeq != seq || r.state != stateActive {
		return
	}
	r.cancelTimerUpdates()
	r.handleLoss(playerID, "timeout")
}

func (r *Room) handleMatchTimeout(seq int) {
	r.mu.Lock()
	defer r.mu.Unlock()

	if r.matchSeq != seq || r.state != stateActive {
		return
	}
	r.turnSeq++
	r.cancelTimerUpdates()

	winner := ""
	if len(r.playerOrder) == 2 {
		p0, p1 := r.playerOrder[0], r.playerOrder[1]
		if r.scores[p0] > r.scores[p1] {
			winner = p0
		} else if r.scores[p1] > r.scores[p0] {
			winner = p1
		}
	}
	r.resolveGame(winner)
}

func (r *Room) handleLoss(playerID, reason string) {
	// Must be called with r.mu held.

	// Shield auto-activates before the loss event.
	if r.shieldActive[playerID] {
		r.shieldActive[playerID] = false
		r.broadcast(mustMarshal(outMsg{
			Type:    "powerup_used",
			Powerup: "shield",
			By:      playerID,
		}))
		// Loss negated: switch to opponent's turn.
		r.currentTurn = (r.currentTurn + 1) % len(r.playerOrder)
		r.startTurn()
		return
	}

	r.broadcast(mustMarshal(outMsg{
		Type:     "loss_event",
		PlayerID: playerID,
		Reason:   reason,
	}))

	// If continue already used, opponent wins immediately.
	if r.continueUsed[playerID] {
		r.resolveGame(r.opponentOf(playerID))
		return
	}

	r.startContinueWindow(playerID)
}

func (r *Room) startContinueWindow(playerID string) {
	// Must be called with r.mu held.
	r.state = stateContinueWin
	r.pendingLossPlayer = playerID
	r.continueSeq++
	seq := r.continueSeq

	r.broadcast(mustMarshal(outMsg{
		Type:       "continue_window",
		PlayerID:   playerID,
		DeadlineMs: int64(config.ContinueWindowSec) * 1000,
	}))

	go func() {
		time.Sleep(time.Duration(config.ContinueWindowSec) * time.Second)
		r.triggerContinueTimeout(seq, playerID)
	}()
}

func (r *Room) triggerContinueTimeout(seq int, playerID string) {
	r.mu.Lock()
	defer r.mu.Unlock()

	if r.continueSeq != seq || r.state != stateContinueWin {
		return
	}

	r.broadcast(mustMarshal(outMsg{
		Type:     "continue_decision",
		PlayerID: playerID,
		Decision: "forfeit",
	}))
	r.resolveGame(r.opponentOf(playerID))
}

func (r *Room) resolveGame(winnerID string) {
	// Must be called with r.mu held.
	if r.state == stateFinished {
		return
	}
	r.state = stateFinished

	// Invalidate all pending timer goroutines.
	r.turnSeq++
	r.matchSeq++
	r.continueSeq++
	r.cancelTimerUpdates()

	scores := make(map[string]int, len(r.scores))
	for k, v := range r.scores {
		scores[k] = v
	}
	chain := make([]string, len(r.chain))
	copy(chain, r.chain)

	r.broadcast(mustMarshal(outMsg{
		Type:   "game_over",
		Winner: winnerID,
		Scores: scores,
	}))

	// Snapshot connected clients before releasing the lock via defer.
	snapshot := make(map[string]*Client, len(r.clients))
	for k, v := range r.clients {
		snapshot[k] = v
	}

	go r.finalizeToDB(winnerID, chain, scores)

	// Give the game_over message time to drain, then close connections.
	go func() {
		time.Sleep(2 * time.Second)
		for _, c := range snapshot {
			if c != nil {
				func() {
					defer func() { recover() }() //nolint:errcheck
					close(c.send)
				}()
			}
		}
		r.hub.RemoveRoom(r.id)
	}()
}

func (r *Room) finalizeToDB(winnerID string, chain []string, scores map[string]int) {
	if r.deps.MatchRepo == nil {
		return
	}
	ctx := context.Background()

	var winnerPtr *string
	if winnerID != "" {
		winnerPtr = &winnerID
	}
	if err := r.deps.MatchRepo.SetMatchWinner(ctx, r.id, winnerPtr); err != nil {
		slog.Error("ws: SetMatchWinner failed", "room", r.id, "error", err)
	}

	gs, _ := json.Marshal(struct {
		WordChain []string       `json:"word_chain"`
		Scores    map[string]int `json:"scores"`
	}{WordChain: chain, Scores: scores})
	if err := r.deps.MatchRepo.SaveGameState(ctx, r.id, gs); err != nil {
		slog.Error("ws: SaveGameState failed", "room", r.id, "error", err)
	}

	for playerID, score := range scores {
		if err := r.deps.MatchRepo.UpdatePlayerScore(ctx, r.id, playerID, score); err != nil {
			slog.Error("ws: UpdatePlayerScore failed", "room", r.id, "player", playerID, "error", err)
		}
	}
}

func (r *Room) sendCurrentState(client *Client) {
	// Must be called with r.mu held.
	nextLetter := ""
	if len(r.chain) > 0 {
		last := r.chain[len(r.chain)-1]
		nextLetter = string(last[len(last)-1])
	}
	scoresCopy := make(map[string]int, len(r.scores))
	for k, v := range r.scores {
		scoresCopy[k] = v
	}
	currentTurnID := ""
	if len(r.playerOrder) > r.currentTurn {
		currentTurnID = r.playerOrder[r.currentTurn]
	}
	r.sendTo(client.userID, mustMarshal(outMsg{
		Type: "game_start",
		State: &gameStartState{
			MatchID:     r.id,
			Mode:        r.mode,
			Players:     append([]string{}, r.playerOrder...),
			CurrentTurn: currentTurnID,
			Chain:       append([]string{}, r.chain...),
			Scores:      scoresCopy,
			NextLetter:  nextLetter,
		},
	}))
}

// ---- helpers ----

func (r *Room) currentPlayerID() string {
	if len(r.playerOrder) == 0 {
		return ""
	}
	return r.playerOrder[r.currentTurn]
}

func (r *Room) opponentOf(playerID string) string {
	for _, p := range r.playerOrder {
		if p != playerID {
			return p
		}
	}
	return ""
}

func (r *Room) turnTimerSec() float64 {
	if r.mode == "time_attack" {
		return float64(config.TurnTimerTimeAttackSec)
	}
	return float64(config.TurnTimerClassicSec)
}

func (r *Room) cancelTimerUpdates() {
	if r.timerUpdateCancel != nil {
		r.timerUpdateCancel()
		r.timerUpdateCancel = nil
	}
}

func (r *Room) broadcast(msg []byte) {
	for _, c := range r.clients {
		if c != nil {
			select {
			case c.send <- msg:
			default:
				slog.Warn("ws: broadcast buffer full, dropping message", "room", r.id)
			}
		}
	}
}

func (r *Room) broadcastExcept(userID string, msg []byte) {
	for uid, c := range r.clients {
		if uid != userID && c != nil {
			select {
			case c.send <- msg:
			default:
			}
		}
	}
}

func (r *Room) sendTo(userID string, msg []byte) {
	if c, ok := r.clients[userID]; ok && c != nil {
		select {
		case c.send <- msg:
		default:
			slog.Warn("ws: sendTo buffer full", "userID", userID)
		}
	}
}

// sendTimerUpdates runs as a goroutine; broadcasts remaining-time every 500 ms
// until the context is cancelled.
func sendTimerUpdates(r *Room, ctx context.Context, playerID string, deadline time.Time) {
	ticker := time.NewTicker(500 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			remaining := time.Until(deadline)
			if remaining < 0 {
				remaining = 0
			}
			r.broadcast(mustMarshal(outMsg{
				Type:        "timer_update",
				PlayerID:    playerID,
				RemainingMs: remaining.Milliseconds(),
			}))
		}
	}
}

func lossReason(err error) string {
	switch {
	case errors.Is(err, engine.ErrTooShort):
		return "too_short"
	case errors.Is(err, engine.ErrWrongLetter):
		return "wrong_letter"
	case errors.Is(err, engine.ErrAlreadyUsed):
		return "already_used"
	case errors.Is(err, engine.ErrNotInDict):
		return "not_in_dictionary"
	case errors.Is(err, engine.ErrInvalidChars):
		return "invalid_characters"
	default:
		return "invalid_word"
	}
}

func mustMarshal(v outMsg) []byte {
	b, _ := json.Marshal(v)
	return b
}
