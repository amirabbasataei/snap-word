# CLAUDE.md — WordChain Project

This file is read by Claude Code at the start of every session.
**Always read this file first. Never skip a phase. Never implement ahead of the current phase.**

---

## 📌 Project Summary

A production-ready word-chain mobile game (Shiritori-style).
- Player enters a word starting with the last letter of the previous word
- Words must be valid (dictionary-checked), no repetition allowed
- Two orthogonal axes:
  - **Opponent**: Solo (vs self), AI (Easy/Medium/Hard), or 1v1 Real-time multiplayer
  - **Match variant**: Classic, Time Attack, or Daily Challenge (see Game Modes & Rules below)

---

## 📊 Phase Status

Update this table when a phase is completed. Source of truth — keep in sync with the per-phase status lines below.

| # | Phase | Status |
|---|---|---|
| 1 | Foundation & Database | [ ] Not started |
| 2 | Backend: Dictionary & Game Engine | [ ] Not started |
| 3 | Backend: Auth | [ ] Not started |
| 4 | Backend: Game REST API & Match Repository | [ ] Not started |
| 5 | Backend: WebSocket & Multiplayer | [ ] Not started |
| 6 | Backend: Matchmaking & AI Opponent | [ ] Not started |
| 7 | Backend: Leaderboard | [ ] Not started |
| 8 | Flutter: Core Setup | [ ] Not started |
| 9 | Flutter: Auth Feature | [ ] Not started |
| 10 | Flutter: Game Feature (Solo) | [ ] Not started |
| 11 | Flutter: Lobby & Multiplayer | [ ] Not started |
| 12 | Flutter: Leaderboard & Profile | [ ] Not started |
| 13 | Monetization Hooks & Final Wiring | [ ] Not started |

---

## 🧱 Tech Stack

| Layer | Choice |
|---|---|
| Mobile | Flutter — feature-based, flutter_bloc/cubit, go_router, dio, get_it |
| Backend | Go — Gin, handler→service→repository (no domain layer) |
| Realtime | WebSocket (gorilla/websocket) |
| Database | PostgreSQL 16 |
| Cache | Redis 7 |
| Dictionary | Hybrid — Flutter `HashSet<String>` (solo/AI, instant, offline) + Go `map[string]struct{}` (multiplayer, authoritative) |
| Auth | JWT (access + refresh tokens) |
| Migrations | `golang-migrate/migrate` (numbered `NNN_name.up.sql` / `.down.sql`) |
| Logging | Go: `slog` (structured JSON in prod, text in dev). Flutter: `logger` package. |

---

## 📁 Final Project Structure (target)

```
wordchain/
├── CLAUDE.md                  ← this file
├── .env.example               ← all required env vars (see appendix)
├── backend/
│   ├── cmd/server/main.go
│   ├── internal/
│   │   ├── config/
│   │   ├── handler/
│   │   ├── service/
│   │   ├── repository/
│   │   ├── ws/
│   │   ├── engine/
│   │   │   └── data/enable.txt   ← bundled wordlist (Go side)
│   │   └── middleware/
│   ├── migrations/
│   ├── Dockerfile
│   └── docker-compose.yml
└── frontend/
    ├── pubspec.yaml
    ├── assets/
    │   └── words/enable.txt      ← bundled wordlist (Flutter side)
    └── lib/
        ├── main.dart
        ├── core/
        │   ├── di/
        │   ├── network/
        │   ├── router/
        │   ├── services/
        │   │   ├── dictionary_service.dart   ← ENABLE wordlist, loaded at startup
        │   │   ├── websocket_service.dart
        │   │   └── monetization_service.dart
        │   └── theme/
        └── features/
            ├── auth/
            ├── home/
            ├── game/
            ├── lobby/
            ├── leaderboard/
            └── profile/
```

---

## 📐 Coding Rules (apply in every session)

