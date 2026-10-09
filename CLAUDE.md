# CLAUDE.md — WordChain Project

Read this file at the start of every session (and **REDESIGN_PLAN.md** when touching UI).

---

## 📌 Project Summary

A production-ready word-chain mobile game (Shiritori-style).
- Player enters a word starting with the last letter of the previous word
- Words must be valid (dictionary-checked), no repetition allowed
- Two orthogonal axes:
  - **Opponent**: Solo (vs self), AI (Easy/Medium/Hard), or 1v1 Real-time multiplayer
  - **Match variant**: Classic only (Time Attack was removed); Daily Challenge is **solo-only**
- In multiplayer, both players contribute to a **single shared chain**, alternating turns

---

## 📊 Phase Status


| # | Phase | Status |
|---|---|---|
| 1 | Flutter: Core Setup | [x] Complete |
| 2 | Flutter: Game Feature (Solo + Tutorial — tutorial later removed) | [x] Complete |
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
| 16 | Monetization Hooks & Final Wiring | [x] Complete |
| 17 | Visual Redesign (زنجیر) | [ ] In Progress — Stages 1–5 complete and on-device verified; Stage 6 code complete (multiplayer game-over/overlays on tokens, legacy `AppColors` removed) — needs a live multiplayer match to verify; Stage 7 partial (shared-widget goldens + token lint done, chain-renderer goldens remaining) |
| 18 | Bug Fixes & Quick Wins | [ ] Not Started |
| 19 | Multiplayer Lives & Best-of-5 Rounds | [ ] Not Started |
| 20 | Progression & Lobby Economy | [ ] Not Started |
| 21 | Production Readiness | [ ] Not Started |
| 22 | Premium Perks (taunts, avatars, badge) | [ ] In Progress — backend + client code complete, backend verified live (WS + REST); client UI **not yet verified on-device**; real billing (Bazaar/Myket) not built |

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
| Auth | Phone number + 4-digit OTP (Kavenegar SMS) → JWT (access + refresh tokens). No email/password. |
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
│   │   │       ├── fa.txt                       ← Persian dictionary
│   │   ├── scheduler/                          ← background jobs
│   │   └── middleware/
│   ├── migrations/
│   ├── Dockerfile
│   └── docker-compose.yml
└── client/
    ├── pubspec.yaml
    ├── assets/
    │   └── words/fa.txt
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

**Current source of truth (Phase 17): the زنجیر Claude Design canvas**, project `4a90de7c-3340-476f-922d-213a9dcd6307`. Full plan, token values, spec-conflict decisions, and per-stage notes live in **REDESIGN_PLAN.md** — read it before touching any screen.
- Fetch screens with the `DesignSync` tool: `method: "get_file"`, `projectId: "4a90de7c-3340-476f-922d-213a9dcd6307"`, `path: "<File>.dc.html"`. WebFetch/browser access to `claude.ai/design/...` returns 403, and `list_projects` doesn't surface this canvas — `get_file` still works.
- Screen files: `ZHome`, `ZSolo`, `ZPlay`, `ZOver`, `ZLobby`, `ZVersus`, `ZDailyBefore`, `ZDailyAfter`, `ZBoard`, `ZProfile`, `ZFriends`, `ZPhone`, `ZOtp`; `Zanjir.dc.html` holds the token sheet.
- The PNGs in `figma/` are the **legacy** Phase 1–16 references, superseded by the canvas for any screen it covers.

Do not invent layouts — if a screen is covered by a design file, follow it. If a detail is ambiguous, match the overall visual style and spacing of the nearest reference. Screens with no canvas design (e.g. the opponent-deciding overlay, friend challenge sheet) are derived from the token system (REDESIGN_PLAN.md Stage 6). `ZOverScreen` is the single game-over/continue screen for solo, vs-AI and multiplayer.

### Visual system rules (Phase 17)
- **A screen never names a hex value.** Read colors from the `ZColors` theme extension via `context.z.<token>` (`core/theme/app_tokens.dart`). Light/dark are the same widgets with different token values. Any `Color(0x…)` in a screen file is a bug.
- The legacy `AppColors` palette is **removed**; `AppTheme.light`/`dark` are both built from `ZColors`. `test/core/theme/token_coverage_test.dart` fails the build on hardcoded colours.
- Typeface: Vazirmatn (vendored in `assets/fonts/`). Spacing/radii/elevation/motion come from `core/theme/app_spacing.dart`, `app_elevation.dart`, `app_motion.dart`.
- **Zero-blur elevation**: solid offset edges only (`solidEdge(...)`); pressed state removes the offset and translates Y +3.
- **Persian digits everywhere** (۰۱۲…, thousands separator «٬») via `core/utils/persian_digits.dart`. Dates use Jalali (`shamsi_date`).
- **RTL-native**: use `EdgeInsetsDirectional`, `start`/`end` alignment — never `left`/`right`.
- Reuse the shared widgets in `core/widgets/` (`LetterTile`, `SolidCard`, `AccentButton`/`NeutralButton`, `CoinPill`, `TintChip`, `AvatarTile`, `SectionHeader`, `StreakStrip`, `ZBottomNav`).
- Theme mode: `ThemeCubit` (persisted in `shared_preferences`, defaults to `ThemeMode.system`), toggled from ZProfile's حالت شب switch.
- **Real-data-only**: never fabricate stats the API doesn't provide (player counts, percentiles, opponent records). Substitute a real field or drop the element, and note it in REDESIGN_PLAN.md.

---

## 📐 Coding Rules (apply in every session)

