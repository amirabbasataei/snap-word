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
  - **Match variant**: Classic or Time Attack for all opponents; Daily Challenge is **solo-only**
- In multiplayer, both players contribute to a **single shared chain**, alternating turns

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
| 7 | Backend: Leaderboard & Streak | [ ] Not started |
| 8 | Backend: Friends & Challenges | [ ] Not started |
| 9 | Backend: Push Notifications | [ ] Not started |
| 10 | Flutter: Core Setup | [ ] Not started |
| 11 | Flutter: Auth Feature | [ ] Not started |
| 12 | Flutter: Game Feature (Solo + Tutorial) | [ ] Not started |
| 13 | Flutter: Lobby & Multiplayer | [ ] Not started |
| 14 | Flutter: Leaderboard, Friends & Profile | [ ] Not started |
| 15 | Flutter: Daily Challenge & Sharing | [ ] Not started |
| 16 | Monetization Hooks & Final Wiring | [ ] Not started |

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
| Push Notifications | Firebase Cloud Messaging (FCM) — Android + iOS via `firebase_messaging` Flutter package |
| Sharing | `share_plus` Flutter package |

---

## 📁 Final Project Structure (target)

```
wordchain/
├── CLAUDE.md
├── .env.example
├── backend/
│   ├── cmd/server/main.go
│   ├── internal/
│   │   ├── config/
│   │   ├── handler/
│   │   ├── service/
│   │   ├── repository/
│   │   ├── ws/
│   │   ├── engine/
│   │   │   └── data/
│   │   │       ├── enable.txt                  ← ENABLE wordlist
│   │   │       └── word_freq_ranks.txt         ← word frequency ranks (see Appendix)
│   │   ├── scheduler/                          ← background jobs (streak reminders, leaderboard reset, challenge expiry)
│   │   └── middleware/
│   ├── migrations/
│   ├── Dockerfile
│   └── docker-compose.yml
└── frontend/
    ├── pubspec.yaml
    ├── assets/
    │   └── words/enable.txt
    └── lib/
        ├── main.dart
        ├── core/
        │   ├── di/
        │   ├── network/
        │   ├── router/
        │   ├── services/
        │   │   ├── dictionary_service.dart
        │   │   ├── websocket_service.dart
        │   │   ├── monetization_service.dart
        │   │   ├── notification_service.dart   ← FCM token registration + foreground handling
        │   │   └── share_service.dart          ← Daily Challenge result card + native share
        │   └── theme/
        └── features/
            ├── auth/
            ├── home/
            ├── game/
            ├── lobby/
            ├── daily/
            ├── leaderboard/
            ├── friends/
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

| Variant | Opponent options | Turn timer | End condition |
|---|---|---|---|
| **Classic** | Solo, AI, 1v1 Multiplayer | 15s per turn | First invalid/timeout move loses; one continue per player allowed (see Continue Rules) |
| **Time Attack** | Solo, AI, 1v1 Multiplayer | 8s per turn | Total match time hits 90s; highest score wins |
| **Daily Challenge** | **Solo only** | 15s per turn | First mistake or after 20 words; score posted to daily leaderboard |

**Daily Challenge never appears in the multiplayer lobby.**

Defaults above are tunable in `internal/config/config.go` and via a `GameConfig` constant on the Flutter side. Do not hardcode magic numbers in handlers, blocs, or widgets.

### Multiplayer shared chain
In any multiplayer match (vs AI or 1v1), **both players contribute to a single shared word chain**:
- Players alternate turns. Player A plays a word, then Player B must continue from the last letter, then Player A, and so on.
- The full chain is visible to both players at all times.
- The first player to submit an invalid word, let the timer expire, or concede loses — unless they invoke a continue (Classic only, see below).
- In Time Attack, players alternate until the 90-second match timer expires; the player with the higher cumulative score wins.

### Continue Rules (Classic mode only — solo and multiplayer)
When a player's turn results in a loss event (invalid word or timeout):
1. The game pauses and a prompt appears for that player.
2. The player may **Watch a rewarded ad** (free continue) or **Spend 25 coins** (instant continue).
3. On continue: the chain resumes from the last valid word; it is that player's turn again.
4. Each player may use **at most one continue per match**.
5. In multiplayer, the opponent sees an "Opponent deciding…" overlay with a **15-second countdown**. If the countdown expires with no action, the loss stands and the opponent wins.
6. **Shield interaction**: Shield auto-activates *before* a loss event occurs; the continue prompt appears only if no Shield is held. They are independent systems.

### Word validation rules
Apply identically in Go (`engine.ValidateMove`) and Flutter (`DictionaryService.isValid`):

1. **Normalize**: trim whitespace, lowercase.
2. **Allowed characters**: `[a-z]` only. Reject digits, spaces, hyphens, apostrophes.
3. **Minimum length**: 3 letters. Reject with reason `too_short`.
4. **Starting letter**: must equal the last letter of the previous accepted word (case-insensitive after normalization). First word of the chain has no constraint.
5. **No repetition**: track `usedWords` per match; reject duplicates with reason `already_used`.
6. **Dictionary check**: must exist in the ENABLE wordlist. No proper nouns; ENABLE excludes them.

### Streak rules

A **match streak** is the count of consecutive successful word submissions by the same player within a single match. Resets to 0 on any rejection or timeout. The `streak_bonus` in the scoring formula uses the count *before* the current word (so the 4th consecutive correct word gets the bonus, not the 3rd).

A **daily streak** is the count of consecutive calendar days (UTC) on which the player completed at least one game of any mode. Tracked server-side in `player_stats`. See the Daily Streak section.

### Solo end conditions
Solo is single-player practice with no opponent. The match ends when **any** of:
- The player submits an invalid word
- The per-turn timer hits 0
- The player taps "End game"

Scores are saved to the backend for authenticated users. Guests see results in-session only but can transfer their score to a new account if they register immediately (see Guest Mode).

---

## 🗄️ Database Schema

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
    mode VARCHAR(20) NOT NULL,        -- classic, time_attack, daily
    status VARCHAR(20) NOT NULL,      -- pending, active, finished, abandoned
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
    continue_used BOOLEAN DEFAULT false,   -- tracks whether this player used their one continue
    joined_at TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (match_id, user_id)
);

CREATE TABLE player_stats (
    user_id UUID PRIMARY KEY REFERENCES users(id),
    total_matches INTEGER DEFAULT 0,
    wins INTEGER DEFAULT 0,
    longest_word TEXT,
    best_match_streak INTEGER DEFAULT 0,
    daily_streak INTEGER DEFAULT 0,
    longest_daily_streak INTEGER DEFAULT 0,
    last_played_date DATE,
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
    attempt_number INTEGER NOT NULL DEFAULT 1,  -- 1 = free attempt, 2 = paid retry
    score INTEGER NOT NULL,
    chain_length INTEGER NOT NULL,
    word_chain TEXT[] NOT NULL DEFAULT '{}',    -- ordered list of words played (used for share card)
    completed_at TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (user_id, challenge_date, attempt_number)
);

CREATE TABLE friendships (
    requester_id UUID REFERENCES users(id),
    addressee_id UUID REFERENCES users(id),
    status VARCHAR(20) NOT NULL DEFAULT 'pending',  -- pending, accepted, declined
    created_at TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (requester_id, addressee_id)
);

CREATE TABLE friend_challenges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    challenger_id UUID REFERENCES users(id),
    challenged_id UUID REFERENCES users(id),
    mode VARCHAR(20) NOT NULL,            -- classic, time_attack
    match_id UUID REFERENCES matches(id), -- null until accepted
    status VARCHAR(20) DEFAULT 'pending', -- pending, accepted, declined, expired
    created_at TIMESTAMPTZ DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL       -- challenger_created_at + 24h
);

CREATE TABLE device_tokens (
    user_id UUID REFERENCES users(id),
    token TEXT NOT NULL,
    platform VARCHAR(10) NOT NULL,  -- ios, android
    updated_at TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (user_id, token)
);

CREATE TABLE weekly_leaderboard_rewards (
    week_start DATE NOT NULL,
    user_id UUID REFERENCES users(id),
    rank INTEGER NOT NULL,
    coins_awarded INTEGER NOT NULL,
    awarded_at TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (week_start, user_id)
);
```