- Backend: strictly 3 layers — `handler → service → repository`. No domain layer.
- Frontend: feature-based folders only. No forced layered architecture per feature.
- Each feature only has what it needs: `cubit/` or `bloc/`, `data/`, `view/`.
- Use `get_it` for all DI. Never use `Provider` or `InheritedWidget` for DI.
- Use `go_router` for all navigation. Never call `Navigator.push` directly.
- Use a single `dio` instance registered in `get_it`, with an auth interceptor.
- WebSocket logic lives in `core/services/websocket_service.dart` only.
- Dictionary validation is **hybrid**: Flutter `DictionaryService` (HashSet) for solo/AI — instant, offline, no server call. Go `map[string]struct{}` for multiplayer — server is the authority, client cannot be trusted.
- Solo and vs-AI games run **entirely on-device**. The server is not involved in word validation for those modes.
- Add comments only where logic is non-obvious.
- Write clean, readable, production-quality code. Avoid over-engineering.

### Error handling
- **Go**: wrap errors with `fmt.Errorf("...: %w", err)`. Handlers translate errors to HTTP via a single `respondError` helper. Define sentinel errors in the service layer (e.g., `ErrInvalidWord`, `ErrNotYourTurn`); handlers map them to status codes.
- **Flutter**: repositories throw typed exceptions (`AuthException`, `NetworkException`, `ValidationException`). Cubits/Blocs catch and emit error states. Never let an exception bubble into the widget tree.

### Logging
- **Go**: `slog` only. Structured fields, no `fmt.Println`. Log at boundaries (handler entry, repo errors, WS events). No PII or passwords in logs.
- **Flutter**: `logger` package. Levels: `v`/`d`/`i`/`w`/`e`. Strip verbose logs in release builds via build flags.

---

## 🎮 Game Modes & Rules

### Match variants

| Variant | Description | Turn timer | End condition |
|---|---|---|---|
| **Classic** | Standard chain. No clock pressure beyond per-turn timer. | 15s per turn | First invalid/timeout move loses (multiplayer) or ends round (solo) |
| **Time Attack** | Race the clock — score as much as possible in a fixed total time. | 8s per turn | Total match time hits 90s; highest score wins |
| **Daily Challenge** | Single seeded run, one attempt per UTC day, server-tracked. | 15s per turn | First mistake or after 20 words; score posted to a daily leaderboard |

Defaults above are tunable in `internal/config/config.go` and on the Flutter side via a `GameConfig` constant. Do not hardcode magic numbers in handlers, blocs, or widgets — read them from config.

### Word validation rules
Apply identically in Go and Flutter (`engine.ValidateMove` and `DictionaryService.isValid`):

1. **Normalize**: trim whitespace, lowercase. Compare normalized form against the dictionary (the wordlist is stored lowercase).
2. **Allowed characters**: `[a-z]` only. Reject anything containing digits, spaces, hyphens, or apostrophes — the ENABLE wordlist already excludes these.
3. **Minimum length**: 3 letters. Reject shorter inputs with reason `too_short`.
4. **Starting letter**: must equal the last letter of the previous accepted word (case-insensitive after normalization). First word of the chain has no starting-letter constraint.
5. **No repetition**: track `usedWords` per match; reject duplicates with reason `already_used`.
6. **Dictionary check**: must exist in the ENABLE wordlist. No proper nouns; ENABLE excludes them.

### Streak rules
A **streak** is the count of consecutive successful word submissions **by the same player within a single match**. Reset to 0 on any rejection or timeout. Streak does not carry across matches. The `streak_bonus` in the scoring formula uses the count *before* the current word is added (so the 3rd consecutive correct word gets the bonus, not the 4th).

### Solo end conditions
Solo is single-player practice with no opponent. The match ends when **any** of:
- The player submits an invalid word (mistake)
- The per-turn timer hits 0
- The player taps "End game" in the UI

Final score and chain length are saved to the backend for authenticated users; guests see them in-session only.

---

## 🗄️ Database Schema (reference — implemented in Phase 1)