- Backend: strictly 3 layers — `handler → service → repository`. No domain layer.
- Flutter: feature-based folders only. No forced layered architecture per feature.
- Each feature only has what it needs: `cubit/` or `bloc/`, `data/`, `view/`.
- Use `get_it` for all DI. Never use `Provider` or `InheritedWidget` for DI.
- Use `go_router` for all navigation. Never call `Navigator.push` directly.
- The four main tabs are kept alive by the shell, so each reloads when its bottom-nav tab is tapped (including a re-tap): `ZBottomNav` taps publish on `TabRefreshBus` (`core/utils/tab_refresh.dart`); tabs subscribe via `TabRefreshListener` / directly (Home) and reload silently (`load(silent: true)` — no spinner, failures keep the current data). New tab screens should do the same.
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
- **All user-facing API error/success text is Persian and lives in `core/utils/error_messages.dart`.** Never show the backend's English `message` or `e.toString()`: repositories build exceptions from `apiErrorCode(e)` + `errorMessageFor(code)`; cubits/screens show that message. Success toasts use the helpers there (`challengeSentMessage`, `coinsAwardedMessage`, …). Adding a backend `respondError` code requires a Persian entry — `test/core/utils/error_messages_test.dart` fails otherwise.

### Logging
- **Go**: `slog` only. Structured fields, no `fmt.Println`. Log at boundaries (handler entry, repo errors, WS events). No PII or passwords in logs.
- **Flutter**: `logger` package. Levels: `v`/`d`/`i`/`w`/`e`. Strip verbose logs in release builds via build flags.

---

## 🎮 Game Modes & Rules

### Match variants

| Variant | Opponent options | Turn timer | End condition |
|---|---|---|---|
| **Classic** | Solo, AI, 1v1 Multiplayer | 15s per turn | First invalid/timeout move loses; one continue per player allowed |
| **Daily Challenge** | **Solo only** | 15s per turn | Out of lives (see Lives below) or after 20 words; score posted to daily leaderboard |

**Daily Challenge never appears in the multiplayer lobby.**

Defaults above are tunable in `internal/config/config.go` and via `GameConstants` on the Flutter side (`client/lib/features/game/data/game_constants.dart`). Do not hardcode magic numbers in handlers, blocs, or widgets.

### Lives (Phase 17, Flutter-only)
- **Solo Classic and Daily Challenge** give the player `GameConstants.soloLives` (**2**) lives. A mistake (invalid word or timeout) with lives remaining costs a life and the match continues; the match ends when lives reach 0. So "first invalid move loses" above applies to these modes only once lives are exhausted.
- **Not applied** to vs-AI or 1v1 multiplayer. Multiplayer is server-authoritative and the Go WS protocol has no lives concept — the canvas's «۲ جان» chip is intentionally omitted from ZVersus until the backend supports it.
- Daily's `dailyMaxWords` (20) cap is unchanged.

### Multiplayer shared chain
In any multiplayer match (vs AI or 1v1), **both players contribute to a single shared word chain**:
- Players alternate turns on the same chain.
- The first player to submit an invalid word, let the timer expire, or concede loses — unless they invoke a continue (Classic only).

### Continue Rules (Classic mode only — solo and multiplayer)
1. On a loss event: player may **Watch a rewarded ad** (free) or **Spend 25 coins** (instant).
2. On continue: chain resumes from the last valid word; it is that player's turn again.
3. Each player may use **at most one continue per match**.
4. In multiplayer, the opponent sees "Opponent deciding…" with a **15-second countdown**. If it expires, the loss stands.
5. **Shield interaction**: Shield auto-activates *before* a loss event; the continue prompt appears only if no Shield is held.

### Word validation rules
Apply identically in Go (`engine.ValidateMove`) and Flutter (`DictionaryService.isValid`):

1. **Normalize**: trim whitespace, lowercase.
2. **Allowed characters**: Persian letters (incl. hamza forms ء آ أ ؤ ئ) plus ZWNJ (U+200C, legal *within* a word, e.g. "می‌روم"). Reject digits, spaces, hyphens, Latin letters, and non-Persian Arabic letters (e.g. ي, ك).
3. **Minimum length**: 3 letters. Reject with reason `too_short`.
4. **Starting letter**: must equal the last letter of the previous accepted word. First word has no constraint.
5. **No repetition**: reject duplicates with reason `already_used`.
6. **Dictionary check**: must exist in the Persian dictionary (`fa.txt`).

### Streak rules
- **Match streak**: consecutive successful word submissions by the same player in one match. Resets on rejection/timeout. `streak_bonus` uses the count *before* the current word.
- **Daily streak**: consecutive calendar days (Iran time, UTC+3:30) with at least one completed game. Tracked server-side in `player_stats`.

### Solo end conditions
Match ends when the player submits an invalid word, the timer hits 0, or they tap "End game".

---

## 🗄️ Database Schema