---

## 🌐 REST API Conventions

- Base path: `/api/v1/`
- Auth header: `Authorization: Bearer <jwt>`
- Content type: `application/json`
- Standard success: `{ "data": { ... } }`
- Standard error: `{ "error": { "code": "...", "message": "..." } }`
- Status codes: `400` validation, `401` missing/invalid JWT, `403` not allowed, `404` not found, `409` conflict, `429` rate limited, `500` server error
- All write endpoints rate-limited via Redis (60 req/min per user/IP)

### Endpoint list

**Auth**
- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `POST /api/v1/auth/refresh`

**Game**
- `POST /api/v1/game/solo` — start a solo game
- `GET  /api/v1/game/:id` — get match state
- `GET  /api/v1/profile/stats` — get current user's stats
- `POST /api/v1/powerup/use` — use a power-up (validates inventory, deducts, applies)

**Matchmaking**
- `POST   /api/v1/match/queue` — join matchmaking queue (body: `{mode, difficulty?}`)
- `DELETE /api/v1/match/queue` — cancel queuing

**Leaderboard**
- `GET /api/v1/leaderboard?type=global&limit=100`
- `GET /api/v1/leaderboard?type=friends&limit=100`

**Daily Challenge**
- `GET  /api/v1/daily` — get today's challenge state for current user (includes whether attempt/retry used)
- `POST /api/v1/daily/retry` — spend 25 coins to unlock a second attempt (returns 409 if retry already used)

**Friends**
- `POST   /api/v1/friends/request` — send a friend request by username
- `GET    /api/v1/friends` — list accepted friends
- `GET    /api/v1/friends/requests` — list pending incoming requests
- `POST   /api/v1/friends/respond` — accept or decline (body: `{requester_id, action: "accept"|"decline"}`)
- `DELETE /api/v1/friends/:friendId` — remove a friend

**Friend Challenges**
- `POST /api/v1/challenges` — create a challenge (body: `{challenged_id, mode}`)
- `POST /api/v1/challenges/:id/respond` — accept or decline
- `GET  /api/v1/challenges/pending` — list pending incoming challenges

**Push Notifications**
- `POST   /api/v1/notifications/token` — register FCM device token
- `DELETE /api/v1/notifications/token` — deregister on logout

---

## 🌐 WebSocket Event Protocol

```
Client → Server:
  { "type": "submit_word",  "word": "apple" }
  { "type": "use_powerup",  "powerup": "freeze" }
  { "type": "continue",     "method": "ad" | "coins" }   ← sent after loss_event; must arrive within 15s
  { "type": "ping" }

Server → Client:
  { "type": "game_start",           "state": { ... } }
  { "type": "word_accepted",        "word": "apple", "score": 85, "next_letter": "e", "player_id": "..." }
  { "type": "word_rejected",        "reason": "not_in_dictionary" | "wrong_letter" | "already_used" | "too_short", "player_id": "..." }
  { "type": "turn_change",          "player_id": "..." }
  { "type": "timer_update",         "remaining_ms": 7400 }
  { "type": "loss_event",           "player_id": "...", "reason": "invalid_word" | "timeout" }
  { "type": "continue_window",      "player_id": "...", "deadline_ms": 15000 }   ← sent to both players
  { "type": "continue_decision",    "player_id": "...", "decision": "continue" | "forfeit" }
  { "type": "powerup_used",         "powerup": "freeze", "by": "..." }
  { "type": "game_over",            "winner": "...", "scores": { ... } }
  { "type": "opponent_disconnected" }
  { "type": "pong" }
```

Client reconnect: exponential backoff (1s, 2s, 4s, capped at 8s) for up to 30 seconds. After 30s, treat as forfeit. Server holds the room open for the same 30s grace window.

---

## 💰 Scoring Formula

```
base_score   = word.length × 10
speed_bonus  = max(0, (time_limit - response_time_sec) × 2)
streak_bonus = streak >= 3 ? base_score × 0.5 : 0
rarity_bonus = freq_rank(word) > 10000 ? 20 : 0
turn_score   = base_score + speed_bonus + streak_bonus + rarity_bonus
```