```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(32) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    coins INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE matches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    mode VARCHAR(20) NOT NULL,
    status VARCHAR(20) NOT NULL,
    winner_id UUID REFERENCES users(id),
    game_state JSONB,
    started_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE match_players (
    match_id UUID REFERENCES matches(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id),
    score INTEGER DEFAULT 0,
    is_ai BOOLEAN DEFAULT false,
    joined_at TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (match_id, user_id)
);

CREATE TABLE player_stats (
    user_id UUID PRIMARY KEY REFERENCES users(id),
    total_matches INTEGER DEFAULT 0,
    wins INTEGER DEFAULT 0,
    longest_word TEXT,
    best_streak INTEGER DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE powerup_inventory (
    user_id UUID REFERENCES users(id),
    powerup_type VARCHAR(20) NOT NULL,
    quantity INTEGER DEFAULT 0,
    PRIMARY KEY (user_id, powerup_type)
);

CREATE TABLE daily_challenges (
    challenge_date DATE PRIMARY KEY,
    seed BIGINT NOT NULL,
    start_letter CHAR(1) NOT NULL
);

CREATE TABLE daily_challenge_attempts (
    user_id UUID REFERENCES users(id),
    challenge_date DATE REFERENCES daily_challenges(challenge_date),
    score INTEGER NOT NULL,
    chain_length INTEGER NOT NULL,
    completed_at TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (user_id, challenge_date)
);
```

---

## 🌐 REST API Conventions

- Base path: `/api/v1/`
- Auth header: `Authorization: Bearer <jwt>`
- Content type: `application/json`
- Standard success envelope:
  ```json
  { "data": { ... } }
  ```
- Standard error envelope:
  ```json
  { "error": { "code": "invalid_word", "message": "human readable" } }
  ```
- Status code map:
  - `400` validation / malformed request
  - `401` missing or invalid JWT
  - `403` authenticated but not allowed (e.g., guest hitting a registered-only route)
  - `404` resource not found
  - `409` conflict (e.g., duplicate username, daily challenge already attempted)
  - `429` rate limited
  - `500` server error
- All write endpoints rate-limited via Redis (token bucket per user/IP). Default: 60 req/min per user.

---

## 🌐 WebSocket Event Protocol (reference)

```
Client → Server:
  { "type": "submit_word",  "word": "apple" }
  { "type": "use_powerup",  "powerup": "freeze" }
  { "type": "ping" }

Server → Client:
  { "type": "game_start",            "state": { ... } }
  { "type": "word_accepted",         "word": "apple", "score": 85, "next_letter": "e" }
  { "type": "word_rejected",         "reason": "not_in_dictionary" | "wrong_letter" | "already_used" | "too_short" }
  { "type": "turn_change",           "player_id": "..." }
  { "type": "timer_update",          "remaining_ms": 7400 }
  { "type": "powerup_used",          "powerup": "freeze", "by": "..." }
  { "type": "game_over",             "winner": "...", "scores": { ... } }
  { "type": "opponent_disconnected" }
  { "type": "pong" }
```

Client reconnect: on socket close during an active match, attempt to reconnect with exponential backoff (1s, 2s, 4s, capped at 8s) for up to 30 seconds. After 30s, treat the match as forfeited. Server holds the room open for the same 30s grace window (see Phase 5).

---

## 💰 Scoring Formula (reference)

```
base_score   = word.length × 10
speed_bonus  = max(0, (time_limit - response_time_sec) × 2)
streak_bonus = streak >= 3 ? base_score × 0.5 : 0
rarity_bonus = word_frequency_rank > 10000 ? 20 : 0
turn_score   = base_score + speed_bonus + streak_bonus + rarity_bonus
```

`time_limit` is the turn timer for the current match variant (see Game Modes & Rules). `streak` is the count of consecutive successes by the player in this match *before* this word. `word_frequency_rank` uses a precomputed frequency list bundled alongside the wordlist; missing entries are treated as rank `infinity` (i.e., always rare).

---

## 🔐 Guest Mode & Auth Strategy

**Core principle: never block a player from playing before they're hooked.**

### What guests can do (no account required)
- Play Solo (vs self, infinite rounds) — fully offline, no server calls
- Play vs AI (Easy / Medium / Hard) — fully offline, no server calls
- Use a limited set of power-ups (session-only, not persisted across restarts)
- See their current session score

### What requires registration
- Online multiplayer (1v1 real-time)
- Persistent stats & streaks (saved across sessions)
- Leaderboard participation
- Persistent coin balance and power-up inventory
- Daily Challenge (server-tracked to prevent replay)

