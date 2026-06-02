# CLAUDE.md — WordChain Project

Read this file and **PLAN.md** at the start of every session.
**Never skip a phase. Never implement ahead of the current phase.**

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

Keep this table in sync with the per-phase status lines in PLAN.md.

| # | Phase | Status |
|---|---|---|
| 1 | Flutter: Core Setup | [x] Complete |
| 2 | Flutter: Game Feature (Solo + Tutorial) | [x] Complete |
| 3 | Flutter: Auth Feature | [x] Complete |
| 4 | Foundation & Database | [x] Complete |
| 5 | Backend: Dictionary & Game Engine | [x] Complete |
| 6 | Backend: Auth | [x] Complete |
| 7 | Backend: Game REST API & Match Repository | [x] Complete |
| 8 | Backend: WebSocket & Multiplayer | [x] Complete |
| 9 | Backend: Matchmaking & AI Opponent | [x] Complete |
| 10 | Backend: Leaderboard & Streak | [x] Complete |
| 11 | Backend: Friends & Challenges | [x] Complete |
| 12 | Backend: Push Notifications | [x] Complete |
| 13 | Flutter: Lobby & Multiplayer | [x] Complete |
| 14 | Flutter: Leaderboard, Friends & Profile | [x] Complete |
| 15 | Flutter: Daily Challenge & Sharing | [x] Complete |
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
| Local DB (Flutter) | Drift 2 — type-safe SQLite ORM; tables: `local_matches`, `local_used_words`, `local_player_stats`, `local_powerup_cache` |

---

## 📁 Final Project Structure (target)