- `time_limit` is the turn timer for the current match variant.
- `streak` is the count of consecutive successes by the player in this match *before* this word.
- `freq_rank` is looked up from `word_freq_ranks.txt` (see Appendix). Missing words are treated as rank ∞ (always rare).
- **Solo/AI note**: `rarity_bonus` is not applied in solo/AI mode — the Flutter scorer omits it because the frequency file is not bundled on the client. Solo scores are therefore calculated without rarity. Since solo scores are not added to the competitive leaderboard, this is acceptable.

---

## 🔐 Guest Mode & Auth Strategy

**Core principle: never block a player from playing before they're hooked.**

### What guests can do (no account required)
- Play Solo (vs self, infinite rounds) — fully offline, no server calls
- Play vs AI (Easy / Medium / Hard) — fully offline, no server calls
- Use 5 Hint power-ups per session (in-memory only, reset on app restart)
- See their current session score

### What requires registration
- Online multiplayer (1v1 real-time)
- Persistent stats, daily streak, and leaderboard participation
- Persistent coin balance and power-up inventory
- Daily Challenge (server-tracked to prevent replay)
- Friend system and friend challenges

### Guest power-up allowance
Guests receive **5 Hint uses per session** (tracked in `GameBloc` state, not persisted). All other power-ups (Freeze, Extra Time, Shield) require registration because they depend on persistent inventory or affect an opponent. When a guest uses their last Hint or taps a locked power-up, show a soft upsell: *"Register free to save your progress and unlock more power-ups."* Never hard-block or show a paywall.

### Guest-to-registered conversion
When a guest completes a solo game and registers immediately within the same session:
- `AuthCubit` checks whether `GameBloc` holds a completed game in state.
- If so, it calls `POST /api/v1/game/solo` after a successful register to save the score and chain to the new account.
- This transfer happens automatically — no user action required beyond registering.
- Guests who restart the app without registering lose their session data. The post-game upsell prompt should make this explicit: *"Register free to save this score and all future progress."*

### Auth flow
```
App launch
  ├── Stored JWT valid?  → /home (full features)
  ├── No token?          → /home (guest mode)
  └── Token expired?     → silent refresh → success: /home | fail: /home (guest)

Tap "Find Match", "Leaderboard", "Friends", or "Daily Challenge"
  └── Guest? → /login?return=<destination>
      After login → return to original destination
```

`AuthCubit` must expose an `isGuest` flag. Only the multiplayer queue and leaderboard write path force a login redirect — all other screens gate features behind the flag without redirecting.

---

## 💸 Monetization Model

**Hybrid freemium: ads + soft IAP. No hard paywalls. No pay-to-win.**

### Revenue streams

| # | Stream | Implementation |
|---|---|---|
| 1 | **Rewarded ads** | Watch ad → earn 20 coins, or use as a free continue. Highest player acceptance. |
| 2 | **Coin IAP bundles** | $0.99 / $2.99 / $9.99 packs. Coins buy power-ups, continues, and Daily Challenge retries. |
| 3 | **Remove Ads IAP** | One-time ~$2.99. Removes interstitial ads; rewarded ads remain (player-initiated). |
| 4 | **Premium subscription** | ~$3.99/month. No ads + 200 coins/week. |

### Coin economy

**Earn:**

| Event | Coins |
|---|---|
| Win a match (multiplayer or vs AI) | +30 |
| Daily login bonus | +10 |
| Watch rewarded ad | +20 |
| Match streak ≥ 5 in one game | +15 |
| Daily streak milestone: 3 consecutive days | +30 |
| Daily streak milestone: 7 consecutive days | +100 |
| Daily streak milestone: 30 consecutive days | +500 |
| Weekly leaderboard 1st place | +500 |
| Weekly leaderboard 2nd place | +300 |
| Weekly leaderboard 3rd place | +100 |

Milestones are repeatable — the next milestone after 30 days is 60, then 90, etc.

**Spend:**

| Item | Coins |
|---|---|
| Hint power-up (1 use) | 10 |
| Freeze power-up (1 use) | 20 |
| Extra Time power-up (1 use) | 15 |
| Continue after loss (Classic only) | 25 |
| Daily Challenge retry (1 per day) | 25 |

### What NOT to do
- No pay-to-win (power-up limits in multiplayer are enforced server-side, not bypassable by buying)
- No energy systems or artificial wait timers
- No interstitial ads during an active game — only on the game-over screen or when returning to home

---

## 🔋 Power-up Reference

| Power-up | Effect | Solo/AI limit | Multiplayer limit | Guest? |
|---|---|---|---|---|
| **Hint** | Suggests a valid word for the current required starting letter | Unlimited | 1 use per match | 5 per session (free, no coins) |
| **Freeze** | Pauses the opponent's turn timer for 5 additional seconds on their next turn | N/A (solo has no opponent) | 1 use per match | ❌ Registered only |
| **Extra Time** | Adds 8s to the current player's turn timer | Unlimited | 1 use per match | ❌ Registered only |
| **Shield** | Auto-activates to negate the next loss-causing event (invalid word or timeout). Fires before the continue prompt. Does not stack. | 1 per game | 1 per match | ❌ Registered only |

Both players' power-up inventories are visible to each other at the start of a multiplayer match (transparent gameplay). Multiplayer use limits are enforced server-side; client UI disables the button after use but the server rejects any second use attempt regardless.

---

## 🤖 AI Opponent

### Difficulty config

| Level | Response delay | Mistake rate | Min word length | Word selection strategy |
|---|---|---|---|---|
| Easy | 3s | 25% | 3 | Random valid word starting with the required letter |
| Medium | 1.5s | 10% | 4 | 30% chance to prefer a trap-ending word |
| Hard | 0.6s | 2% | 6 | 70% chance to prefer a trap-ending word; selects the longest valid trap word when available |

### Trap letter strategy
**Trap letters** are Q, X, Z, J, V — letters for which very few English words begin. By choosing a word ending in one of these letters, the AI maximises the difficulty of the human's next turn.

The trap preference is applied only when at least one valid trap-ending word exists for the current required starting letter. If none exists, the AI falls back to its standard random selection. The AI never intentionally makes a mistake when a trap word is available.

This strategy is implemented in `internal/service/ai.go` as a weighted random selection over candidate words, where trap-ending candidates receive a boosted weight at Medium and Hard difficulty.

---

## 📅 Daily Streak

A **daily streak** counts consecutive calendar days (UTC) on which the player completed at least one game of any mode.