### Guest power-up allowance
Guests receive **5 Hint uses per session** (in-memory only, reset on app restart).  
All other power-ups (Freeze, Extra Time, Shield) are registered-only because they either affect an opponent or require persistent inventory tracking.  
When a guest taps a locked power-up, show a soft upsell: *"Save your progress and unlock power-ups — it's free!"* with a Register button. Never hard-block or show a paywall.

### Auth flow
```
App launch
  ├── Stored JWT valid?  → go to /home (full features)
  ├── No token?          → go to /home (guest mode, limited features)
  └── Token expired?     → attempt silent refresh → success: /home | fail: /home (guest)

User taps "Find Match" or "Leaderboard"
  └── Not authenticated? → redirect to /login with return route
      After login        → return to original destination
```

### Implementation note
`AuthCubit` must expose an `isGuest` flag. All screens that need auth gate their features
behind this flag — they do **not** redirect unconditionally. Only the multiplayer queue
and leaderboard write path force a login redirect.

---

## 💸 Monetization Model

The game uses a **hybrid freemium** model: ads + soft IAP. No hard paywalls. No pay-to-win.

### Revenue streams (in priority order)

| # | Stream | Implementation |
|---|---|---|
| 1 | **Rewarded ads** | Watch ad → earn 20 coins or revive after a loss. 62% of word game ad revenue. Highest player acceptance. |
| 2 | **Coin IAP bundles** | Small / Medium / Large packs ($0.99 / $2.99 / $9.99). Coins buy power-ups, extra continues. |
| 3 | **Remove Ads IAP** | One-time purchase (~$2.99). Removes interstitial ads; rewarded ads stay (player-initiated). |
| 4 | **Premium subscription** | ~$3.99/month. No ads + 200 coins/week + exclusive board themes. |
| 5 | **Cosmetics** | Board themes, word-chain color palettes, avatar frames. Purely visual, never affect gameplay. |

### Coin economy
```
Earn coins:
  - Win a match:            +30 coins
  - Daily login bonus:      +10 coins
  - Watch rewarded ad:      +20 coins
  - Achieve a streak ≥ 5:   +15 coins

Spend coins:
  - Hint power-up:          10 coins per use
  - Freeze opponent:        20 coins per use
  - Extra Time:             15 coins per use
  - Continue after loss:    25 coins (vs ad-based continue)
```

### What NOT to do
- No pay-to-win mechanics (power-ups in multiplayer must be earned/limited, not buyable in unlimited quantities)
- No energy systems or artificial wait timers — word games succeed on session frequency, not artificial scarcity
- No interstitial ads during an active game — only between sessions or on game-over screen

---

## 🧪 Testing Strategy

Tests are written **inside the phase that introduces the code**, not as a separate phase.

### Backend (Go)
- **Unit tests** for every file in `internal/engine/` and `internal/service/` — required to mark a phase complete.
- **Repository tests** use a real Postgres test container (or `testcontainers-go`); no mocked DB.
- **Handler tests** use `httptest` against the Gin router with a stubbed service layer.
- **WebSocket tests** spin up `httptest.Server` and connect a real client.
- Target ≥ 70% coverage on `engine/` and `service/`.

### Frontend (Flutter)
- **Widget tests** for each screen's primary states (loading, success, error, empty).
- **Bloc/Cubit tests** using `bloc_test` for every state transition.
- **Golden tests** for `WordChainList` and `TimerBar` (visual regression).
- Mock `DictionaryService` and `WebSocketService` in widget tests; do not load the real wordlist.

### Integration
- Final integration check is part of Phase 13. End-to-end smoke flow: guest → solo → game over → rewarded ad → continue; registered → queue → match → game → leaderboard.

---

## 🗺️ Implementation Phases

> **How to use:**
> At the start of each session, tell Claude Code:
> *"Read CLAUDE.md and implement Phase N."*
> Mark the phase `[x]` in both the status table at the top and the per-phase status line when complete.

---

### Phase 1 — Foundation & Database
**Status: [ ] Not started**