```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(32) UNIQUE,               -- NULL until signup completes (first verify-otp)
    phone VARCHAR(11) UNIQUE NOT NULL,         -- normalized 09XXXXXXXXX (Iran mobile)
    otp_code CHAR(4),
    otp_expires_at TIMESTAMPTZ,
    otp_attempts SMALLINT NOT NULL DEFAULT 0,
    otp_sent_at TIMESTAMPTZ,                   -- last send, for the resend cooldown
    phone_verified_at TIMESTAMPTZ,             -- NULL = signup not yet completed
    referral_code VARCHAR(6) UNIQUE,           -- NULL until signup completes
    referred_by UUID REFERENCES users(id),     -- NULL if no referrer linked
    coins INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE matches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    mode VARCHAR(20) NOT NULL,        -- classic, daily
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
  TextColumn    get mode         => text()();                    // classic
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

**Auth:** `POST /auth/send-otp` · `POST /auth/verify-otp` · `POST /auth/refresh`

**Referral:** `GET /referral/me` (own code, for sharing) · `GET /rewards` · `POST /rewards/:id/claim` (claimable prizes) · `POST /referral/redeem` — post-login, one-time entry point (b); see § Referral Code System below.

**Game:** `POST /game/solo` · `GET /game/:id` · `GET /profile/stats` · `PATCH /profile/username` (3–20 letters/digits/`_`; `400 invalid_username`, `409 username_taken`) · `GET /profile/perks` (`is_premium`, `premium_until`, `avatar_id`) · `PATCH /profile/avatar` (premium only; `403 premium_required`, `400 invalid_avatar`) · `GET /powerup/inventory` · `POST /powerup/use`

**Matchmaking:** `POST /match/queue` · `DELETE /match/queue`

**Leaderboard:** `GET /leaderboard?type=global&limit=100` · `GET /leaderboard?type=alltime&limit=100` · `GET /leaderboard?type=friends&limit=100`

**Daily Challenge:** `GET /daily` · `GET /daily/leaderboard` · `POST /daily/retry`

**Friends:** `POST /friends/request` · `GET /friends` · `GET /friends/requests` · `POST /friends/respond` · `DELETE /friends/:friendId`

**Friend Challenges:** `POST /challenges` · `POST /challenges/:id/respond` · `GET /challenges/pending` · `GET /challenges/joinable` (challenger's accepted challenges whose room still awaits them)

**Push Notifications:** `POST /notifications/token` · `DELETE /notifications/token`

---

## 🌐 WebSocket Event Protocol

```
Client → Server:
  { "type": "submit_word",  "word": "apple" }
  { "type": "use_powerup",  "powerup": "freeze" }
  { "type": "continue",     "method": "ad" | "coins" }   ← must arrive within 15s of loss_event
  { "type": "send_taunt",   "taunt": "hurry_up" }         ← premium only; ID from config.TauntIDs
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
  { "type": "taunt",                "player_id": "...", "taunt": "hurry_up" }        ← sent to both players
  { "type": "taunt_rejected",       "reason": "premium_required" | "rate_limited" }  ← sender only
  { "type": "pong" }