### Rules
- Completing any game (solo, AI, multiplayer, or Daily Challenge) before midnight UTC counts for that day.
- Missing a day resets the streak to 0.
- Tracked in `player_stats.daily_streak` and `player_stats.last_played_date`.
- `longest_daily_streak` updates whenever `daily_streak` exceeds the previous record.
- `RecordGamePlayed(userID string, date time.Time)` is called at every game end (solo, multiplayer room close, and daily challenge completion). It updates the streak, awards milestone coins, and enqueues a push notification for milestone events.

### Milestone rewards (one-time per milestone level; repeatable on subsequent cycles)

| Milestone | Reward |
|---|---|
| 3 consecutive days | +30 coins |
| 7 consecutive days | +100 coins |
| 30 consecutive days | +500 coins |

After 30 days the cycle repeats: next milestones are 60, 90, etc.

### At-risk notification
If a player has an active streak ≥ 3 and has not played by 20:00 local time, the scheduler sends a push notification: *"Your [N]-day streak is at risk! Play one game before midnight to keep it alive."* See Push Notifications section for implementation.

---

## 👥 Social Features

### Friend system
- Any registered user can search for others by exact username.
- `POST /api/v1/friends/request` sends a request; the target receives a push notification.
- Requests are accepted or declined via `POST /api/v1/friends/respond`.
- Accepted friendships are bidirectional; a single row with `status = accepted` is sufficient (the service checks both `(requester_id, addressee_id)` and `(addressee_id, requester_id)` when determining friendship).
- The **Friends tab** on the Leaderboard screen shows only the current user's friends, ranked by their weekly score from the same Redis sorted set as the global leaderboard.

### Friend challenges
- From a friend's profile, tap **Challenge** and choose Classic or Time Attack.
- A `friend_challenges` record is created with `expires_at = NOW() + 24h`.
- The challenged player receives a push notification: *"[Username] challenged you to a [Mode] match!"*
- On acceptance: both players are placed into a private match room directly (bypasses the public matchmaking queue). The `match_id` is written to `friend_challenges`.
- On decline: the challenger is notified — *"[Username] declined your challenge."*
- On expiry (24h, no response): the challenger is notified — *"Your challenge to [Username] expired."* The scheduler runs `ExpireOldChallenges` every 5 minutes.

### Daily Challenge share card
After completing the Daily Challenge (win or lose, free attempt or paid retry), the player is shown a result card. Tapping **Share** opens the native share sheet via `share_plus`.

**Text format:**
```
WordChain Daily #[N]
Score: [score] | Chain: [chain_length] words
[word1] → [word2] → ... → [last_word]
Play at wordchain.app
```

- Day number `N` = days elapsed since `GAME_EPOCH_DATE` (see env vars appendix), 1-indexed.
- The word chain array is stored in `daily_challenge_attempts.word_chain`.
- `share_service.dart` exposes `shareDaily(DailyChallengeResult result)` which builds the text string and calls `Share.share()`.

---

## 🔔 Push Notifications

All notifications are sent via the FCM HTTP v1 API. Device tokens are registered at login (`POST /api/v1/notifications/token`) and deregistered at logout.

| Trigger | Audience | Message |
|---|---|---|
| Daily Challenge available (midnight UTC) | All registered users with a device token | "Today's Word Chain challenge is ready. Can you beat yesterday's score?" |
| Streak at risk (20:00 local, streak ≥ 3, not played today) | Affected users | "Your [N]-day streak is at risk! Play one game before midnight to keep it alive." |
| Streak milestone reached | Player | "🔥 [N]-day streak! You've earned [coins] coins." |
| Friend request received | Addressee | "[Username] wants to be your friend." |
| Friend challenge received | Challenged player | "[Username] challenged you to a [Mode] match!" |
| Friend challenge response | Challenger | "[Username] accepted/declined your challenge." / "Your challenge to [Username] expired." |
| Match found via matchmaking | Both players | "Opponent found! Your match is ready." |
| Weekly leaderboard reward | Top 3 players | "The weekly leaderboard has reset. You finished #[rank] and earned [coins] coins!" |

### Backend implementation
- `internal/service/notification.go` — `SendToUser(userID, title, body string)`: fetches FCM token from `device_tokens`, calls FCM v1 API.
- `internal/scheduler/scheduler.go` — goroutine with a 1-minute ticker running the following jobs:
  - **Midnight UTC**: send Daily Challenge push to all users with tokens.
  - **Every minute**: check for users whose `last_played_date < today` and `daily_streak >= 3` and whose local 20:00 has passed (use a UTC offset defaulted to 0 if no timezone stored).
  - **Every 5 minutes**: expire stale `friend_challenges`.
  - **Sunday 00:00 UTC**: run weekly leaderboard reset (see Leaderboard section).

### Flutter implementation
- `core/services/notification_service.dart`: requests FCM permission on first launch (after tutorial), registers the device token via the API, handles foreground messages as in-app banners, and exposes a stream of notification payloads for deep-link routing (tapping a Daily Challenge notification navigates to `/daily`; tapping a friend challenge notification navigates to `/friends`).

---

## 🎓 Tutorial (First-Time Player)

Triggered automatically on first app launch. Can be skipped at any time via a "Skip" button and replayed later from Profile → Help.

**Completion flag**: `tutorial_completed` (bool) stored in `shared_preferences`.

### Tutorial steps

| Step | Instruction shown | What the player does |
|---|---|---|
| 1 | "Type any word to start the chain!" | Types any valid word (≥ 3 letters) |
| 2 | "Now type a word starting with **[last letter]**!" | Types a valid continuation |
| 3 | "Great! Keep going — you can't reuse words." | Types one more valid word |
| 4 | "You're ready! Try Classic, Time Attack, or the Daily Challenge." | Taps "Start Playing" |

- The tutorial runs against a sandboxed in-memory game state. No score or match record is created.
- Invalid words during the tutorial show a gentle inline prompt ("That one doesn't work — try another word starting with [letter]!") instead of triggering a game-over.
- After the tutorial, if the player is still a guest, show the soft upsell: *"Register free to save your progress and unlock power-ups."* (non-blocking — tap to dismiss).

---

## 🏆 Leaderboard & Weekly Reset