**Scope:**
- Create the monorepo folder structure (`backend/`, `frontend/`)
- Write the full textual architecture diagram covering all components and data flows (save as `backend/ARCHITECTURE.md`)
- Initialize the Go module (`go.mod`) with all required dependencies
- Write `internal/config/config.go` — load from environment variables (see Appendix: Environment Variables)
- Write `migrations/001_init.sql` (and `001_init.down.sql`) — full schema from the reference above
- Write `docker-compose.yml` — services: app, postgres, redis
- Write backend `Dockerfile`
- Write `cmd/server/main.go` — wire config, DB connection, Redis connection, and start Gin router (empty routes for now, plus `GET /health`)
- Write `.env.example` at repo root

**Done when:** `docker-compose up` starts all three services, Go server boots and responds to `GET /health` with `200 OK`.

---

### Phase 2 — Backend: Dictionary & Game Engine
**Status: [ ] Not started**

**Note:** The Go dictionary is used **only for multiplayer validation** (the server is the authority; clients can be tampered with). Solo and vs-AI games validate entirely on the Flutter client via `DictionaryService`. Both sides load the same ENABLE wordlist.

**Scope:**
- `internal/engine/dictionary.go` — embed the ENABLE wordlist as a `.txt` file in `internal/engine/data/`; load into `map[string]struct{}` at startup; expose `IsValid(word string) bool`
- `internal/engine/validator.go` — `ValidateMove(prevWord, newWord string, usedWords map[string]bool) error` covering: normalization, allowed characters, min length, correct starting letter, valid dictionary word, not already used (per Word Validation Rules above)
- `internal/engine/scorer.go` — `CalculateScore(word string, responseTimeSec float64, streak int, timeLimitSec float64) int` using the formula above
- Unit tests for all three engine files

**Done when:** All engine unit tests pass. Dictionary loads without error. Validator correctly rejects bad moves with typed sentinel errors.

---

### Phase 3 — Backend: Auth
**Status: [ ] Not started**

**Scope:**
- `internal/repository/user.go` — `CreateUser`, `GetUserByEmail`, `GetUserByID`
- `internal/service/auth.go` — `Register`, `Login`, `RefreshToken` (bcrypt password hashing, JWT generation)
- `internal/handler/auth.go` — `POST /api/v1/auth/register`, `POST /api/v1/auth/login`, `POST /api/v1/auth/refresh`
- `internal/middleware/auth.go` — JWT validation middleware for protected routes
- Password policy: minimum 8 characters, at least one letter and one digit. Username: 3–32 chars, `[a-zA-Z0-9_]`.

**Done when:** Register and login return valid JWTs. Protected route returns 401 without token. Invalid passwords are rejected with 400 + descriptive error.

---

### Phase 4 — Backend: Game REST API & Match Repository
**Status: [ ] Not started**

**Scope:**
- `internal/repository/match.go` — `CreateMatch`, `GetMatch`, `UpdateMatchStatus`, `SaveGameState`, `GetMatchPlayers`
- `internal/repository/stats.go` — `UpsertStats`, `GetStats`
- `internal/service/game.go` — `CreateSoloGame`, `GetGameState`, `EndGame`, `UpdateStats`
- `internal/handler/game.go` — REST endpoints:
  - `POST /api/v1/game/solo` — start a solo game
  - `GET  /api/v1/game/:id` — get match state
  - `GET  /api/v1/profile/stats` — get current user's stats
- `internal/handler/powerup.go` — `POST /api/v1/powerup/use` (validates inventory, deducts, applies)

**Done when:** Can create a solo game, retrieve its state, and use a power-up via REST.

---

### Phase 5 — Backend: WebSocket & Multiplayer
**Status: [ ] Not started**

**Scope:**
- `internal/ws/client.go` — WebSocket client wrapper (read/write pumps, ping/pong)
- `internal/ws/room.go` — game room: holds 2 clients, manages turn state, dispatches typed events, handles reconnection (30s grace window)
- `internal/ws/hub.go` — central hub: manages all rooms, routes messages, cleans up finished rooms
- `internal/handler/ws.go` — `GET /api/v1/ws/game/:roomID` — upgrades connection, registers client with hub
- Integrate engine validator and scorer into room turn logic
- Handle: timeout (auto-loss), invalid word, win/loss, opponent disconnect