```

Client reconnect: exponential backoff (1s, 2s, 4s, capped at 8s) for up to 30 seconds. After 30s, treat as forfeit. Server holds the room open for the same 30s grace window.

---

## 💰 Scoring Formula

```
base_score   = letters(word) × 10          ← letters/runes, never UTF-8 bytes
speed_bonus  = max(0, (time_limit - response_time_sec) × 2)
streak_bonus = streak >= 3 ? base_score × 0.5 : 0
turn_score   = base_score + speed_bonus + streak_bonus
```

- **Long-word bonus (Phase 17, Flutter solo/AI only)**: words with ≥ `GameConstants.longWordBonusMinLength` (7) letters have their turn score multiplied by `longWordBonusMultiplier` (2.0) in `GameBloc._calculateScore`. The Go scorer does **not** apply it yet — multiplayer support is follow-up work.

- `time_limit` is the turn timer for the current match variant.
- `streak` is consecutive successes *before* this word.
- **No rarity bonus.** It depended on an English word-frequency list (`word_freq_ranks.txt`), removed 2026-09-28 — no Persian frequency data exists. Go and Flutter scorers are now identical apart from the long-word bonus above.
- Go counts letters with `utf8.RuneCountInString` (it previously used `len(word)`, i.e. bytes, which doubled every Persian multiplayer score).

---

## 🔐 Guest Mode & Auth Strategy

**Core principle: never block a player from playing before they're hooked.**

Screens: `ZLoginScreen` (`/login`, phone entry) and `ZOtpVerifyScreen` (`/login/otp`, 4-box OTP driven by the phone's own number keyboard via a hidden TextField) in `features/auth/view/`. The old email/password `login_screen.dart`/`register_screen.dart` and `/register` route are gone. A dev/test bypass code `1111` exists while no Kavenegar account is purchased; real SMS delivery is still unverified end-to-end.

Identity is phone number + OTP (Kavenegar SMS), not email/password — there is no username/email login. `POST /auth/send-otp` generates and delivers a 4-digit code (~2min expiry, 120s resend cooldown, rate-limited); `POST /auth/verify-otp` checks it and issues a session. First-time verification of a phone number **is** signup — a username and referral code are auto-generated at that point (`AuthService.VerifyOTP`, `backend/internal/service/auth.go`). Guest local/offline data (below) is intentionally **not** tied to this schema and is not migrated into a phone account on signup — open item, not yet built.

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

## 🔗 Referral Code System

Every user gets a unique 6-char alphanumeric `referral_code` (charset excludes ambiguous `0/O/1/I`), assigned when signup completes (first successful `verify-otp`, not at row creation). Two entry points, both landing on the same server-side link/reward logic:

1. **At signup** — an optional `referral_code` on `POST /auth/verify-otp` for a phone verifying for the first time. If it resolves, `referred_by` is linked and the **new** user gets **+100 coins**. An unresolvable code never blocks signup — it comes back as a soft `referral_warning: "referral_not_found"` field on the 200 response, not an error.
2. **Post-login** — `POST /referral/redeem` (protected), for an existing account that hasn't linked a referrer yet. One-time only (`referred_by IS NULL` check, atomic) — `409 referral_already_used` on a second attempt. Awards **+50 coins**.

Self-referral (code equals the caller's own) is rejected (`400 self_referral`) — structurally impossible at signup since the new code doesn't exist yet, checked explicitly for the post-login path.

**Renaming:** ZProfile's pencil icon (signed-in only) opens `EditUsernameSheet` (`features/auth/view/widgets/edit_username_sheet.dart`) → `PATCH /profile/username` (`AuthService.UpdateUsername`). The JWT keeps the old username in its claims until refresh; nothing authoritative reads it.

**Sharing your own code:** ZProfile's `_InviteCard` loads it via `GET /referral/me` and shares a short Persian invite text + code through `ShareService.shareInvite` (system share sheet → social apps/SMS).

**Inviter reward (+50 coins, `config.CoinReferralInviter`):** whenever a referral is linked (either entry point) an unclaimed `inbox_rewards` row is created for the referrer.

Client: both entry points are served by one shared widget, `ReferralBottomSheet` (`client/lib/features/auth/view/widgets/referral_bottom_sheet.dart`), which branches on `AuthCubit`'s state (authenticated → redeem directly; not yet authenticated → stash the code and forward it into `verify-otp`). Triggered from the ZLogin phone screen's referral teaser card (entry point a) and from Profile → Settings (entry point b) — the latter is a deliberate small addition beyond the two named screens (`ZLobby`'s `_InviteRow` referral placeholder is unrelated and stays a stub).

---

## 🎁 Prize Rewards & Messages

**Time zone:** all server day boundaries (Daily Challenge day, streak days, daily-login, prize payouts, scheduler) use Iran time, fixed UTC+3:30 (`config.IranLocation`/`config.IranDate`; no DST since 2022). Client countdowns use `core/utils/iran_time.dart`.

Every claimable prize is a row in `inbox_rewards` (migration `007`; `kind` = `referral_reward` · `streak` · `weekly_rank` · `daily_login` · `daily_done` · `daily_rank`, unique per `(user_id, kind, ref)` so awards are idempotent). Coins are credited only by `POST /rewards/:id/claim` (atomic, once). The home gift icon (`features/rewards/`, route `/rewards`) shows a badge with the unclaimed count; claimed rewards disappear from the list `config.RewardClaimedRetention` (24h) after claiming; `GET /rewards` also returns the live server coin balance, which the client uses to overwrite its stale local balance. Streak milestones, weekly top-3 rewards and referrals also send an FCM push (no-op while FCM is unconfigured). **Daily login +10** is created lazily on the first `GET /rewards` of each UTC day. **Daily Challenge prizes** (`DailyService.RunDailyPayout`, scheduler checks every 5 min for the day that just ended at Iran midnight, Redis flag `payout:daily:<date>`): every finisher gets +10 (`daily_done`), the top 3 an extra +100/+60/+30 (`daily_rank`, ties share a rank). Today's ranking is `GET /daily/leaderboard` (ZDailyAfter/Before «جدول امروز» → `/daily/board`). **Welcome bonus +50** (`config.CoinWelcome`) is credited directly at signup, on top of any referral bonus.

**Messages (inbox icon next to the gift, `features/messages/`, route `/messages`):** actionable invitations only — pending friend requests (`GET /friends/requests`) and friend challenges (`GET /challenges/pending`, now includes `challenger_username`), with accept/decline reusing the friends endpoints; accepting a challenge enters the room. The badge is the combined count. No new backend store; announcements would be a later addition.

---

## 💸 Monetization Model

**Hybrid freemium: ads + soft IAP. No hard paywalls. No pay-to-win.**

| Stream | Details |
|---|---|
| Rewarded ads | Watch ad → earn 20 coins or use as a free continue |
| Coin IAP bundles | Toman-denominated (not USD-pegged): ۱۰۰ coins ۹٬۰۰۰ · ۳۵۰ coins ۲۵٬۰۰۰ · ۱۵۰۰ coins ۷۹٬۰۰۰ Toman (`MockMonetizationService`, `ZProfile` buy sheet) |
| Remove Ads IAP | ۱۵٬۰۰۰ Toman one-time; keeps rewarded ads (player-initiated) |
| Premium subscription | no ads + 200 coins/week + taunts + avatars + badge (see § Premium Perks). Price is **Rial-denominated** for the Iranian market, not USD: launch proposal ۱۹۰٬۰۰۰ Rials/month (۱۹٬۰۰۰ Toman; show Toman in the UI), 3 months ۴۹۰٬۰۰۰, yearly ۱٬۴۹۰٬۰۰۰, weekly ۷۰٬۰۰۰ (lowered twice from ۹۹٬۰۰۰ Toman/month, 2026-10; deliberately cheap — entertainment spend is minimal in the current economy). Unvalidated — no competitor price data could be found (store pages hide IAP amounts); A/B the monthly price. Free-market dollar ≈ ۲۶۶٬۰۰۰ Toman on 2026-10-09, so a literal USD conversion ($0.99 ≈ ۲۶۳٬۰۰۰ Toman) was rejected as unaffordable |

### Coin economy

**Earn:** Win match +30 · Daily login +10 · Watch rewarded ad +20 · Match streak ≥5 +15 · Daily streak 3d +30 · 7d +100 · 30d +500 · Weekly leaderboard 1st +500 · 2nd +300 · 3rd +100 · Referral signup bonus (new user, valid code supplied at signup) +100 · Referral redeem (existing user, one-time post-login) +50 · Welcome bonus +50 (every new account) · Referral inviter reward +50 per invited user. Streak, weekly-rank, daily-login, daily-challenge and inviter prizes are claimed from the inbox

**Entry fee (1v1 human matches only):** each player pays `config.EntryFeeCoins` (20, mirrored as `GameConstants.entryFeeCoins`) when the second player joins; the winner takes the whole pot (2 × fee), a draw refunds both, matches vs the AI fallback are free. Charged/settled server-side in `ws.Room` (`chargeEntryFees` / `settleEntryFees`); `game_start.state.entry_fee` and `game_over.payout` tell the client; `match_cancelled` (`insufficient_coins`) aborts a match where someone can no longer pay. Queue join and challenge create/accept pre-check the balance (`402 insufficient_coins`).

**Coin shortfall UX:** every blocked-by-coins action (queue join, challenge send/accept, daily retry, solo continue-with-coins, multiplayer `match_cancelled`/`insufficient_coins`) opens the shared `showInsufficientCoinsDialog` (`core/widgets/insufficient_coins_dialog.dart`), which lists real ways to earn coins (rewarded ad, Daily Challenge, invites, daily/streak rewards, winning a pot) with links to those screens. Mid-game power-up shortfalls keep the pause-aware `_NeedCoinsSheet` instead (navigating away would abandon the match). New coin-gated actions should call the dialog rather than a toast.

**Spend:** Hint 10 · Freeze 20 · Extra Time 15 · Continue (Classic) 25 · Daily Challenge retry 25

No energy systems, no artificial wait timers, no interstitial ads during an active game.

---

## 👑 Premium Perks (Phase 22)

Cosmetic/social only — **never gameplay advantages** (no free power-ups in multiplayer, no entry-fee discounts, no matchmaking edge).

- **State:** `users.premium_until` (TIMESTAMPTZ, migration `010_premium_perks`) — premium ⇔ `premium_until > now()`. It is set **server-side only**; no client endpoint can grant it. **Real billing (Cafe Bazaar / Myket / gateway receipt verification) is not built**: until it is, grant premium with `bash scripts/grant_premium.sh [-d DAYS] [--revoke|--dry-run] <phone>…` (runs the SQL on the production DB over SSH; default +30 days, extends any remaining time). Manual coin top-ups: `bash scripts/grant_coins.sh <amount> <phone>…`. `MockMonetizationService.purchase('premium_monthly')` still just returns success without granting anything — misleading, flagged, not fixed.
- **Taunts (1v1 multiplayer):** premium players *send* preset messages, everyone *receives* them (the free-user exposure is the upsell). Client sends `send_taunt {taunt: id}`; `Room.processTaunt` rejects unknown IDs silently, re-checks the subscription on every send (`PerkLookup.GetPerks`, DB lookup outside the room lock), and enforces `config.TauntCooldownSec` (5 s) + `config.TauntMaxPerMatch` (8) per player. Preset IDs only — **never free text**. Persian text lives in `core/utils/premium_catalog.dart`; `test/core/utils/premium_catalog_test.dart` fails if the Dart IDs drift from `config.TauntIDs`/`config.AvatarIDs`. UI: chat button in ZVersus' header (lock icon + upsell text for free players), bottom sheet of chips, transient bubble (`_TauntBubble`, 3 s) driven by `GameActive.tauntId/tauntFromMe/tauntSeq`.
- **Avatars:** 16 IDs (`config.AvatarIDs`, opaque keys — the names no longer describe the art) rendered by `AvatarTile(avatarId:)` from bundled PNGs `client/assets/avatars/<id>.png` — DiceBear **Lorelei** (by Lisa Wischofsky, **CC0 1.0**, no attribution required), seeds `zanjir-<id>`, calm-smile mouths only, pastel backgrounds; regenerate with `https://api.dicebear.com/9.x/lorelei/png?seed=zanjir-<id>&size=256&backgroundType=solid&backgroundColor=b6e3f4,c0aede,ffd5dc,ffdfbf,d1d4f9&mouth=happy01,happy02,happy03,happy04,happy05,happy06,happy13`. Swap for commissioned illustrations later without changing the IDs. Picker: ZProfile → «تغییر آواتار» (premium) → `PATCH /profile/avatar`. `GetPerks` returns `avatar_id` only while premium is active, so a lapsed subscription silently falls back to the initial. Shown in ZProfile, ZVersus (via `game_start.state.avatars`) and the **leaderboard** (all three tabs: `LeaderboardEntry.avatar_id` per row + `player_avatar_id` for the self row, via `LeaderboardService.attachAvatars`); **not yet** in the friends list.
- **Badge:** crown icon next to the name in ZProfile and ZVersus (`game_start.state.premium`).
- **Not built:** the 200 coins/week grant, a subscription-expiry push, avatars/badge in the friends list (leaderboard avatars done; badge not), the Flutter purchase flow.