### Leaderboard sources
- Redis Sorted Set `leaderboard:global:weekly` stores cumulative score per user.
- Score is added at the end of **multiplayer and Daily Challenge games only**. Solo scores are excluded from the competitive leaderboard.
- `GET /api/v1/leaderboard?type=global` returns top 100 with rank, username, score.
- `GET /api/v1/leaderboard?type=friends` fetches the current user's friend IDs, retrieves their scores from the same sorted set via `ZSCORE`, and returns a ranked friend-only list.

### Weekly reset (Sunday 00:00 UTC — run by scheduler)
1. Query top 3 from `leaderboard:global:weekly`.
2. Insert rows into `weekly_leaderboard_rewards` (idempotent — skip if `week_start` already exists).
3. Award coins: 1st → 500, 2nd → 300, 3rd → 100 (`UPDATE users SET coins = coins + X`).
4. Send push notification to each rewarded user.
5. Delete the Redis key to start the new week's leaderboard at zero.

---

## 🧪 Testing Strategy

Tests are written **inside the phase that introduces the code**, not as a separate phase.

### Backend (Go)
- **Unit tests** for every file in `internal/engine/`, `internal/service/`, `internal/scheduler/`.
- **Repository tests** use a real Postgres test container (`testcontainers-go`); no mocked DB.
- **Handler tests** use `httptest` against the Gin router with a stubbed service layer.
- **WebSocket tests** spin up `httptest.Server` and connect a real client.
- Target ≥ 70% coverage on `engine/` and `service/`.

### Frontend (Flutter)
- **Widget tests** for each screen's primary states (loading, success, error, empty).
- **Bloc/Cubit tests** using `bloc_test` for every state transition.
- **Golden tests** for `WordChainList` and `TimerBar`.
- Mock `DictionaryService`, `WebSocketService`, and `NotificationService` in widget tests. Do not load the real wordlist.

### Integration (Phase 16)
Full end-to-end smoke flows:
- Guest → tutorial → solo → game over → watch ad continue → game ends → score shown
- Guest → completes solo → registers → score transferred to new account
- Registered → Daily Challenge → completes → share card generated → retry costs 25 coins
- Registered → matchmaking queue → 1v1 match → shared chain play → continue prompt → game over → leaderboard updated
- Registered → sends friend request → friend accepts → friend challenge → private match
- Weekly scheduler job runs → top 3 rewarded → leaderboard resets

---

## 🗺️ Implementation Phases

> At the start of each session: *"Read CLAUDE.md and implement Phase N."*
> Mark the phase `[x]` in both the status table and the per-phase status line when complete.

---

### Phase 1 — Foundation & Database
**Status: [ ] Not started**

**Scope:**
- Create monorepo folder structure (`backend/`, `frontend/`)
- Write full architecture diagram (`backend/ARCHITECTURE.md`)
- Initialize Go module (`go.mod`) with all dependencies
- `internal/config/config.go` — load from env vars (see Appendix)
- `migrations/001_init.up.sql` + `001_init.down.sql` — full schema from the Database Schema section above (all tables including `friendships`, `friend_challenges`, `device_tokens`, `weekly_leaderboard_rewards`)
- `docker-compose.yml` — services: app, postgres, redis
- Backend `Dockerfile`
- `cmd/server/main.go` — wire config, DB, Redis, Gin router, `GET /health`
- `.env.example`

**Done when:** `docker-compose up` starts all three services. Server responds to `GET /health` with 200 OK.

---

### Phase 2 — Backend: Dictionary & Game Engine
**Status: [ ] Not started**

**Note:** The Go dictionary is used **only for multiplayer validation**. Solo and AI games validate entirely on the Flutter client via `DictionaryService`.

**Scope:**
- `internal/engine/dictionary.go` — embed ENABLE wordlist (`data/enable.txt`), load into `map[string]struct{}` at startup, expose `IsValid(word string) bool`
- `internal/engine/frequency.go` — embed `data/word_freq_ranks.txt`, load into `map[string]int` at startup, expose `Rank(word string) int` (returns `math.MaxInt` if missing)
- `internal/engine/validator.go` — `ValidateMove(prevWord, newWord string, usedWords map[string]bool) error` — covers all six Word Validation Rules; returns typed sentinel errors
- `internal/engine/scorer.go` — `CalculateScore(word string, responseTimeSec float64, streak int, timeLimitSec float64) int` using the formula above (includes rarity_bonus via `frequency.Rank`)
- Unit tests for all four engine files

**Done when:** All engine unit tests pass. Dictionary loads. Validator correctly rejects bad moves with typed errors.

---

### Phase 3 — Backend: Auth
**Status: [ ] Not started**

**Scope:**
- `internal/repository/user.go` — `CreateUser`, `GetUserByEmail`, `GetUserByID`
- `internal/service/auth.go` — `Register`, `Login`, `RefreshToken` (bcrypt, JWT generation)
- `internal/handler/auth.go` — `POST /api/v1/auth/register`, `POST /api/v1/auth/login`, `POST /api/v1/auth/refresh`
- `internal/middleware/auth.go` — JWT validation middleware for protected routes
- Password policy: min 8 chars, ≥1 letter and ≥1 digit. Username: 3–32 chars, `[a-zA-Z0-9_]`.

**Done when:** Register and login return valid JWTs. Protected route returns 401 without token. Invalid passwords rejected with 400.

---

### Phase 4 — Backend: Game REST API & Match Repository
**Status: [ ] Not started**

**Scope:**
- `internal/repository/match.go` — `CreateMatch`, `GetMatch`, `UpdateMatchStatus`, `SaveGameState`, `GetMatchPlayers`, `SetContinueUsed`
- `internal/repository/stats.go` — `UpsertStats`, `GetStats`
- `internal/service/game.go` — `CreateSoloGame`, `GetGameState`, `EndGame`, `UpdateStats`
- REST endpoints: `POST /api/v1/game/solo`, `GET /api/v1/game/:id`, `GET /api/v1/profile/stats`
- `internal/handler/powerup.go` — `POST /api/v1/powerup/use` (validates inventory, deducts, applies; rejects second use in multiplayer via `match_players.continue_used` or per-powerup-type tracking)

**Done when:** Solo game create/retrieve/end and power-up use work via REST.

---

### Phase 5 — Backend: WebSocket & Multiplayer
**Status: [ ] Not started**