**Done when:** Two clients can connect to the same room, exchange valid words, and receive `game_over` when one fails.

---

### Phase 6 — Backend: Matchmaking & AI Opponent
**Status: [ ] Not started**

**Scope:**
- `internal/service/matchmaking.go` — Redis List queue per mode; background goroutine polls every 500ms; pairs two players → creates room → notifies via WS; falls back to AI after 30s wait
- `internal/handler/game.go` additions — `POST /api/v1/match/queue`, `DELETE /api/v1/match/queue`
- `internal/service/ai.go` — AI player struct with difficulty config:
  ```
  Easy:   3s delay,  25% mistake rate, min word length 3
  Medium: 1.5s delay, 10% mistake rate, min word length 4
  Hard:   0.6s delay,  2% mistake rate, min word length 6
  ```
  AI picks a valid word from the dictionary filtered by required starting letter, applies mistake probability, waits simulated delay, submits via the room's input channel

**Done when:** Matchmaking pairs two real clients. Solo vs AI works at all three difficulty levels.

---

### Phase 7 — Backend: Leaderboard
**Status: [ ] Not started**

**Scope:**
- `internal/service/leaderboard.go` — Redis Sorted Set (`leaderboard:global:weekly`): `AddScore`, `GetTopN(n int)`, `GetPlayerRank(userID string)`
- Call `AddScore` at game end in the room's win/loss handler
- `internal/handler/leaderboard.go` — `GET /api/v1/leaderboard?limit=100` returns top N with rank + score + username

**Done when:** Leaderboard endpoint returns correct ranked list after a few completed games.

---

### Phase 8 — Flutter: Core Setup
**Status: [ ] Not started**

**Scope:**
- Initialize Flutter project in `frontend/`
- Add dependencies to `pubspec.yaml`: `flutter_bloc`, `go_router`, `dio`, `get_it`, `equatable`, `web_socket_channel`, `shared_preferences`, `logger`
- `core/di/injection.dart` — register all services and repositories with `get_it`
- `core/network/dio_client.dart` — single `Dio` instance, base URL from env/config, auth interceptor (attaches JWT, handles 401 → refresh token)
- `core/network/api_endpoints.dart` — all endpoint constants
- `core/router/app_router.dart` — all routes via `go_router`: `/login`, `/register`, `/home`, `/game/:id`, `/lobby`, `/leaderboard`, `/profile`
- `core/services/websocket_service.dart` — connect, disconnect, send, stream of incoming typed events
- `core/services/dictionary_service.dart` — load ENABLE wordlist from `assets/words/enable.txt` into a `HashSet<String>` at app startup; expose `isValid(String word) bool` and `suggestWords(String startLetter) List<String>` (used by the Hint power-up). Register as a singleton in `get_it`. Call `load()` in `main()` before `runApp()`.
- `core/theme/app_theme.dart` — light/dark theme
- Bundle `assets/words/enable.txt` (~170k words, ~1.7 MB plain / ~500 KB gzipped) in `pubspec.yaml` assets

**Done when:** App builds, navigates between placeholder screens, DI resolves without errors, `DictionaryService` loads and `isValid("apple")` returns true.

---

### Phase 9 — Flutter: Auth Feature
**Status: [ ] Not started**

**Scope:**
- `features/auth/data/auth_repository.dart` — `register`, `login`, `refreshToken`; persist JWT in `shared_preferences`
- `features/auth/cubit/auth_cubit.dart` + `auth_state.dart` — states: `AuthInitial`, `AuthLoading`, `AuthGuest`, `AuthAuthenticated`, `AuthError`
  - `AuthGuest`: no token; user can play solo/AI; multiplayer and leaderboard are locked
  - `AuthAuthenticated`: valid JWT; all features unlocked
- `features/auth/view/login_screen.dart` — email + password fields, login button, link to register, **"Continue as Guest"** text button (navigates to `/home` in guest mode)
- `features/auth/view/register_screen.dart` — username + email + password, register button, "Continue as Guest" link
- App startup logic:
  - Valid JWT found → emit `AuthAuthenticated` → `/home`
  - No token or expired (refresh failed) → emit `AuthGuest` → `/home` (guest mode, no redirect to login)
  - Player taps "Find Match" or "Leaderboard" while guest → redirect to `/login?return=/lobby`