---

## 🔋 Power-up Reference

| Power-up | Effect | Solo/AI limit | Multiplayer limit | Guest? |
|---|---|---|---|---|
| **Hint** | Suggests a valid word for the required starting letter | Unlimited | 1 per match | 5 per session (free) |
| **Freeze** | Pauses opponent's timer +5s on their next turn | N/A | 1 per match | ❌ Registered only |
| **Extra Time** | Adds 8s to current player's turn timer | Unlimited | 1 per match | ❌ Registered only |
| **Shield** | Auto-negates next loss-causing event. Fires before continue prompt. Does not stack. | 1 per game | 1 per match | ❌ Registered only |

**How a use is paid for (server-authoritative, `PowerupService.UseItem`):** owned inventory first; when the count is 0 it costs coins — Hint 10 · Freeze 20 · Extra Time 15 · Shield 20 (`config.PowerupPrice` / `GameConstants.powerupCostCoins`; Shield's price was not in the original spec). There is no separate shop yet, so inventory only grows via future rewards. The tile badge shows owned count, with the coin price beneath when it is 0. Solo/vs-AI apply the effect locally after the server call succeeds (Freeze is not offered there); multiplayer sends `use_powerup` over WS and the server answers `powerup_used` (with the caller's `coins`/`remaining`) or `powerup_rejected`. Guests: free Hint only; other tiles raise the register upsell.

Both players' inventories are visible at match start. Multiplayer limits enforced server-side — server rejects any second use regardless of client state.