**Scope:**
- `internal/ws/client.go` — read/write pumps, ping/pong
- `internal/ws/room.go` — **shared chain room**: alternating turns on a single chain, `loss_event` dispatch, continue handling (15s window per event, one continue per player tracked via `match_players.continue_used`), Shield interaction, reconnection (30s grace)
- `internal/ws/hub.go` — manages all rooms, routes messages, cleans up finished rooms
- `internal/handler/ws.go` — `GET /api/v1/ws/game/:roomID` — upgrades connection, registers client with hub
- Integrate engine validator and scorer into room turn logic
- Handle client events: `submit_word`, `use_powerup`, `continue`
- Emit server events: `word_accepted`, `word_rejected`, `loss_event`, `continue_window`, `continue_decision`, `game_over`
- Multiplayer power-up enforcement: reject `use_powerup` if the player has already used that power-up type in this match

**Done when:** Two clients share a single chain, alternate correctly, loss events trigger the continue window, one continue per player enforced, game_over fires.

---

### Phase 6 — Backend: Matchmaking & AI Opponent
**Status: [ ] Not started**

**Scope:**
- `internal/service/matchmaking.go` — Redis List queue per mode (`queue:classic`, `queue:time_attack`); background goroutine polls every 500ms; pairs two players → creates room → notifies via WS; falls back to AI opponent after 30s wait
- `POST /api/v1/match/queue`, `DELETE /api/v1/match/queue`
- `internal/service/ai.go` — AI difficulty struct:
  ```
  Easy:   3s delay, 25% mistake rate, min length 3, random word selection
  Medium: 1.5s delay, 10% mistake rate, min length 4, 30% trap-letter preference
  Hard:   0.6s delay, 2% mistake rate, min length 6, 70% trap-letter preference + longest valid trap word preferred
  ```
  Trap letters: Q, X, Z, J, V. AI selects a trap-ending word only when at least one exists for the required starting letter; otherwise falls back to weighted random from all valid candidates.

**Done when:** Matchmaking pairs two real clients. AI plays at all three difficulty levels with correct trap letter behaviour.

---

### Phase 7 — Backend: Leaderboard & Streak
**Status: [ ] Not started**

**Scope:**
- `internal/service/leaderboard.go` — Redis Sorted Set `leaderboard:global:weekly`: `AddScore`, `GetTopN(n int)`, `GetPlayerRank(userID string)`
- `AddScore` is called at the end of **multiplayer and Daily Challenge games only** (not solo)
- `GET /api/v1/leaderboard?type=global&limit=100`
- `GET /api/v1/leaderboard?type=friends&limit=100` — fetches friend IDs, retrieves scores via `ZSCORE`, returns sorted list
- `internal/service/streak.go` — `RecordGamePlayed(userID string, date time.Time)`: updates `daily_streak`, `last_played_date`, `longest_daily_streak`; awards milestone coins; calls `notification.SendToUser` for milestone events
- Call `RecordGamePlayed` at every game end (solo end, multiplayer room close, daily challenge completion)
- `internal/scheduler/scheduler.go` — goroutine with 1-minute ticker, initial jobs:
  - Weekly reset: Sunday 00:00 UTC — query top 3, insert `weekly_leaderboard_rewards`, award coins, send push notifications, delete Redis key
  - Streak at-risk check: every minute, fire notifications where applicable

**Done when:** Leaderboard returns correct ranked list. Weekly reset awards coins and sends notifications. Streak increments and milestone coins are awarded.

---

### Phase 8 — Backend: Friends & Challenges
**Status: [ ] Not started**

**Scope:**
- `internal/repository/friendship.go` — `SendRequest`, `RespondToRequest`, `ListFriends`, `ListPendingRequests`, `RemoveFriend`
- `internal/repository/challenge.go` — `CreateChallenge`, `RespondToChallenge`, `GetPendingChallenges`, `ExpireOldChallenges`
- `internal/service/friends.go` — business logic: no duplicate requests, no self-requests, validates friendship before challenge creation
- `internal/service/challenge.go` — `CreateChallenge` (creates a private match room on accept, writes `match_id`), `RespondToChallenge` (accept → triggers matchmaking directly into private room; decline → notify challenger), sends push notifications on all state changes
- Handlers for all Friends and Friend Challenge endpoints
- Add scheduler job: run `ExpireOldChallenges` every 5 minutes; notify challenger on expiry

**Done when:** Full friend request and friend challenge flows work end-to-end. Expired challenges are cleaned up automatically.

---

### Phase 9 — Backend: Push Notifications
**Status: [ ] Not started**

**Scope:**
- `internal/service/notification.go` — `SendToUser(userID, title, body string)`: looks up FCM token from `device_tokens`, calls FCM HTTP v1 API (`https://fcm.googleapis.com/v1/projects/{FCM_PROJECT_ID}/messages:send`) using `FCM_SERVICE_ACCOUNT_JSON` for auth
- `POST /api/v1/notifications/token`, `DELETE /api/v1/notifications/token`
- Wire `SendToUser` into all existing trigger points that were previously stubs: friend request, challenge received/responded, match found, streak milestone, weekly leaderboard reward
- Add scheduler jobs:
  - **Midnight UTC daily**: query all users with device tokens, send Daily Challenge reminder
  - **Every minute**: query `player_stats` for users with `daily_streak >= 3`, `last_played_date < today`, and estimated local time ≥ 20:00 — send streak-at-risk notification (deduplicate using a Redis key `notif:streak_risk:{userID}:{date}` with TTL 24h)

**Done when:** All notification triggers fire in integration tests. Token registration and deregistration work. Duplicate at-risk notifications are prevented.

---

### Phase 10 — Flutter: Core Setup
**Status: [ ] Not started**

**Scope:**
- Initialize Flutter project in `frontend/`
- `pubspec.yaml` dependencies: `flutter_bloc`, `go_router`, `dio`, `get_it`, `equatable`, `web_socket_channel`, `shared_preferences`, `logger`, `firebase_messaging`, `share_plus`
- `core/di/injection.dart` — register all services and repositories
- `core/network/dio_client.dart` — single `Dio` instance, base URL from config, auth interceptor (attaches JWT, handles 401 → refresh)
- `core/network/api_endpoints.dart` — all endpoint constants
- `core/router/app_router.dart` — routes: `/login`, `/register`, `/home`, `/game/:id`, `/lobby`, `/daily`, `/leaderboard`, `/friends`, `/profile`
- `core/services/websocket_service.dart` — connect, disconnect, send, stream of typed incoming events
- `core/services/dictionary_service.dart` — load ENABLE into `HashSet<String>` before `runApp()`, expose `isValid(String word) bool` and `suggestWords(String startLetter) List<String>`
- `core/services/notification_service.dart` — request FCM permission after tutorial, register token via API, handle foreground messages as in-app banners, expose notification payload stream for deep-link routing
- `core/services/share_service.dart` — `shareDaily(DailyChallengeResult result)` using `share_plus`
- `core/theme/app_theme.dart` — light/dark theme
- Bundle `assets/words/enable.txt` in `pubspec.yaml`