**Done when:** Guest can reach home and play solo without logging in. Registered user's token survives restart. Multiplayer tap redirects guest to login.

---

### Phase 10 — Flutter: Game Feature (Solo)
**Status: [ ] Not started**

**Important:** Solo and vs-AI games are **fully on-device**. No server calls for word validation — use `DictionaryService` (injected via `get_it`). The backend is not involved. This means guests can play without any network connection.

**Scope:**
- `features/game/data/game_repository.dart` — `startSoloGame`, `getGame`, `usePowerup` (REST calls only for authenticated users saving state; guests play in-memory only)
- `features/game/bloc/game_bloc.dart` + events + states — states: `GameInitial`, `GameLoading`, `GameActive`, `GameOver`, `GameError`
- Events: `GameStarted`, `WordSubmitted`, `PowerupUsed`, `TimerTicked`, `GameEnded`
- `features/game/view/game_screen.dart` — show current word chain, required starting letter, score, timer bar
- `features/game/view/widgets/word_input.dart` — text field with submit button; validates locally via `DictionaryService` with zero latency; disable during opponent turn
- `features/game/view/widgets/word_chain_list.dart` — scrollable list of played words with player labels
- `features/game/view/widgets/timer_bar.dart` — animated countdown bar
- Wire `GameBloc` to `WebSocketService` only for multiplayer; solo uses no WebSocket
- Implement solo end conditions per Game Modes & Rules: invalid word, timeout, or manual "End game" tap
- Guest power-up logic: allow 5 Hint uses per session (tracked in `GameBloc` state, not persisted); show soft upsell prompt ("Register to save your progress and unlock more power-ups") when guest uses their last hint or taps a locked power-up

**Done when:** Solo game is fully playable by a guest with zero login friction. `DictionaryService` validates all words locally. All three end conditions trigger `GameOver` correctly.

---

### Phase 11 — Flutter: Lobby & Multiplayer
**Status: [ ] Not started**

**Scope:**
- `features/lobby/data/` — `joinQueue`, `cancelQueue`
- `features/lobby/cubit/lobby_cubit.dart` — states: `LobbyIdle`, `LobbySearching`, `LobbyMatchFound`, `LobbyError`
- `features/lobby/view/lobby_screen.dart` — mode selector (Classic / Time Attack / Daily), difficulty selector (for AI), Find Match button, searching animation, cancel button
- On `LobbyMatchFound`, navigate to `/game/:id`
- Add `features/home/view/home_screen.dart` — buttons for Solo vs AI, Find Match, Daily Challenge, Leaderboard, Profile

**Done when:** Player can queue, be matched, and land in a live game room.

---

### Phase 12 — Flutter: Leaderboard & Profile
**Status: [ ] Not started**

**Scope:**
- `features/leaderboard/cubit/leaderboard_cubit.dart` — fetch top 100, find current user's rank
- `features/leaderboard/view/leaderboard_screen.dart` — ranked list with avatar placeholder, username, score; highlight current user's row
- `features/profile/cubit/profile_cubit.dart` — fetch stats (total matches, wins, best streak, longest word, coin balance)
- `features/profile/view/profile_screen.dart` — stats display, power-up inventory, coin balance

**Done when:** Leaderboard and profile screens display real data from the backend.

---

### Phase 13 — Monetization Hooks & Final Wiring
**Status: [ ] Not started**

**Scope:**
- `core/services/monetization_service.dart` — abstract class + mock implementation:
  - `showRewardedAd() → Future<bool>` — returns true if user watched the full ad
  - `showInterstitialAd()` — called between sessions (game over → home), never mid-game
  - `getProducts() → Future<List<Product>>`
  - `purchase(productId) → Future<PurchaseResult>`
  - `spendCoins(int amount) → bool` — returns false if insufficient balance
  - `awardCoins(int amount)`