---

## 🤖 AI Opponent

| Level | Response delay | Mistake rate | Min word length | Strategy |
|---|---|---|---|---|
| Easy | 3s | 25% | 3 | Random valid word |
| Medium | 1.5s | 10% | 4 | 30% trap-letter preference |
| Hard | 0.6s | 2% | 6 | 70% trap-letter preference; longest valid trap word when available |

The matchmaking AI-fallback opponent is persisted as a single fixed user, `config.SystemAIUserID` (`00000000-0000-0000-0000-000000000001`, seeded by migration `004_ai_system_user`), with `match_players.is_ai = true`. It is never recorded in `player_stats` or the weekly leaderboard.

**Trap letters**: ژ ظ ث ذ ض — the five letters that the fewest `fa.txt` words start with (33–69 words each). ی is deliberately excluded (few words start with it, ~2.6k end with it). Trap preference applies only when at least one trap-ending word exists for the required starting letter; otherwise it falls back to random. Go: `config.AITrapLetters` + `engine.SelectAIWord` (rune-based); Flutter: `aiTrapLetters` in `core/services/ai_opponent.dart`. Keep both in sync. The table's "Min word length" is in letters, not bytes.

---

## 📅 Daily Streak

- Completing any game (solo, AI, multiplayer, or Daily Challenge) before midnight Iran time counts for that day.
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
- From a friend's profile → Challenge → confirm the Classic challenge.
- Record created with `expires_at = NOW() + 24h`. On accept: private match room (bypasses matchmaking queue). On decline/expiry: challenger notified. `ExpireOldChallenges` runs every 5 minutes. Accepting creates the private room immediately; any room still `waiting` for its second player after `config.RoomWaitTimeoutSec` (120s) is cancelled (`match_cancelled`, reason `opponent_unavailable`, no coins charged) and removed, so an offline/absent challenger never leaves the accepter waiting forever. **Challenger side:** the app-wide `ChallengeWatcher` (`core/services/challenge_watcher.dart`, started in `main()`) polls `GET /challenges/joinable` every 2s while the app is foregrounded and signed in, and pushes `/game` into the room from any screen (skipped when already on `/game`). It replaced the per-screen pollers in `FriendsCubit`/`LobbyScreen`. Push-based delivery is still unwired. While a multiplayer room waits for the second player, `GameScreen` shows `_WaitingForOpponent` (opponent name from `GameRouteArgs.opponentName`, spinner, countdown from `GameConstants.roomWaitTimeoutSec`, cancel button); `/challenges/joinable` rows include `challenged_username`. The challenge stays valid for the full 24h regardless of the sender's presence.

### Daily Challenge share card
```
WordChain Daily #[N]
Score: [score] | Chain: [chain_length] words
[word1] → [word2] → ... → [last_word]
Play at wordchain.app
```
Day N = days since `GAME_EPOCH_DATE`, 1-indexed. Each day's `daily_challenges` row (seed + start letter) is auto-generated by a scheduler job (every 5 min it makes sure today's and tomorrow's rows exist; the start letter comes from `engine/daily_letter.go`). `share_service.dart` → `shareDaily(DailyChallengeResult)` → `Share.share()`.

---

## 🔔 Push Notifications

All sent via FCM HTTP v1 API. Tokens registered at login, deregistered at logout.

**Push text is Persian** (server-composed title/body; numbers via `faNum` in `service/notification.go`). The table below lists the triggers in English for reference only — the actual strings live at each `SendToUser`/`SendToAll` call site. The foreground toast (`main.dart`) shows the push title+body as-is, so any new push must be written in Persian.

| Trigger | Message |
|---|---|
| Daily Challenge available (midnight Iran time) | "Today's Word Chain challenge is ready." |
| Streak at risk (20:00 local, streak ≥ 3) | "Your [N]-day streak is at risk!" |
| Streak milestone | "[N]-day streak! You've earned [coins] coins." |
| Friend request | "[Username] wants to be your friend." |
| Friend challenge received | "[Username] challenged you to a [Mode] match!" |
| Friend challenge response | Accepted / declined / expired message |
| Match found | "Opponent found! Your match is ready." |
| Weekly leaderboard reward | "You finished #[rank] and earned [coins] coins!" |

**Backend**: `internal/service/notification.go` — `SendToUser(userID, title, body)`.
**Scheduler** (1-min ticker): midnight daily challenge push · every-minute streak-at-risk check · every-5-min challenge expiry · Saturday 00:00 weekly reset (end of Friday).
**Flutter**: `notification_service.dart` — FCM permission request, token registration, foreground banners, payload stream for deep-link routing (`/daily`, `/friends`).

---

## 🎓 Tutorial

**Removed — no tutorial.** Product decision (Phase 17): the first-time tutorial was dropped. `tutorial_screen.dart`, the `/tutorial` route, the `tutorial_completed` first-launch redirect, and Profile → Help "replay tutorial" were deleted in `fa5811d`. Do not rebuild it.

---

## 🏆 Leaderboard & Weekly Reset

- Redis Sorted Set `leaderboard:global:weekly` — score added at end of **multiplayer and Daily Challenge games only** (not solo).
- **All-time board («همیشه»):** `GET /leaderboard?type=alltime` ranks `player_stats.total_score` (lifetime, never reset; DB-backed, AI user excluded). `LeaderboardService.AddScore` increments it together with the weekly Redis score, so it counts exactly the games the weekly board counts (currently multiplayer only — Daily Challenge scores are not added to either). Counts only from migration 008 onward; no backfill.
- `GET /leaderboard?type=friends` fetches friend IDs, retrieves scores via `ZSCORE` from the same set.