**Done when:** App builds, all routes navigate to placeholder screens, DI resolves, `isValid("apple")` returns true, FCM token registers successfully.

---

### Phase 11 — Flutter: Auth Feature
**Status: [ ] Not started**

**Scope:**
- `features/auth/data/auth_repository.dart` — `register`, `login`, `refreshToken`; persist JWT in `shared_preferences`
- `features/auth/cubit/auth_cubit.dart` — states: `AuthInitial`, `AuthLoading`, `AuthGuest`, `AuthAuthenticated`, `AuthError`; expose `isGuest` flag
- `features/auth/view/login_screen.dart` — email + password, login button, register link, "Continue as Guest" button
- `features/auth/view/register_screen.dart` — username + email + password, register button, "Continue as Guest" link
- App startup logic: valid JWT → `AuthAuthenticated` → `/home`; no token / refresh failed → `AuthGuest` → `/home`
- On register success: check `GameBloc` state; if a completed solo game exists, call `POST /api/v1/game/solo` to transfer score before navigating home

**Done when:** Guest reaches home and plays solo without login. Token survives restart. Guest score transfers on registration.

---

### Phase 12 — Flutter: Game Feature (Solo + Tutorial)
**Status: [ ] Not started**

**Scope:**
- `features/game/data/game_repository.dart` — `startSoloGame`, `getGame`, `usePowerup`
- `features/game/bloc/game_bloc.dart` — states: `GameInitial`, `GameLoading`, `GameActive`, `GameOver`, `GameError`; events: `GameStarted`, `WordSubmitted`, `PowerupUsed`, `TimerTicked`, `GameEnded`, `ContinueRequested`, `ContinueResolved`
- `features/game/view/game_screen.dart` — word chain display, required starting letter, score, timer bar, power-up buttons, game-over overlay with continue prompt
- `features/game/view/widgets/word_input.dart` — text field + submit; validates via `DictionaryService` locally; disabled during opponent's turn
- `features/game/view/widgets/word_chain_list.dart` — scrollable list of played words
- `features/game/view/widgets/timer_bar.dart` — animated countdown bar
- `features/game/view/widgets/continue_prompt.dart` — shown on `GameOver` in Classic mode; "Watch Ad" and "Spend 25 Coins" buttons; 15-second countdown; one use per session tracked in `GameBloc` state
- Tutorial flow at `features/game/view/tutorial_screen.dart`:
  - 4 guided steps (see Tutorial section)
  - Sandboxed in-memory state, no record created
  - Shown on first launch via `shared_preferences: tutorial_completed`
  - Skippable and replayable from Profile → Help
- Guest Hint: 5 free per session, soft upsell prompt on last use

**Done when:** Solo game fully playable by a guest. Tutorial completes all four steps. Continue works once per Classic session. All end conditions trigger `GameOver`.

---

### Phase 13 — Flutter: Lobby & Multiplayer
**Status: [ ] Not started**

**Scope:**
- `features/lobby/data/lobby_repository.dart` — `joinQueue`, `cancelQueue`
- `features/lobby/cubit/lobby_cubit.dart` — states: `LobbyIdle`, `LobbySearching`, `LobbyMatchFound`, `LobbyError`
- `features/lobby/view/lobby_screen.dart` — mode selector (**Classic** and **Time Attack only** — Daily Challenge does not appear here), difficulty selector for AI, Find Match button, searching animation, cancel button
- On `LobbyMatchFound`, navigate to `/game/:id`
- Multiplayer additions to `game_screen.dart`:
  - Shared chain display: words labeled by player
  - Turn indicator (whose turn it is)
  - Both players' power-up inventories displayed
  - Opponent continue-window overlay: "Opponent deciding… [15s countdown]" when a `continue_window` event is received
- Wire `GameBloc` to `WebSocketService` for multiplayer; handle `loss_event`, `continue_window`, `continue_decision`, `game_over`
- `features/home/view/home_screen.dart` — buttons for Solo / vs AI, Find Match, Daily Challenge, Leaderboard, Friends, Profile; show daily streak count if user is authenticated

**Done when:** Player queues, is matched, plays a shared-chain multiplayer game, continue window works for both players, game_over navigates correctly.

---

### Phase 14 — Flutter: Leaderboard, Friends & Profile
**Status: [ ] Not started**

**Scope:**
- `features/leaderboard/cubit/leaderboard_cubit.dart` — fetch global top 100 and friends top 100; current user rank in each
- `features/leaderboard/view/leaderboard_screen.dart` — tab bar: Global | Friends; ranked list; highlight current user's row; show weekly reward note for top 3
- `features/friends/data/friends_repository.dart` — all Friend and Friend Challenge API calls
- `features/friends/cubit/friends_cubit.dart`
- `features/friends/view/friends_screen.dart` — friend list, pending requests banner, username search, per-friend profile with Challenge button
- `features/friends/view/friend_challenge_sheet.dart` — mode selector (Classic / Time Attack), send challenge button
- `features/profile/cubit/profile_cubit.dart` — fetch stats + coin balance + power-up inventory
- `features/profile/view/profile_screen.dart` — total matches, wins, best match streak, daily streak, longest daily streak, longest word played, coin balance, power-up inventory, Help button (replays tutorial)
- Handle notification deep links: friend request notification → `/friends`; friend challenge notification → `/friends`

**Done when:** All screens show real data. Friend request and challenge flows complete end-to-end.

---

### Phase 15 — Flutter: Daily Challenge & Sharing
**Status: [ ] Not started**