```
wordchain/
├── CLAUDE.md
├── PLAN.md
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
│   │   ├── scheduler/                          ← background jobs
│   │   └── middleware/
│   ├── migrations/
│   ├── Dockerfile
│   └── docker-compose.yml
└── client/
    ├── pubspec.yaml
    ├── assets/
    │   └── words/enable.txt
    └── lib/
        ├── main.dart
        ├── core/
        │   ├── di/
        │   ├── network/
        │   ├── router/
        │   ├── database/
        │   │   ├── app_database.dart
        │   │   └── daos/
        │   │       ├── match_dao.dart
        │   │       ├── used_word_dao.dart
        │   │       ├── stats_dao.dart
        │   │       └── powerup_cache_dao.dart
        │   ├── services/
        │   │   ├── dictionary_service.dart
        │   │   ├── sync_service.dart
        │   │   ├── websocket_service.dart
        │   │   ├── monetization_service.dart
        │   │   ├── notification_service.dart
        │   │   └── share_service.dart
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

## 🎨 UI Design Reference

All Flutter screens must be implemented pixel-close to the designs in `figma/`. Each PLAN.md Flutter phase lists the specific reference image(s) for that phase. Do not invent layouts — if a screen is covered by a design file, follow it. If a detail is ambiguous, match the overall visual style and spacing of the nearest reference image.

---

## 📐 Coding Rules (apply in every session)

- Backend: strictly 3 layers — `handler → service → repository`. No domain layer.
- Flutter: feature-based folders only. No forced layered architecture per feature.
- Each feature only has what it needs: `cubit/` or `bloc/`, `data/`, `view/`.
- Use `get_it` for all DI. Never use `Provider` or `InheritedWidget` for DI.
- Use `go_router` for all navigation. Never call `Navigator.push` directly.
- Use a single `dio` instance registered in `get_it`, with an auth interceptor.
- WebSocket logic lives in `core/services/websocket_service.dart` only.
- Dictionary validation is **hybrid**: Flutter `DictionaryService` (HashSet) for solo/AI — instant, offline, no server call. Go `map[string]struct{}` for multiplayer — server is the authority.
- Solo and vs-AI games run **entirely on-device**. The server is not involved in word validation for those modes.
- Add comments only where logic is non-obvious.

### Local database (Drift)
- The local Drift DB is the **single source of truth for all solo and AI game state**. Never rely on in-memory-only state for data that must survive an app restart or backgrounding.
- `LocalUsedWords` is the authoritative duplicate-check source during a game. On each `WordSubmitted` event, `GameBloc` calls `UsedWordDao.isWordUsed(matchId, word)` before the dictionary check — never use only an in-memory `Set<String>` for this.
- When a match ends, the full word chain is serialised into `local_matches.word_chain` (JSON) and all `local_used_words` rows for that match are deleted inside a single Drift transaction.
- `LocalPlayerStats` is updated synchronously at game-end inside the same Drift transaction. `SyncService.sync()` propagates it to the backend asynchronously afterwards — never block the UI on the sync call.
- `LocalPowerupCache` reflects the last-known server inventory for authenticated users. Writes always go to the server first; update the local cache only on a successful API response.
- For guests, `LocalPowerupCache` is not used. The 5 free Hint uses per session are tracked in `GameBloc` state only (intentional reset per session).
- `SyncService.sync()` is idempotent and safe to call on every app resume. Trigger it on: app foreground (authenticated), successful registration, successful login, and connectivity-restored events.
- Never write a Drift migration that drops or truncates `local_matches` or `local_player_stats` without first flushing all rows where `synced = false`.

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
| **Classic** | Solo, AI, 1v1 Multiplayer | 15s per turn | First invalid/timeout move loses; one continue per player allowed |
| **Time Attack** | Solo, AI, 1v1 Multiplayer | 8s per turn | Total match time hits 90s; highest score wins |
| **Daily Challenge** | **Solo only** | 15s per turn | First mistake or after 20 words; score posted to daily leaderboard |

**Daily Challenge never appears in the multiplayer lobby.**

Defaults above are tunable in `internal/config/config.go` and via a `GameConfig` constant on the Flutter side. Do not hardcode magic numbers in handlers, blocs, or widgets.

### Multiplayer shared chain
In any multiplayer match (vs AI or 1v1), **both players contribute to a single shared word chain**:
- Players alternate turns on the same chain.
- The first player to submit an invalid word, let the timer expire, or concede loses — unless they invoke a continue (Classic only).
- In Time Attack, players alternate until the 90-second match timer expires; highest cumulative score wins.

### Continue Rules (Classic mode only — solo and multiplayer)
1. On a loss event: player may **Watch a rewarded ad** (free) or **Spend 25 coins** (instant).
2. On continue: chain resumes from the last valid word; it is that player's turn again.
3. Each player may use **at most one continue per match**.
4. In multiplayer, the opponent sees "Opponent deciding…" with a **15-second countdown**. If it expires, the loss stands.
5. **Shield interaction**: Shield auto-activates *before* a loss event; the continue prompt appears only if no Shield is held.

### Word validation rules
Apply identically in Go (`engine.ValidateMove`) and Flutter (`DictionaryService.isValid`):

1. **Normalize**: trim whitespace, lowercase.
2. **Allowed characters**: `[a-z]` only. Reject digits, spaces, hyphens, apostrophes.
3. **Minimum length**: 3 letters. Reject with reason `too_short`.
4. **Starting letter**: must equal the last letter of the previous accepted word. First word has no constraint.
5. **No repetition**: reject duplicates with reason `already_used`.
6. **Dictionary check**: must exist in the ENABLE wordlist.

### Streak rules
- **Match streak**: consecutive successful word submissions by the same player in one match. Resets on rejection/timeout. `streak_bonus` uses the count *before* the current word.
- **Daily streak**: consecutive calendar days (UTC) with at least one completed game. Tracked server-side in `player_stats`.

### Solo end conditions
Match ends when the player submits an invalid word, the timer hits 0, or they tap "End game".

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
    continue_used BOOLEAN DEFAULT false,
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
    attempt_number INTEGER NOT NULL DEFAULT 1,  -- 1 = free, 2 = paid retry
    score INTEGER NOT NULL,
    chain_length INTEGER NOT NULL,
    word_chain TEXT[] NOT NULL DEFAULT '{}',
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
    mode VARCHAR(20) NOT NULL,
    match_id UUID REFERENCES matches(id),
    status VARCHAR(20) DEFAULT 'pending',  -- pending, accepted, declined, expired
    created_at TIMESTAMPTZ DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL        -- created_at + 24h
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

## 📱 Local Database Schema (Flutter / Drift)

All tables live in a single Drift database (`AppDatabase`) at `core/database/app_database.dart`. Schema version starts at `1`; increment and add a `MigrationStrategy` step on every change. Run `dart run build_runner build` after schema edits.

```dart
class LocalMatches extends Table {
  IntColumn     get id           => integer().autoIncrement()();
  TextColumn    get remoteId     => text().nullable()();         // null until synced
  TextColumn    get mode         => text()();                    // classic | time_attack
  TextColumn    get opponentType => text()();                    // solo | ai_easy | ai_medium | ai_hard
  TextColumn    get status       => text()();                    // active | finished | abandoned
  IntColumn     get score        => integer().withDefault(const Constant(0))();
  IntColumn     get chainLength  => integer().withDefault(const Constant(0))();
  TextColumn    get wordChain    => text().withDefault(const Constant('[]'))(); // JSON List<String>
  BoolColumn    get synced       => boolean().withDefault(const Constant(false))();
  DateTimeColumn get startedAt   => dateTime()();
  DateTimeColumn get endedAt     => dateTime().nullable()();
}