**Weekly reset (Saturday 00:00 Iran time = end of Friday, the Iranian week):**
1. Query top 3 → insert `weekly_leaderboard_rewards` (idempotent)
2. Award coins: 1st →500, 2nd →300, 3rd →100
3. Send push notifications to rewarded users
4. Delete Redis key

---

## 🧪 Testing Strategy

Tests written **inside the phase that introduces the code**.

**Backend (Go):** Unit tests for `engine/`, `service/`, `scheduler/`. Repository tests use real Postgres container (`testcontainers-go`). Handler tests use `httptest` with stubbed service. WS tests use `httptest.Server` with real client. Target ≥ 70% coverage on `engine/` and `service/`.

**Flutter:** Widget tests for each screen's primary states. Bloc/Cubit tests via `bloc_test`. Golden tests for `WordChainList` and `TimerBar`. Mock `DictionaryService`, `WebSocketService`, `NotificationService` — do not load the real wordlist.


---

## 🔁 Session Workflow

1. Read **CLAUDE.md** (specs, rules)
2. State the phase: *"Implement Phase N — [title]"*
3. Update the CLAUDE.md status table
4. Commit before starting the next phase

---

## 🛠️ Developer Commands & Environment

```bash
# Backend (run from backend/)
go run ./cmd/server                 # start (reads backend/.env — not the repo root)
go test ./internal/...              # all tests
docker-compose up                   # app + postgres:16 + redis:7

# Flutter (run from client/)
flutter run --dart-define-from-file=tapsell.json   # ad zone ids; see note below
dart run build_runner build         # regenerate Drift .g.dart files (gitignored)
flutter analyze
flutter test
```

- **Production host (`root@185.110.191.158`, Ubuntu, 2 GB RAM, shares the box with the unrelated `hamketab` site):** backend lives in `/opt/wordchain` as its own compose project `wordchain` (own Postgres 16 + Redis 7, no host ports published; `.env` there holds the generated `DB_PASSWORD`/`JWT_SECRET`; `secrets/fcm-service-account.json` is mounted). The app binds `127.0.0.1:18080`; nginx (`/etc/nginx/conf.d/wordchain.conf`) exposes it publicly on **`http://185.110.191.158:8080`** (WebSocket upgrade enabled) — the port-80 hamketab config is untouched. No TLS/domain yet. Redeploy: `bash scripts/deploy_backend.sh` (`--dry-run` to preview, `--logs` to tail afterwards; go build → rsync → compose rebuild → `/health` poll), which wraps `rsync -a --exclude /server --exclude /.env --exclude 'docker-compose*.yml' --exclude '*.md' backend/ root@185.110.191.158:/opt/wordchain/` then `ssh root@… 'cd /opt/wordchain && docker compose up -d --build app'`. **Client:** `DioClient.baseUrl` defaults to that URL (`--dart-define=API_BASE_URL=http://10.0.2.2:8080` for a local backend); Android main manifest allows cleartext + INTERNET until TLS exists. Prod compose file is server-only (differs from the dev `docker-compose.yml`).
- Migrations are embedded via `io/fs` (`backend/migrations/embed.go`) and auto-run at server startup. Current set: `001_init`, `002_friend_challenge_room`, `003_phone_auth_referral` (drops email/password, adds phone/OTP/referral columns), `004_ai_system_user`, `005_daily_retries`, `006_referral_rewards` (superseded by `007_inbox_rewards`), `008_total_score` (adds `player_stats.total_score` for the all-time board), `009_xp` (adds `player_stats.xp` for profile levels), `010_premium_perks` (adds `users.premium_until` + `users.avatar_id`).
- **Ads (Tapsell Mediation, Android only):** the app key is a manifest placeholder in `client/android/app/build.gradle.kts`; the zone id is compile-time `--dart-define`s read in `core/services/ad_service.dart` (`AdZones`). Copy `client/tapsell.example.json` to `client/tapsell.json` (gitignored), fill in the rewarded zone id, and pass `--dart-define-from-file=tapsell.json` to `flutter run`/`build`. An empty id silently disables ads. Policy: only player-initiated rewarded ads — no interstitials and no banners (the Tapsell banner is a native overlay that leaked across screens and covered `ZBottomNav`; removed).

---

## 🚧 Open Issues & Follow-ups

Tracked in detail in REDESIGN_PLAN.md; listed here so they aren't lost. 

**Phase 17 placeholders (canvas UI rendered, no backend yet — never fake client-side):**
- **Best-of-5 rounds** (ZVersus) — the static «دست ۱ از ۵» indicator was removed (it was a placeholder with no backend); needs new WS round events + server round state + match-level winner rule before re-adding.
- **Multiplayer lives** — not built (see Lives).
- **Badges** (ZProfile) — not built; the card is commented out, no schema fields.
- **Levels** (ZProfile) — implemented: `player_stats.xp` is credited with each game's score at game end (`GameService.AddXP`: solo/AI/daily via `CreateSoloGame`, multiplayer via `ws.Room` `XPSvc`). Curve in `config.XPForLevel`/`LevelFromXP` (step to level L+1 = 1000×L); `GET /profile/stats` returns `xp`, `level`, `xp_in_level`, `xp_for_next`. Level titles live in `GameConstants.levelTitles`. Counts from migration 009 onward (no backfill); guests have no level.
- **Typing indicator** (ZVersus) — not built; needs a new WS event.
- **Long-word bonus in Go scorer** — Flutter-only today.