**Scope:**
- `features/daily/data/daily_repository.dart` — `getDailyChallenge`, `submitAttempt`, `retryChallenge`
- `features/daily/cubit/daily_cubit.dart` — states: `DailyInitial`, `DailyLoading`, `DailyAvailable`, `DailyAttempted`, `DailyRetryAvailable`, `DailyError`
- `features/daily/view/daily_screen.dart`:
  - If not attempted: shows today's challenge details and Play button
  - If attempted: shows score, chain length, word chain, Share button, and (if eligible) a Retry button showing the 25-coin cost
  - If retry attempted: shows retry score alongside original score, Share button only
- After game completion: navigate to daily result screen, trigger share card display
- `share_service.dart` generates the text card and calls `Share.share()`
- Handle notification deep link: daily push notification → `/daily`
- Wire daily streak display on Home screen and Profile (fetched as part of `player_stats`)

**Done when:** Daily Challenge plays end-to-end. Share card generates correctly. Retry deducts 25 coins. Streak increments after any game completion. Deep link from push notification navigates to `/daily`.

---

### Phase 16 — Monetization Hooks & Final Wiring
**Status: [ ] Not started**

**Scope:**
- `core/services/monetization_service.dart` — abstract class + mock implementation:
  - `showRewardedAd() → Future<bool>` — returns true if full ad watched
  - `showInterstitialAd()` — between sessions only, never mid-game
  - `getProducts() → Future<List<Product>>`
  - `purchase(productId) → Future<PurchaseResult>`
  - `spendCoins(int amount) → bool`
  - `awardCoins(int amount)`
- Register `MockMonetizationService` in `get_it`; swap for AdMob + RevenueCat in production
- Game-over screen: "Watch Ad to Continue" + "Spend 25 Coins" buttons; interstitial ad when returning to home (not when continuing)
- Profile screen: coin balance display, "Buy Coins" button (mock prices: $0.99 / $2.99 / $9.99), "Remove Ads" one-time purchase, "Premium — $3.99/mo" subscription with feature list
- Backend `internal/service/monetization.go` — `AwardCoins`, `SpendCoins`, `ValidateReceipt` (stub)
- Run full integration test suite (see Testing Strategy — Integration)

**Done when:** All screens connected, no placeholder crashes, every earn/spend coin path updates balances correctly, full guest and registered game loops run end-to-end.

---

## 🔁 Session Workflow

1. Point Claude Code at this file: *"Read CLAUDE.md"*
2. State the phase: *"Implement Phase N — [title]"*
3. Mark both the per-phase status line and the Phase Status table `[x] Complete` when done
4. Commit the code before starting the next phase

---

## ⚠️ Important Notes for Claude Code

- **Never implement outside the current phase's scope.** Flag missing items from prior phases without silently fixing them.
- **Always check previous phases' output** before writing code that depends on it (e.g., verify actual repository method signatures before calling them in a service).
- **Keep CLAUDE.md status table and per-phase status lines in sync.**
- **Dictionary is dual:** `enable.txt` lives in both `backend/internal/engine/data/` and `frontend/assets/words/`. Keep them byte-identical.
- **`word_freq_ranks.txt` is backend only.** Rarity scoring is server-side; `rarity_bonus` is omitted from the Flutter scorer. Solo scores are not posted to the competitive leaderboard, so this asymmetry is acceptable.
- **Never require login to start a solo or vs-AI game.** Guest mode is first-class. Any screen that forces login before solo play is a bug.
- **Daily Challenge never appears in the multiplayer lobby.** It is solo-only.
- **Power-up limits in multiplayer are enforced server-side.** Client UI disables buttons after use, but the server must reject any second use attempt regardless.
- **Do not hardcode game tuning values** (timers, scores, AI difficulty, trap letter weights). Read from `config.go` on the Go side and a `GameConfig` constant on the Flutter side.
- Local dev ports: backend 8080, Postgres 5432, Redis 6379.

---

## 📎 Appendix: Environment Variables

| Variable | Required | Example | Notes |
|---|---|---|---|
| `PORT` | yes | `8080` | HTTP port |
| `DATABASE_URL` | yes | `postgres://user:pass@localhost:5432/wordchain?sslmode=disable` | |
| `REDIS_URL` | yes | `redis://localhost:6379/0` | |
| `JWT_SECRET` | yes | (random 32+ bytes) | HS256 signing secret |
| `JWT_ACCESS_TTL` | no | `15m` | Default 15 minutes |
| `JWT_REFRESH_TTL` | no | `720h` | Default 30 days |
| `LOG_LEVEL` | no | `info` | debug / info / warn / error |
| `ENV` | no | `dev` | dev / prod — controls log format |
| `CORS_ORIGINS` | no | `http://localhost:*` | Comma-separated allowed origins |
| `FCM_PROJECT_ID` | yes | `wordchain-prod` | Firebase project ID for FCM v1 API |
| `FCM_SERVICE_ACCOUNT_JSON` | yes | (path or inline JSON) | Service account credentials for FCM auth |
| `GAME_EPOCH_DATE` | no | `2025-01-01` | Day #1 for Daily Challenge numbering (YYYY-MM-DD) |

---

## 📎 Appendix: Dictionary & Word Frequency List

### ENABLE wordlist
- ~172,820 words, public domain, one lowercase word per line, ASCII only, no proper nouns, no contractions.
- Stored at `backend/internal/engine/data/enable.txt` and `frontend/assets/words/enable.txt` (byte-identical).
- Loaded into `map[string]struct{}` (Go) and `HashSet<String>` (Flutter) at startup.
- Memory footprint: ~1.7 MB plain text; ~6–8 MB in-memory set.

### Word frequency list (`word_freq_ranks.txt`)
- **Format**: tab-separated `word\trank`, one entry per line, lowercase, sorted by rank ascending.
- **Source**: derive from a freely licensed word frequency corpus (e.g., Wikipedia word count data, CC BY-SA). Restrict to words that also appear in the ENABLE wordlist to keep the file small.
- **Usage**: words with rank > 10,000 are considered rare and earn the `rarity_bonus`. Words absent from the file receive rank `math.MaxInt` (always rare).
- **Storage**: backend only, at `backend/internal/engine/data/word_freq_ranks.txt`. Loaded into `map[string]int` at server startup alongside the dictionary.
- **Note**: verify the license of the chosen corpus before shipping. Wikipedia-derived counts are CC BY-SA and acceptable for a commercial product provided attribution is given in the app's credits.