class LocalUsedWords extends Table {
  IntColumn  get matchId => integer()();   // FK → LocalMatches.id
  TextColumn get word    => text()();
  @override
  Set<Column> get primaryKey => {matchId, word};
}

class LocalPlayerStats extends Table {
  IntColumn     get id                 => integer().withDefault(const Constant(1))();
  IntColumn     get totalMatches       => integer().withDefault(const Constant(0))();
  IntColumn     get wins               => integer().withDefault(const Constant(0))();
  IntColumn     get bestScore          => integer().withDefault(const Constant(0))();
  IntColumn     get bestMatchStreak    => integer().withDefault(const Constant(0))();
  IntColumn     get dailyStreak        => integer().withDefault(const Constant(0))();
  IntColumn     get longestDailyStreak => integer().withDefault(const Constant(0))();
  TextColumn    get longestWord        => text().nullable()();
  DateTimeColumn get lastPlayedDate    => dateTime().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class LocalPowerupCache extends Table {
  TextColumn     get powerupType  => text()();                    // hint | freeze | extra_time | shield
  IntColumn      get quantity     => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  @override
  Set<Column> get primaryKey => {powerupType};
}
```

### DAO responsibilities

| DAO | Key methods |
|---|---|
| `MatchDao` | `createMatch`, `updateMatch`, `getActiveMatch`, `getUnsyncedMatches`, `markSynced(id, remoteId)` |
| `UsedWordDao` | `insertWord(matchId, word)`, `isWordUsed(matchId, word) → bool`, `deleteWordsForMatch(matchId)` |
| `StatsDao` | `getStats`, `upsertStats`, `mergeWithRemote(RemoteStats)` — takes MAX of each numeric field |
| `PowerupCacheDao` | `getAll`, `setQuantity(type, qty)`, `refreshFromRemote(List<RemotePowerup>)` |

### Sync strategy (`SyncService`)

```
SyncService.sync()  ← idempotent; no-op if guest; safe to call on every app resume
  1. Upload unsynced matches
       fetch local_matches WHERE synced = false, ORDER BY startedAt ASC
       → POST /api/v1/game/solo for each
       → 200: set synced = true, store remoteId
       → 409 (already exists): mark synced = true silently
       → network error: abort remaining; retry on next trigger
  2. Merge stats
       GET /api/v1/profile/stats → StatsDao.mergeWithRemote()
  3. Refresh powerup cache
       GET /api/v1/powerup/inventory → PowerupCacheDao.refreshFromRemote()
```

**Sync triggers:** app foreground (authenticated), successful registration/login, connectivity restored, before joining multiplayer queue.

---

## 🌐 REST API Conventions

- Base path: `/api/v1/`
- Auth header: `Authorization: Bearer <jwt>`
- Content type: `application/json`
- Standard success: `{ "data": { ... } }`
- Standard error: `{ "error": { "code": "...", "message": "..." } }`
- Status codes: `400` validation, `401` unauthorized, `403` forbidden, `404` not found, `409` conflict, `429` rate limited, `500` server error
- All write endpoints rate-limited via Redis (60 req/min per user/IP)

### Endpoint list

**Auth:** `POST /auth/register` · `POST /auth/login` · `POST /auth/refresh`

**Game:** `POST /game/solo` · `GET /game/:id` · `GET /profile/stats` · `GET /powerup/inventory` · `POST /powerup/use`

**Matchmaking:** `POST /match/queue` · `DELETE /match/queue`

**Leaderboard:** `GET /leaderboard?type=global&limit=100` · `GET /leaderboard?type=friends&limit=100`

**Daily Challenge:** `GET /daily` · `POST /daily/retry`

**Friends:** `POST /friends/request` · `GET /friends` · `GET /friends/requests` · `POST /friends/respond` · `DELETE /friends/:friendId`

**Friend Challenges:** `POST /challenges` · `POST /challenges/:id/respond` · `GET /challenges/pending`

**Push Notifications:** `POST /notifications/token` · `DELETE /notifications/token`

---

## 🌐 WebSocket Event Protocol

```
Client → Server:
  { "type": "submit_word",  "word": "apple" }
  { "type": "use_powerup",  "powerup": "freeze" }
  { "type": "continue",     "method": "ad" | "coins" }   ← must arrive within 15s of loss_event
  { "type": "ping" }

Server → Client:
  { "type": "game_start",           "state": { ... } }
  { "type": "word_accepted",        "word": "apple", "score": 85, "next_letter": "e", "player_id": "..." }
  { "type": "word_rejected",        "reason": "not_in_dictionary" | "wrong_letter" | "already_used" | "too_short", "player_id": "..." }
  { "type": "turn_change",          "player_id": "..." }
  { "type": "timer_update",         "remaining_ms": 7400 }
  { "type": "loss_event",           "player_id": "...", "reason": "invalid_word" | "timeout" }
  { "type": "continue_window",      "player_id": "...", "deadline_ms": 15000 }
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
- `streak` is consecutive successes *before* this word.
- `rarity_bonus` is **not applied in solo/AI mode** — the Flutter scorer omits it (frequency file is backend-only). Solo scores are excluded from the competitive leaderboard, so this asymmetry is acceptable.

---

## 🔐 Guest Mode & Auth Strategy

**Core principle: never block a player from playing before they're hooked.**

### What guests can do
- Play Solo and vs AI — fully offline, no server calls
- Accumulate stats persisted to local Drift DB, preserved across restarts
- Use 5 Hint power-ups per session (tracked in `GameBloc` state, reset on restart)
- Resume an interrupted game on next app launch

### What requires registration
- Online multiplayer, Daily Challenge, leaderboard, friends system
- Cloud-synced stats, persistent coins and power-up inventory

### Guest power-up allowance
5 free Hint uses per session. All other power-ups require registration. On last use or tapping a locked power-up, show soft upsell: *"Register free to save your progress and unlock more power-ups."* Never hard-block.

### Guest-to-registered conversion
On register/login, `AuthCubit` triggers `SyncService.sync()` immediately. History from any prior session is preserved because it lives in the local DB. On `409` conflict from API: mark local row `synced = true` silently.

### Auth flow
```
App launch
  ├── Stored JWT valid?  → /home (full features)
  ├── No token?          → /home (guest mode)
  └── Token expired?     → silent refresh → success: /home | fail: /home (guest)

Tap "Find Match", "Leaderboard", "Friends", or "Daily Challenge"
  └── Guest? → /login?return=<destination>
```

`AuthCubit` must expose an `isGuest` flag. Only multiplayer queue and leaderboard write path force a login redirect.

---

## 💸 Monetization Model

**Hybrid freemium: ads + soft IAP. No hard paywalls. No pay-to-win.**

| Stream | Details |
|---|---|
| Rewarded ads | Watch ad → earn 20 coins or use as a free continue |
| Coin IAP bundles | $0.99 / $2.99 / $9.99 |
| Remove Ads IAP | ~$2.99 one-time; keeps rewarded ads (player-initiated) |
| Premium subscription | ~$3.99/mo; no ads + 200 coins/week |

### Coin economy

**Earn:** Win match +30 · Daily login +10 · Watch rewarded ad +20 · Match streak ≥5 +15 · Daily streak 3d +30 · 7d +100 · 30d +500 · Weekly leaderboard 1st +500 · 2nd +300 · 3rd +100

**Spend:** Hint 10 · Freeze 20 · Extra Time 15 · Continue (Classic) 25 · Daily Challenge retry 25

No energy systems, no artificial wait timers, no interstitial ads during an active game.

---

## 🔋 Power-up Reference

| Power-up | Effect | Solo/AI limit | Multiplayer limit | Guest? |
|---|---|---|---|---|
| **Hint** | Suggests a valid word for the required starting letter | Unlimited | 1 per match | 5 per session (free) |
| **Freeze** | Pauses opponent's timer +5s on their next turn | N/A | 1 per match | ❌ Registered only |
| **Extra Time** | Adds 8s to current player's turn timer | Unlimited | 1 per match | ❌ Registered only |
| **Shield** | Auto-negates next loss-causing event. Fires before continue prompt. Does not stack. | 1 per game | 1 per match | ❌ Registered only |

Both players' inventories are visible at match start. Multiplayer limits enforced server-side — server rejects any second use regardless of client state.

---

## 🤖 AI Opponent

| Level | Response delay | Mistake rate | Min word length | Strategy |
|---|---|---|---|---|
| Easy | 3s | 25% | 3 | Random valid word |
| Medium | 1.5s | 10% | 4 | 30% trap-letter preference |
| Hard | 0.6s | 2% | 6 | 70% trap-letter preference; longest valid trap word when available |

**Trap letters**: Q, X, Z, J, V. Trap preference only when at least one trap-ending word exists for the required starting letter; otherwise falls back to weighted random. Implemented in `internal/service/ai.go`.

---

## 📅 Daily Streak

- Completing any game (solo, AI, multiplayer, or Daily Challenge) before midnight UTC counts for that day.
- Missing a day resets the streak to 0.
- Tracked in `player_stats.daily_streak` and `player_stats.last_played_date`.
- `RecordGamePlayed(userID string, date time.Time)` called at every game end — updates streak, awards milestone coins, enqueues push notification.

| Milestone | Reward |
|---|---|
| 3 consecutive days | +30 coins |
| 7 consecutive days | +100 coins |
| 30 consecutive days | +500 coins |

Milestones repeat: next cycle is 60, 90, etc.

**At-risk notification**: streak ≥ 3, not played today, local time ≥ 20:00 → push *"Your [N]-day streak is at risk!"*

---

## 👥 Social Features

### Friend system
- Search by exact username. `POST /friends/request` → push notification to target.
- Accepted friendships are bidirectional (service checks both directions of the row).
- Friends tab on Leaderboard shows friends ranked by the same Redis sorted set.

### Friend challenges
- From a friend's profile → Challenge → choose Classic or Time Attack.
- Record created with `expires_at = NOW() + 24h`. On accept: private match room (bypasses matchmaking queue). On decline/expiry: challenger notified. `ExpireOldChallenges` runs every 5 minutes.

### Daily Challenge share card
```
WordChain Daily #[N]
Score: [score] | Chain: [chain_length] words
[word1] → [word2] → ... → [last_word]
Play at wordchain.app
```
Day N = days since `GAME_EPOCH_DATE`, 1-indexed. `share_service.dart` → `shareDaily(DailyChallengeResult)` → `Share.share()`.

---

## 🔔 Push Notifications

All sent via FCM HTTP v1 API. Tokens registered at login, deregistered at logout.

| Trigger | Message |
|---|---|
| Daily Challenge available (midnight UTC) | "Today's Word Chain challenge is ready." |
| Streak at risk (20:00 local, streak ≥ 3) | "Your [N]-day streak is at risk!" |
| Streak milestone | "[N]-day streak! You've earned [coins] coins." |
| Friend request | "[Username] wants to be your friend." |
| Friend challenge received | "[Username] challenged you to a [Mode] match!" |
| Friend challenge response | Accepted / declined / expired message |
| Match found | "Opponent found! Your match is ready." |
| Weekly leaderboard reward | "You finished #[rank] and earned [coins] coins!" |

**Backend**: `internal/service/notification.go` — `SendToUser(userID, title, body)`.
**Scheduler** (1-min ticker): midnight daily challenge push · every-minute streak-at-risk check · every-5-min challenge expiry · Sunday 00:00 weekly reset.
**Flutter**: `notification_service.dart` — FCM permission after tutorial, token registration, foreground banners, payload stream for deep-link routing (`/daily`, `/friends`).

---

## 🎓 Tutorial (First-Time Player)

Auto-triggered on first launch. Skippable; replayable from Profile → Help. Completion flag: `tutorial_completed` in `shared_preferences`.

| Step | Instruction | Action |
|---|---|---|
| 1 | "Type any word to start the chain!" | Any valid word ≥ 3 letters |
| 2 | "Now type a word starting with **[letter]**!" | Valid continuation |
| 3 | "Great! Keep going — you can't reuse words." | One more valid word |
| 4 | "You're ready! Try Classic, Time Attack, or the Daily Challenge." | Tap "Start Playing" |

- Sandboxed in-memory state; no match record created.
- Invalid words show inline prompt, not game-over.
- After tutorial (if still guest): soft upsell *"Register free to save your progress and unlock power-ups."*

---

## 🏆 Leaderboard & Weekly Reset

- Redis Sorted Set `leaderboard:global:weekly` — score added at end of **multiplayer and Daily Challenge games only** (not solo).
- `GET /leaderboard?type=friends` fetches friend IDs, retrieves scores via `ZSCORE` from the same set.

**Weekly reset (Sunday 00:00 UTC):**
1. Query top 3 → insert `weekly_leaderboard_rewards` (idempotent)
2. Award coins: 1st →500, 2nd →300, 3rd →100
3. Send push notifications to rewarded users
4. Delete Redis key

---

## 🧪 Testing Strategy

Tests written **inside the phase that introduces the code**.

**Backend (Go):** Unit tests for `engine/`, `service/`, `scheduler/`. Repository tests use real Postgres container (`testcontainers-go`). Handler tests use `httptest` with stubbed service. WS tests use `httptest.Server` with real client. Target ≥ 70% coverage on `engine/` and `service/`.

**Flutter:** Widget tests for each screen's primary states. Bloc/Cubit tests via `bloc_test`. Golden tests for `WordChainList` and `TimerBar`. Mock `DictionaryService`, `WebSocketService`, `NotificationService` — do not load the real wordlist.

**Integration:** See PLAN.md Phase 16 for full end-to-end smoke flows.

---

## 🔁 Session Workflow

1. Read **CLAUDE.md** (specs, rules) and **PLAN.md** (phase scope)
2. State the phase: *"Implement Phase N — [title]"*
3. Mark `[x] Complete` in both the CLAUDE.md status table and the PLAN.md per-phase status line
4. Commit before starting the next phase

---

## ⚠️ Important Notes for Claude Code

- **Never implement outside the current phase's scope.** Flag missing items from prior phases without silently fixing them.
- **Always check previous phases' output** before writing code that depends on it (verify actual method signatures).
- **Keep CLAUDE.md status table and PLAN.md per-phase status lines in sync.**
- **Dictionary is dual:** `enable.txt` lives in both `backend/internal/engine/data/` and `client/assets/words/`. Keep them byte-identical.
- **`word_freq_ranks.txt` is backend only.** Rarity bonus is server-side; omit it from the Flutter scorer.
- **Never require login to start a solo or vs-AI game.** Guest mode is first-class.
- **Local DB is the source of truth for solo/AI games.** The backend is never called during an active solo or AI game.
- **Daily Challenge never appears in the multiplayer lobby.**
- **Power-up limits in multiplayer are enforced server-side.** Server rejects any second use regardless of client state.
- **Do not hardcode game tuning values.** Read from `config.go` (Go) and `GameConfig` constant (Flutter).
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
| `CORS_ORIGINS` | no | `http://localhost:*` | Comma-separated |
| `FCM_PROJECT_ID` | yes | `wordchain-prod` | Firebase project ID |
| `FCM_SERVICE_ACCOUNT_JSON` | yes | (path or inline JSON) | Service account for FCM auth |
| `GAME_EPOCH_DATE` | no | `2025-01-01` | Day #1 for Daily Challenge numbering |

---

## 📎 Appendix: Dictionary & Word Frequency List

**ENABLE wordlist** — ~172,820 words, public domain, one lowercase word per line, ASCII only, no proper nouns. Stored at `backend/internal/engine/data/enable.txt` and `client/assets/words/enable.txt` (byte-identical). Memory: ~1.7 MB plain text, ~6–8 MB in-memory set.

**`word_freq_ranks.txt`** — tab-separated `word\trank`, lowercase, sorted by rank ascending. Source: freely licensed corpus (e.g. Wikipedia CC BY-SA) filtered to ENABLE words. Words with rank > 10,000 earn `rarity_bonus`; missing words treated as rank ∞. Backend only at `backend/internal/engine/data/word_freq_ranks.txt`.