**Known bugs / gaps (pre-existing, flagged not fixed):**
- **Longest word is the player's own words only.** vs-AI chains are shared, so `longestOwnWord` (`core/services/ai_opponent.dart`; player = even indices) feeds local stats and `SyncService` uploads it as `longest_word` on `POST /game/solo`; the server honours it only if it appears in `word_chain` (older clients fall back to the whole chain). Values stored before this fix (an AI word) are never lowered — `player_stats.longest_word` / local `LocalPlayerStats.longestWord` only grow; reset by hand if needed.
- `test/core/widgets/shared_widgets_golden_test.dart` (light + dark) fails on a clean checkout too (1.05% pixel diff) — verified with `AvatarTile` reverted to HEAD; unrelated to Phase 22.
- **Fixed:** the iOS-simulator blank white screen. Cause: `NotificationService.init()` awaited `FirebaseMessaging.getInitialMessage()` before `runApp`; without `GoogleService-Info.plist`/APNs it never completes (hangs, doesn't throw, so the `try/catch` didn't help). Now `main.dart` runs Firebase setup in the background (`_initFirebase()`, unawaited, after `runApp`) and `getInitialMessage()` has a 3s timeout. Rule: Firebase/push calls must never gate the first frame. Push itself still doesn't work on iOS until `GoogleService-Info.plist` + an APNs key are added.
- ZProfile's «صدا و لرزش» and «یادآور چالش روزانه» rows are cosmetic (no setting persisted, no reminder scheduled).
- Kavenegar SMS delivery unverified end-to-end (no account yet; dev bypass OTP `1111`).
- **FCM setup (done client-side, Firebase project `zanjir-269aa`):** `main.dart` initialises Firebase with `DefaultFirebaseOptions` and, while a user is signed in, registers the token (`NotificationService.registerToken`, also on token refresh). The OS permission is **not** asked at launch: the first time a signed-in user taps the Friends tab, `maybeAskNotificationPermission` (`core/widgets/notification_permission_dialog.dart`) shows an explainer dialog once (flag in `shared_preferences`) and requests permission only if they accept; `AuthCubit.logout` deregisters it first. Foreground pushes show as a SnackBar (`foregroundStream`). **Server delivery needs the service-account key:** download it from Firebase console → Project settings → Service accounts → Generate new private key and save it as `backend/secrets/fcm-service-account.json` (gitignored, mounted at `/secrets`), then `docker compose up -d --build app`. Until then sends are logged no-ops. **Dev caveat:** in Iran the Docker container can't reach Google (only the host does, via Nekoray), so FCM sends time out from the container; fine from a foreign server. Pushes carry no `data.route` yet, so tapping one just opens the app; iOS also needs `GoogleService-Info.plist` + APNs key (not done).

---

## ⚠️ Important Notes for Claude Code

- **After any backend change, rebuild and restart the backend** (it runs in Docker: `cd backend && docker compose up -d --build app`) and **always update CLAUDE.md** .

- **Read REDESIGN_PLAN.md too while Phase 17 is in progress.** Record each stage's outcome, decisions, and flagged issues there.
- **Verify on-device.** Phase 17 found multiple bugs that only a live run exposed (Stage 4 multiplayer was non-functional end-to-end despite passing analysis). Don't mark a stage complete from `flutter analyze`/tests alone.
- **Never implement outside the current phase's scope.** Flag missing items from prior phases without silently fixing them.
- **Always check previous phases' output** before writing code that depends on it (verify actual method signatures).
- **Dictionary is dual:** `fa.txt` lives in both `backend/internal/engine/data/` and `client/assets/words/`. Keep them byte-identical.
- **Persian text is multi-byte.** Never index or measure a Persian string by bytes in Go (`w[0]`, `w[len(w)-1]`, `len(w)`). Use `engine.LastLetter`/`firstLetter` and `utf8.RuneCountInString`. Four separate byte-vs-rune bugs have been fixed so far (WS next letter, scorer, AI word picker, longest word).
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
| `KAVENEGAR_API_KEY` | no | (Kavenegar panel API key) | OTP SMS delivery. Empty = dev no-op (logs instead of sending) |
| `KAVENEGAR_OTP_TEMPLATE` | no | `wordchain-otp` | Verify Lookup API template name, provisioned in the Kavenegar panel |
| `OTP_CODE_TTL` | no | `2m` | OTP code expiry |
| `OTP_RESEND_COOLDOWN` | no | `120s` | Minimum time between OTP sends to the same phone |

---

## 📎 Appendix: Dictionary & Word Frequency List

**Persian dictionary (`fa.txt`)** — the only word data in the project. 21,527 words, one word per line, no spaces, no teh marbuta (ة) or diacritics. Stored at `backend/internal/engine/data/fa.txt` and `client/assets/words/fa.txt` (byte-identical). History: 162,626 (noisy) → 17,414 in commit `2758a1c` → 17,321 → 21,527 on 2026-10-09.

**Decision (2026-10-09): the 21,527-word list is final; do not restore the 162k list.** It is the 17.3k curated list plus 4,205 words that passed *all* of: present in the Hunspell `fa` dictionary (or Wiktionary lemma) **and** OpenSubtitles frequency ≥ 30, not a verb conjugation/plural/colloquial spelling, then a manual review of every candidate. Policy: countries/cities/historic figures in, foreign first names out; infinitives and bare past forms («رفت») in, personal conjugations and imperatives out; no words ending in ء. The 3,750 words rejected in that review are kept in `output/dictionary/rejected_words.txt` (untracked) so a future rebuild does not re-add them; the added words are visible in `git diff` of `fa.txt`. Source licenses (Hunspell fa, Wiktionary, OpenSubtitles) were **not** checked — verify before commercial release. Trap letters stay ژ ظ ث ذ ض (still the five rarest starts: 33–69 words).

The English `word_freq_ranks.txt` and `engine/frequency.go` were deleted — there is no English data left in the project.