- Register `MockMonetizationService` in `get_it` (swap for real SDK — AdMob + RevenueCat — in production)
- **Game-over screen additions:**
  - "Watch Ad to Continue" button (calls `showRewardedAd`; on success, resume game with 50% timer restored)
  - "Use 25 coins to continue" button (registered users only; calls `spendCoins(25)`)
  - Show interstitial ad when returning to home (not when continuing)
- **Profile screen additions:**
  - Coin balance display
  - "Buy Coins" button — shows product list (mock prices: $0.99 / $2.99 / $9.99)
  - "Remove Ads" one-time purchase button
  - "Premium — $3.99/mo" subscription button with feature list
- **Power-up upsell:** when guest uses last free hint, show bottom sheet: *"Register free to save progress + unlock more power-ups"*
- Backend `internal/service/monetization.go` — `AwardCoins`, `SpendCoins`, `ValidateReceipt` (stub; real receipt validation added when integrating store SDKs)
- Final integration test: full flow from guest → solo game → game over → rewarded ad → continue; and register → queue → match → game → game over → leaderboard

**Done when:** All screens are connected, no placeholder crashes, the full game loop (guest and registered) runs end-to-end. Coin balance updates after rewarded ad.

---

## 🔁 Session Workflow

Each time you start a new Claude Code session:

1. Point Claude Code at this file: *"Read CLAUDE.md"*
2. State the phase: *"Implement Phase N — [title]"*
3. After the phase is complete, update **both** the status line under the phase **and** the Phase Status table at the top of this file from `[ ] Not started` to `[x] Complete`
4. Commit the code before starting the next session

---

## ⚠️ Important Notes for Claude Code

- **Never implement anything outside the current phase's scope.** If you notice something missing from a previous phase, flag it but do not fix it silently.
- **Always check previous phases' output** before writing new code that depends on it (e.g., check actual repository method signatures before calling them in a service).
- **Keep the CLAUDE.md status table and per-phase status lines in sync** after completing each phase.
- **Dictionary is dual:** embed `enable.txt` both in `internal/engine/data/` (Go, for multiplayer) and in `assets/words/enable.txt` (Flutter, for solo/AI). Same file, two copies.
- **Never require login to start a solo or vs-AI game.** Guest mode is a first-class state. Any screen that forces login before solo play is a bug.
- **Do not hardcode game tuning values** (timers, scores, AI difficulty). Read them from config on the Go side and a `GameConfig` constant on the Flutter side.
- For local development, backend port is `8080`, Postgres is `5432`, Redis is `6379`.

---

## 📎 Appendix: Environment Variables

All env vars are loaded by `internal/config/config.go`. A complete `.env.example` lives at the repo root.

| Variable | Required | Example | Notes |
|---|---|---|---|
| `PORT` | yes | `8080` | HTTP port |
| `DATABASE_URL` | yes | `postgres://user:pass@localhost:5432/wordchain?sslmode=disable` | Postgres DSN |
| `REDIS_URL` | yes | `redis://localhost:6379/0` | Redis DSN |
| `JWT_SECRET` | yes | (random 32+ bytes) | HS256 signing secret |
| `JWT_ACCESS_TTL` | no | `15m` | Access token lifetime |
| `JWT_REFRESH_TTL` | no | `720h` | Refresh token lifetime (30 days) |
| `LOG_LEVEL` | no | `info` | `debug` / `info` / `warn` / `error` |
| `ENV` | no | `dev` | `dev` / `prod` — controls log format (text vs JSON) |
| `CORS_ORIGINS` | no | `http://localhost:*` | Comma-separated allowed origins |

---

## 📎 Appendix: Dictionary

- **Source**: ENABLE (Enhanced North American Benchmark Lexicon), public domain, ~172,820 words.
- **Format**: one lowercase word per line, ASCII only, no proper nouns, no contractions.
- **Storage**: same file at `backend/internal/engine/data/enable.txt` and `frontend/assets/words/enable.txt`. Keep them byte-identical — add a CI check in a later iteration if drift becomes a concern.
- **Loading**: Go side loads into `map[string]struct{}` at server startup (one-time cost). Flutter side loads into `HashSet<String>` in `DictionaryService.load()` before `runApp()`.
- **Memory footprint**: ~1.7 MB plain text; in-memory set ~6–8 MB. Acceptable on all target devices.