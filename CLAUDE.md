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
| 23 | Admin Panel (web, RTL Persian) | [ ] In Progress — A1 (backend auth/sessions/roles/audit) complete; A2 (frontend scaffold/shell/login/embedding) complete; A3 (dashboard) complete; A4 (users & economy, ban) complete; A5 (content & catalogue) complete; A6–A7 not started; the «پیشنهاد کلمات» page (`/admin/content/words`) belongs to Phase 24, see § Word Suggestions; A8 (product analytics — self-hosted behaviour events + retention, see § Product Analytics) complete in code, client side **not yet verified on-device**. Plan and per-stage status in **ADMIN_PLAN.md** (stages A1–A8, one per session) |
| 24 | Word Suggestions & Dictionary Delta | [ ] In Progress — **24a complete** (backend + admin panel «پیشنهاد کلمات», verified live locally, **deployed to prod 2026-10-27** (together with the legal pages; migration 015 applied)); **24b complete in code** (Flutter: dictionary delta, report/flag/suggest UI, «پیشنهادهای من», reward face) — unit/widget-tested, **not yet verified on a device**. See § Word Suggestions (Phase 24) |

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
| Local DB (Flutter) | Drift 2 — type-safe SQLite ORM; tables: `local_matches`, `local_used_words`, `local_player_stats`, `local_powerup_cache`, `local_analytics_events` (schema v2) |

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
- Screen files: `ZHome`, `ZSolo`, `ZPlay`, `ZOver`, `ZLobby`, `ZVersus`, `ZDailyBefore`, `ZDailyAfter`, `ZBoard`, `ZProfile`, `ZFriends`, `ZPhone`, `ZOtp`, `ZSplash`; `Zanjir.dc.html` holds the token sheet.
- The PNGs in `figma/` are the **legacy** Phase 1–16 references, superseded by the canvas for any screen it covers.

Do not invent layouts — if a screen is covered by a design file, follow it. If a detail is ambiguous, match the overall visual style and spacing of the nearest reference. Screens with no canvas design (e.g. the friend challenge sheet) are derived from the token system (REDESIGN_PLAN.md Stage 6). `ZOverScreen` is the single game-over/continue screen for solo, vs-AI and multiplayer.

### Visual system rules (Phase 17)
- **A screen never names a hex value.** Read colors from the `ZColors` theme extension via `context.z.<token>` (`core/theme/app_tokens.dart`). Light/dark are the same widgets with different token values. Any `Color(0x…)` in a screen file is a bug.
- The legacy `AppColors` palette is **removed**; `AppTheme.light`/`dark` are both built from `ZColors`. `test/core/theme/token_coverage_test.dart` fails the build on hardcoded colours.
- Typeface: Vazirmatn (vendored in `assets/fonts/`). Spacing/radii/elevation/motion come from `core/theme/app_spacing.dart`, `app_elevation.dart`, `app_motion.dart`.
- **Zero-blur elevation**: solid offset edges only (`solidEdge(...)`); pressed state removes the offset and translates Y +3.
- **Persian digits everywhere** (۰۱۲…, thousands separator «٬») via `core/utils/persian_digits.dart`. Dates use Jalali (`shamsi_date`).
- **RTL-native**: use `EdgeInsetsDirectional`, `start`/`end` alignment — never `left`/`right`.
- Reuse the shared widgets in `core/widgets/` (`LetterTile`, `SolidCard`, `AccentButton`/`NeutralButton`, `CoinPill`, `TintChip`, `AvatarTile`, `ZAccentDisc` (the 52dp accent square of prize / message cards), `SectionHeader`, `StreakStrip`, `ZBottomNav`; state blocks `ZEmptyState` / `ZLoadState` (loading + failed load, `core/widgets/z_empty_state.dart`, `z_load_state.dart`) inside a `ZStateCard` (`z_state_card.dart`, the surface card on the sky scene); `ZInviteButton` (the amber «دعوت به بازی» of the lobby and Friends tab)).
- Game-feel pieces also shared from `core/widgets/`: `ChunkyBox`/`ChunkyPressable`/`ZChunkPill`, `ZMascot`, `ZDiscAvatar`, `ZHudCoinPill` (HUD coin balance), `ZStrokedText` (outlined sticker titles), `ZRaysPainter`; the active-game frame lives in `features/game/view/widgets/` (`ZGameScaffold`, `ZGameHud`, `ZOver*` for the result screen).
- **Toasts:** `ZToast.show(context, title, {message, amount, kind, duration, actionLabel, onAction})` (`core/widgets/z_toast.dart`, canvas 16a/16b): chunky card floating 52dp below the safe area, glossy kind badge (success / error / info / coin), draining bar, ✕ to dismiss, 4 s default, one at a time; an optional `actionLabel`/`onAction` adds a teal ✓ icon beside the ✕ (`actionLabel` is its screen-reader label; runs the callback, then dismisses). Never `SnackBar`.
- **Dialogs:** every non-screen modal goes through `showZDialog` + `ZDialogCard` + `ZDialogButton` (`core/widgets/z_dialog.dart`; `scrim` token backdrop, drop-in entrance). The exit-confirm is one `ZExitConfirm` with a mode (solo / ai / online / daily) whose copy states what leaving really does — never copy a canvas claim the product doesn't back (`features/game/view/widgets/z_exit_confirm.dart`). The vs-AI level picker is `showAiLevelDialog` (`features/home/view/widgets/home_level_dialog.dart`). `ZRibbonTitle` (`core/widgets/z_ribbon_title.dart`) is the swallow-tail screen title (first used by ZLobby); `ZMascot` (`core/widgets/z_mascot.dart`) is the one mascot drawing everywhere: 5 standing moods plus `ZMascotMood.hanging`, the Home pose (raised hand on the chain, waving arm, kicking leg; canvas `ZHome3A` frame 7a). There is no separate home mascot.
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
4. In multiplayer, the opponent sees "Opponent deciding…" with a **15-second countdown** — the canvas `ZOppDeciding` dialog (`ZOppDecidingOverlay`, `features/game/view/widgets/z_opp_deciding.dart`, fed by `GameActive.opponentContinueWindowRemaining` / `opponentLossReason`). If it expires, the loss stands.
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

**Game:** `POST /game/solo` · `GET /game/:id` · `GET /profile/stats` · `PATCH /profile/username` (3–20 letters/digits/`_`; `400 invalid_username`, `409 username_taken`) · `GET /profile/perks` (`is_premium`, `premium_until`, `avatar_id`) · `PATCH /profile/avatar` (premium only; `403 premium_required`, `400 invalid_avatar`) · `GET /perks/catalog` · `GET /avatars/:id/image` (public; admin write routes under `/admin`, see § Premium Perks) · `GET /powerup/inventory` · `POST /powerup/use`

**Matchmaking:** `POST /match/queue` · `DELETE /match/queue`

**Leaderboard:** `GET /leaderboard?type=global&limit=100` · `GET /leaderboard?type=alltime&limit=100` · `GET /leaderboard?type=friends&limit=100`

**Daily Challenge:** `GET /daily` · `GET /daily/leaderboard` · `POST /daily/retry`

**Friends:** `POST /friends/request` · `GET /friends` · `GET /friends/requests` · `POST /friends/respond` · `DELETE /friends/:friendId`

**Friend Challenges:** `POST /challenges` · `POST /challenges/:id/respond` · `GET /challenges/pending` · `GET /challenges/joinable` (challenger's accepted challenges whose room still awaits them)

**Push Notifications:** `POST /notifications/token` · `DELETE /notifications/token`

**Analytics (public, guests included):** `POST /analytics/events` — see § Product Analytics.

**Public web pages (outside `/api/v1`, no login):** `GET /terms` · `GET /privacy` · `GET /legal/assets/:name` (fonts + font licence) — see § Legal Pages.

**Word suggestions (Phase 24):** `POST /words/suggestions` (public, optional Bearer) · `GET /words/suggestions/mine` (auth) · `GET /dictionary/delta?since=N` (public) — see § Word Suggestions.

---

## 🌐 WebSocket Event Protocol

```
Client → Server:
  { "type": "submit_word",  "word": "apple" }
  { "type": "use_powerup",  "powerup": "freeze" }
  { "type": "continue",     "method": "ad" | "coins" | "forfeit" }   ← must arrive within 15s of loss_event; `forfeit` (the loser declines) ends the game at once for the opponent, broadcasting `continue_decision` forfeit then `game_over`
  { "type": "forfeit" }                                   ← leave the match: while active or in a continue window the opponent wins immediately (`game_over` with winner/scores/payout; entry fee settled once). No-op in any other state, from spectators/stale connections, and when repeated or racing a timeout/disconnect (`Room.forfeit`/`resolveGame` are idempotent). Sent by the client when the player taps «تسلیم و خروج» (`GameBloc._onGameEnded`, multiplayer only)
  { "type": "send_taunt",   "taunt": "hurry_up" }         ← premium only; ID from the `taunts` table
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
  { "type": "taunt",                "player_id": "...", "taunt": "hurry_up", "text": "..." }  ← sent to both players
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

Screens: `ZLoginScreen` (`/login`, phone entry) and `ZOtpVerifyScreen` (`/login/otp`, 4-box OTP driven by the phone's own number keyboard via a hidden TextField) in `features/auth/view/`. The old email/password `login_screen.dart`/`register_screen.dart` and `/register` route are gone. A dev/test bypass code `1111` exists while no Kavenegar account is purchased; real SMS delivery is still unverified end-to-end. Both screens follow the «A · mascot-led» canvas (REDESIGN_PLAN.md § ZLogin / ZOtp): screen-scoped `PhoneEntryCubit` / `OtpFlowCubit` (the resend countdown and the code-expiry notice are computed from stored deadlines with an injectable clock, not a decremented counter), no terms checkbox (the sentence only; its two nouns «قوانین» and «حریم خصوصی» are inline links to the public pages, see § Legal Pages), no carrier / voice-call / SMS-auto-read claims (nothing backs them). **The `return=` target is applied by the router** — `authRedirect` in `core/router/app_router.dart` sends a signed-in player on `/login` or `/login/otp` to `return=` (or the OTP args' `returnPath`), else Home, and sends `/login/otp` without its args back to `/login`. A new account's gift is the server's: +50 welcome, +100 more with a resolved referral code (`GameConstants.welcomeBonusCoins` / `referralSignupCoins`); a code given for an existing number is ignored by the server.

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

All of the launch box above (dictionary, DI, `AuthCubit.init()` incl. the refresh call) runs in `main()` **before** `runApp`; `SplashScreen` (`/splash`, initial location, 3.2 s intro from the ZSplash canvas) waits for nothing and then goes to `/home` for guests and signed-in players alike — only while it is still the router's location. Slow/failed init therefore has no UI yet (todo.md § 3).

`AuthCubit` must expose an `isGuest` flag. Only multiplayer queue and leaderboard write path force a login redirect.

---

## 🔗 Referral Code System

Every user gets a unique 6-char alphanumeric `referral_code` (charset excludes ambiguous `0/O/1/I`), assigned when signup completes (first successful `verify-otp`, not at row creation). Two entry points, both landing on the same server-side link/reward logic:

1. **At signup** — an optional `referral_code` on `POST /auth/verify-otp` for a phone verifying for the first time. If it resolves, `referred_by` is linked and the **new** user gets **+100 coins**. An unresolvable code never blocks signup — it comes back as a soft `referral_warning: "referral_not_found"` field on the 200 response, not an error.
2. **Post-login** — `POST /referral/redeem` (protected), for an existing account that hasn't linked a referrer yet. One-time only (`referred_by IS NULL` check, atomic) — `409 referral_already_used` on a second attempt. Awards **+50 coins**.

Self-referral (code equals the caller's own) is rejected (`400 self_referral`) — structurally impossible at signup since the new code doesn't exist yet, checked explicitly for the post-login path.

**Renaming:** ZProfile's pencil icon (signed-in only) opens `EditUsernameDialog` (`showEditUsernameDialog`, `features/auth/view/widgets/edit_username_dialog.dart`, canvas ZDialogs 14b) → `PATCH /profile/username` (`AuthService.UpdateUsername`). The JWT keeps the old username in its claims until refresh; nothing authoritative reads it.

**Sharing your own code:** ZProfile's `ProfileInviteCard` (`features/profile/view/widgets/profile_invite_card.dart`, fed by `InviteCodeCubit`) loads it via `GET /referral/me` and shares a short Persian invite text + code through `ShareService.shareInvite` (system share sheet → social apps/SMS).

**Inviter reward (+50 coins, `config.CoinReferralInviter`):** whenever a referral is linked (either entry point) an unclaimed `inbox_rewards` row is created for the referrer.

Client: both entry points are served by one shared widget, `ReferralDialog` (`showReferralDialog`, `client/lib/features/auth/view/widgets/referral_dialog.dart`, canvas ZDialogs 14a), which branches on `AuthCubit`'s state (authenticated → redeem directly; not yet authenticated → stash the code and forward it into `verify-otp`). Triggered from the ZLogin phone screen's referral teaser card (entry point a) and from ZProfile's «کد دعوت داری؟» button (entry point b) — the latter is a deliberate small addition beyond the two named screens (ZLobby has no referral row any more — it was removed 2026-10-03 and is not in the "A" canvas).

---

## 🎁 Prize Rewards & Messages

**Time zone:** all server day boundaries (Daily Challenge day, streak days, daily-login, prize payouts, scheduler) use Iran time, fixed UTC+3:30 (`config.IranLocation`/`config.IranDate`; no DST since 2022). Client countdowns use `core/utils/iran_time.dart`.

Every claimable prize is a row in `inbox_rewards` (migration `007`; `kind` = `referral_reward` · `streak` · `weekly_rank` · `daily_login` · `daily_done` · `daily_rank` · `admin_gift` (granted from the admin panel) · `word_suggestion` (approved missing-word report, Phase 24), unique per `(user_id, kind, ref)` so awards are idempotent). Coins are credited only by `POST /rewards/:id/claim` (atomic, once). The home gift icon (`features/rewards/`, route `/rewards`) shows a badge with the unclaimed count; claimed rewards disappear from the list `config.RewardClaimedRetention` (24h) after claiming; `GET /rewards` also returns the live server coin balance, which the client uses to overwrite its stale local balance. Streak milestones, weekly top-3 rewards and referrals also send an FCM push (no-op while FCM is unconfigured). **Daily login +10** is created lazily on the first `GET /rewards` of each UTC day. **Daily Challenge prizes** (`DailyService.RunDailyPayout`, scheduler checks every 5 min for the day that just ended at Iran midnight, Redis flag `payout:daily:<date>`): every finisher gets +10 (`daily_done`), the top 3 an extra +100/+60/+30 (`daily_rank`, ties share a rank). Today's ranking is `GET /daily/leaderboard` (ZDailyAfter/Before «جدول امروز» → `/daily/board`). **Welcome bonus +50** (`config.CoinWelcome`) is credited directly at signup, on top of any referral bonus.

**Messages («اعلان‌ها», `features/messages/`, route `/messages`; rebuilt from the `ZNotifs` canvas 2026-10-26, REDESIGN_PLAN.md § ZNotifs):** actionable invitations only — pending friend requests (`GET /friends/requests`) and friend challenges (`GET /challenges/pending`, now includes `challenger_username`), one card each with a teal accept and a neutral «رد», reusing the friends endpoints; accepting a challenge enters the room. The Friends tab badge is the combined count (`MessagesCubit`; its state has `loaded`/`error` like `RewardsState`). The canvas's tabs, read state, day groups and times are omitted — nothing backs them. No new backend store; announcements would be a later addition. Entry point: the **bell** in Home's top bar (canvas `ZHome3A`, frame 7a) with a coral count badge (`MessagesCubit.count`, hidden at 0, «۹۹+» cap); a guest tapping it goes to `/login?return=/messages`. **Pushes during a game:** a foreground push that arrives while the router is on `/game` is never shown as a toast (the app-level `SnackBar` covered the board; any toast already showing is also cleared when `/game` opens). `main.dart` hands it to `MessagesCubit.addMissed(title, body)` instead: it counts toward the bell badge and appears on `/messages` as a `MissedPushTile` with a «باشه» dismiss (session-only, in memory; a sign-in is required).

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

- **State:** `users.premium_until` (TIMESTAMPTZ, migration `010_premium_perks`) — premium ⇔ `premium_until > now()`. It is set **server-side only**; no client endpoint can grant it. **Real billing (Cafe Bazaar / Myket / gateway receipt verification) is not built**: until it is, grant premium from the admin panel (Users → user detail → premium grant/revoke; extends any remaining time). Manual coin top-ups: the same page (coins ±, or a claimable `admin_gift` reward). The old `grant_premium.sh` / `grant_coins.sh` SSH scripts were deleted (2026-10-27). `MockMonetizationService.purchase('premium_monthly')` still just returns success without granting anything — misleading, flagged, not fixed.
- **Catalogues are server-managed (add/remove with no app release).** Taunts live in the `taunts` table (`id`, Persian `text`, `sort_order`), avatars in `avatars` (`id`, image `BYTEA`, `content_type`, `sort_order`). Nothing is compiled into the server or bundled in the APK (the 16 avatar PNGs were removed from `client/assets/`; the originals are kept as seed data in `scripts/seed/avatars/`). `service.CatalogService` serves reads from a 30 s in-memory copy that admin writes invalidate. **Public:** `GET /perks/catalog` (`{taunts:[{id,text}], avatars:[{id}]}`, picker order) and `GET /avatars/:id/image` (ETag + `max-age=86400`, so a replaced image reaches clients within a day). **Admin** (header `X-Admin-Key` = `ADMIN_API_KEY`; unset ⇒ routes 404): `PUT /admin/taunts/:id` `{text, sort_order?}` (add or edit), `DELETE /admin/taunts/:id`, `PUT /admin/avatars/:id` (multipart `image` PNG/JPEG/WebP ≤ `config.AvatarMaxBytes` 256 KB, sniffed from the bytes; optional `sort_order`), `DELETE /admin/avatars/:id` (also clears it from every user who picked it). Ids: lowercase `[a-z][a-z0-9_]`, taunt ≤ 32 / avatar ≤ 24 chars; taunt text ≤ `config.TauntMaxTextRunes` (60). **Use `bash scripts/perks_admin.sh list | taunt add|rm | avatar add|rm | seed`** — it runs curl on the production host over SSH against `127.0.0.1:18080` and reads `ADMIN_API_KEY` from `/opt/wordchain/.env` there (the key never crosses the network; `WORDCHAIN_API=… ADMIN_API_KEY=…` targets a local backend instead). The admin panel (Phase 23, A5) manages the same catalogues from `/admin` (reorder, uploads with usage counts; sessions must give a reason — the key script need not). **Prod:** `ADMIN_API_KEY` is set in `/opt/wordchain/.env` and the 16 seed avatars were uploaded (2026-10-11). nginx also exposes `/api/v1/admin/*` publicly — key/session-protected, but keep using the SSH script for key access. Client: `core/services/perks_catalog_service.dart` (`PerksCatalogService.cached` / `.refresh()`, last good copy in `shared_preferences`, never throws) feeds the taunt sheet and avatar picker; `AvatarTile` loads `GET /avatars/:id/image` with `Image.network` and keeps the initial as placeholder/error fallback (no disk image cache yet — `cached_network_image` would add one). Removing an avatar or taunt takes effect immediately for new picks; clients with a stale list just fail to load the image (initial shown) or the server ignores the taunt id.
- **Taunts (1v1 multiplayer):** premium players *send* preset messages, everyone *receives* them (the free-user exposure is the upsell). Client sends `send_taunt {taunt: id}`; `Room.processTaunt` ignores IDs missing from the catalogue (`TauntLookup`), re-checks the subscription on every send (`PerkLookup.GetPerks`, DB lookup outside the room lock), and enforces `config.TauntCooldownSec` (5 s) + `config.TauntMaxPerMatch` (8) per player. The broadcast `taunt` event carries `text` as well as the id, so a client with a stale catalogue still shows a newly added taunt. Preset IDs only — **never free text**. UI (`features/game/view/widgets/z_taunt_tray.dart`): chunky `ZTauntButton` beside ZVersus' input card (crown badge for premium, lock for free players), `ZTauntTray` (a `showZDialog` card; sub-line states the real cooldown/cap from `GameConstants.tauntCooldownSec/tauntMaxPerMatch`; chips locked for free players), the latest taunt is an amber pill **inside the chain** under the sender's last word (`ZVersusChain` → `ZBubbleChain(taunt:)`, 3 s, sender's side and disc; no word from the sender yet → under the newest word) driven by `GameActive.tauntId/tauntFromMe/tauntSeq`. A `taunt_rejected` reply shows a toast with the real rule. `game_start.state` sends `premium` + `avatars` for both players but **no usernames** (todo.md 1.6a), so the opponent shows as «حریف».
- **Avatars:** 16 IDs (`config.AvatarIDs`, opaque keys — the names no longer describe the art) rendered by `AvatarTile(avatarId:)` from the server-hosted image — the seed art is DiceBear **Lorelei** (by Lisa Wischofsky, **CC0 1.0**, no attribution required), seeds `zanjir-<id>`, calm-smile mouths only, pastel backgrounds; regenerate with `https://api.dicebear.com/9.x/lorelei/png?seed=zanjir-<id>&size=256&backgroundType=solid&backgroundColor=b6e3f4,c0aede,ffd5dc,ffdfbf,d1d4f9&mouth=happy01,happy02,happy03,happy04,happy05,happy06,happy13`. Swap for commissioned illustrations later with `perks_admin.sh avatar add <same id> <file>`. Picker: ZProfile → «تغییر آواتار» (premium) → `PATCH /profile/avatar`. `GetPerks` returns `avatar_id` only while premium is active, so a lapsed subscription silently falls back to the initial. Shown in ZProfile, ZVersus (via `game_start.state.avatars`), the **leaderboard** (all three tabs: `LeaderboardEntry.avatar_id` per row + `player_avatar_id` for the self row, via `LeaderboardService.attachAvatars`) and the **Friends tab** (read from the friends-leaderboard row the client already fetches for the weekly score; `GET /friends` itself carries no avatar). Not in the lobby's friend rows yet.
- **Badge:** crown icon next to the name in ZProfile and in the ZVersus score pill (`game_start.state.premium`).
- **Not built:** the 200 coins/week grant, a subscription-expiry push, the premium badge in the friends list (avatars are shown there; no premium flag is sent), the Flutter purchase flow.

---

## 🛠️ Admin Panel (Phase 23)

Web panel (React, RTL Persian, embedded in the Go binary) for operators. Plan, visual system and per-stage status/log: **ADMIN_PLAN.md** (stages A1–A7, one per session). **Stages A1 (backend), A2 (frontend scaffold, shell, login, embedding), A3 (dashboard), A4 (users & economy, ban) and A5 (content & catalogue) are done**; the remaining pages behind the nav are placeholders until A6–A7.

- **Frontend (`admin/`, A2):** React 18 + TypeScript + Vite + Tailwind v4 (+ Radix, TanStack Query, React Router, `date-fns-jalali`), RTL Persian, Estedad font. Commands (run from the repo root): `pnpm -C admin install` · `pnpm -C admin dev` (http://localhost:5173/admin/, proxies `/api` to :8080) · `pnpm -C admin typecheck && pnpm -C admin lint && pnpm -C admin test` · `pnpm -C admin build` (writes `backend/internal/adminui/dist`, clearing it first). Rules: colours only from `src/styles/tokens.css` (hex anywhere else fails `src/test/lint-rules.test.ts`), logical CSS only (no `ml-/pr-/left-/right-`), Persian digits via `lib/fa.ts`, Jalali dates in Iran time, backend error codes mapped to Persian in `lib/errors.ts`, all requests through `lib/api.ts` (cookie + `X-Requested-With` header + 401 → login). `/admin/kit` (dev server only) is a component gallery.
- **Dashboard (A3):** read-only `GET /api/v1/admin/dashboard/summary` (users total/new/premium, coins in circulation, today's matches by bucket, daily participants, unclaimed rewards, live rooms/players via `Hub.Snapshot()`, matchmaking queue length, FCM configured flag) and `GET /admin/dashboard/timeseries?days=30` (1–90; per Iran-time day: signups, matches by bucket, daily attempts, coins claimed) — any admin role; `service/admin_dashboard.go`. Match buckets are derived (solo+on-device AI / 1v1 / online AI fallback / daily); the server cannot split solo from on-device AI. Charts use **Apache ECharts** (`echarts` + `echarts-for-react`, tree-shaken in `components/charts/EChart.tsx`, colours read from the CSS tokens at runtime via `useChartColors`); the dashboard route is lazy-loaded and refreshes every 60 s.
- **Users & economy (A4):** reads for any role — `GET /api/v1/admin/users?q=&filter=premium|banned|new&sort=created|coins|xp|matches|username&order=&page=&page_size=` and `GET /admin/users/:id` (profile, stats, level progress, referrer/referred, last rewards/matches/daily attempts). Mutations need role ≥ operator, a required `reason` (3–200 chars) and write an audit row (`user.coins|premium_grant|premium_revoke|rename|avatar_clear|ban|unban`): `POST /users/:id/coins {mode: direct|reward, amount, reason}` (`direct` = atomic ± on the balance, `409 insufficient_coins` below zero; `reward` = claimable inbox reward of kind `admin_gift`), `POST /users/:id/premium {action: grant|revoke, days, reason}` (grant extends any remaining time), `PATCH /users/:id/username`, `POST /users/:id/avatar/clear`, `POST /users/:id/ban|unban`. Phones are masked (`0912*****67`) **server-side** for non-owners, who also cannot search by phone; OTP codes are never read. Code: `handler|service|repository/admin_users.go`; panel: `pages/Users.tsx`, `pages/UserDetail.tsx`, `pages/users/`, generic `components/ui/ReasonDialog.tsx` (typed confirmation for ban and premium revoke).
- **Ban (migration `013_user_ban`: `users.banned_at`, `ban_reason`):** a banned account gets `403 account_banned` on `verify-otp` (checked before the code), `refresh`, every `RequireAuth` request (one PK lookup, no cache — immediate), the WS handshake, queue join and challenge create (`ensureCanAffordEntry`). Leaderboards hide banned users (all-time in SQL; weekly/friends dropped on read — the Redis score stays so an unban restores it; the weekly payout therefore skips them). `account_banned` is in `error_messages.dart`. **Not done:** a socket already inside a room is not kicked (effective at the next API call/handshake), and `send-otp` still texts a banned phone.
- **Content & catalogue (A5):** reads for any role — `GET /api/v1/admin/taunts`, `/avatars` (uncached; with bytes/type and `users`/`active_users` per avatar plus the size/type limits), `/avatars/:id/usage`, `/daily?from=&to=` (default today-29…today+7; max 120 days, up to 60 days ahead), `/daily/:date` (stats, ranking, newest 100 attempts, payout status), `/leaderboards/weekly|alltime?limit=` (≤100; banned players hidden like in the app) and `/leaderboards/rewards?weeks=`. Mutations (role ≥ operator, audited, **panel sessions must send a `reason`**; the `X-Admin-Key` script path may omit it): the existing `PUT/DELETE /taunts|avatars/:id` (reason in the JSON body / multipart form field; avatar delete audits `users_cleared`), new `POST /taunts/reorder {ids, reason}` (every taunt exactly once, else `409 catalog_changed`) and `PATCH /daily/:date {start_letter, reason}` — **future days only** (today/past → `409 date_not_editable`, enforced in SQL too), letter must be in `engine.DailyStartLetters()` (`400 invalid_letter`); a future day the scheduler has not generated yet is created with `seed = date.Unix()` so the scheduler leaves it alone. Audit actions: `taunt.save|delete|reorder`, `avatar.save|delete`, `daily.start_letter`. Payout status is derived from the `daily_done` reward rows (`paid`/`pending`/`missed`/`not_due`/`no_players`), not just the Redis flag. Code: `handler|service|repository/admin_content.go` (+ `perks_catalog.go`); panel: `pages/Taunts.tsx`, `Avatars.tsx`, `Daily.tsx`, `DailyDetail.tsx`, `Leaderboards.tsx`, `lib/content.ts`. Taunt reordering uses `@dnd-kit` (pinned) with keyboard support and up/down buttons.
- **Embedding/serving:** the build is embedded with `//go:embed all:dist` (`backend/internal/adminui`; only `dist/.gitkeep` is committed) and served by `handler.AdminUIHandler` at `/admin` and `/admin/*` with SPA fallback, immutable caching for `assets/`, strict CSP, `X-Frame-Options: DENY`; it 404s like the API when no admin/key exists and obeys `ADMIN_IP_ALLOWLIST`; without a build it answers 503 "panel not built". **A backend rebuild is needed after every panel build** (`pnpm -C admin build && cd backend && docker compose up -d --build app`). `scripts/deploy_backend.sh` builds the panel (`pnpm -C admin install --frozen-lockfile && build`) before building the image, so Node/pnpm and Docker must be available on the deploy machine. **Public URL: `https://amirabbasataei.ir/admin/`**. The panel is always served at `/admin/` on the backend's own origin — the short-lived `/zanjir` prefix (`PANEL_PREFIX`, `lib/base.ts`) was removed when Zanjir took over the whole domain.
- **Accounts:** `admin_users` (migration `012_admin`: username, bcrypt hash cost 12, `role` ∈ `owner|operator|viewer`, `totp_secret` (unused until A7), `disabled_at`, `last_login_at`). Entirely separate from player `users` and player JWTs. Password 10–72 chars; username `^[a-z][a-z0-9_.-]{2,31}$`.
- **Sessions:** server-side in Redis — `admin:sess:<64-hex token>` → `{admin_id, role, created_at}`, idle TTL `ADMIN_SESSION_TTL` (2h, sliding) capped by an absolute 12h (`config.AdminSessionAbsoluteTTL`); `admin:sessions:<admin_id>` is a set of live tokens for revoke-all. Cookie `zanjir_admin`: httpOnly, `SameSite=Strict`, `Path=/`, `Secure` only when the request is TLS/`X-Forwarded-Proto: https` (there is no TLS yet). Every request re-reads the admin row, so disabling an admin or changing their role applies immediately; password change/disable also end all their sessions.
- **Auth routes:** `POST /api/v1/admin/auth/login` `{username, password}` (public; 404 while no admin exists and no key is set) · `POST /admin/auth/logout` · `GET /admin/auth/me` (`{admin:{id,username,role,last_login_at,via:"session"|"key"}}`). Login failures are deliberately indistinguishable (`401 invalid_credentials`, same bcrypt cost for unknown users). **Throttling:** failed logins counted per IP (5) and per username (10) per 15 min → `429 rate_limited` + `Retry-After`.
- **Middleware (`middleware/admin.go`):** `RequireAdmin(key, sessions)` accepts the session cookie **or** `X-Admin-Key` (actor `script`, role owner, so `scripts/perks_admin.sh` keeps working). Cookie-authenticated mutating requests (and login) must send `X-Requested-With: zanjir-admin` (`403 csrf_required`); key requests are exempt. `RequireRole(min)` → `403 insufficient_role`; `RequireAdminIP(allowlist)`. Taunt/avatar write routes now require role ≥ operator.
- **Audit:** `service.AuditService.Record(ctx, actor, action, target, payload)` writes `admin_audit_log` (actor, optional admin_id, action, target, JSONB payload, ip). Currently recorded: `auth.login`, `auth.login_failed`, `auth.login_blocked`, `auth.logout`, `taunt.save|delete`, `avatar.save|delete`, `user.*` (A4, see above). New admin mutations must record an entry.
- **Error codes** stay English (operator-only, `adminError`); the panel maps them to Persian.
- **Accounts CLI:** `cmd/adminctl` (built into the image at `/adminctl`): `create-user <username> [role]`, `set-password`, `disable`, `enable`; the password is prompted without echo (or read from stdin when not a TTY), never taken from argv. Prod: `bash scripts/admin_user.sh <username> [role]` (also `--set-password|--disable|--enable <username>`), which SSHes in and runs it via `docker compose exec`. Locally: `docker compose exec app /adminctl create-user <name> owner`.
- **Prod (2026-10-11):** deployed; first owner `amirabbas` created non-interactively (initial password was in root-only `/root/zanjir-admin-credentials.txt`, to be deleted after saving); `ADMIN_SESSION_TTL` / `ADMIN_IP_ALLOWLIST` can be set in `/opt/wordchain/.env` (already wired in `deploy/sites/wordchain/compose.yml`). nginx rate-limits `POST /api/v1/admin/auth/login` (5/min per IP) on top of the app's lockout. **HTTPS:** on since 2026-10-13; plain `http://` is redirected to https. `ClientIP()` still trusts all proxies (gin default), which is now safe in prod because nginx is the only entry and **overwrites** `X-Forwarded-For` with the real visitor IP (ArvanCloud ranges trusted via `set_real_ip_from`). A7 adds mandatory TOTP and the audit viewer.
- **Tests:** `service/admin_auth_test.go` (miniredis + `testutil.FakeAdminStore`: login, lockout, idle/absolute expiry, revocation), `middleware/admin_test.go`, `handler/admin_auth_test.go`.

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

### Result share (story image)
«اشتراک‌گذاری» (ZOver, ZDailyAfter) shares a **9:16 PNG story card** (1080×1920), not text. `ShareStoryCard` (`features/share/view/share_story_card.dart`, 360×640 grid, always the light theme, no animation/network images): wordmark, mascot (sad only when `iWon == false`), heading («برنده شدم!» / «نتیجهٔ من» / «چالش روزانهٔ N»), score, the last 4 chain words as chunky pills, and — signed-in only — a block «با کد دعوت من ثبت‌نام کن و سکهٔ هدیه بگیر» with the player's referral code (`GET /referral/me` via `AuthCubit.fetchMyReferralCode`, 4 s timeout; guests / a failed fetch get the card without the block and the line «بازی زنجیرهٔ کلمه‌ها»). **No install link** (decision 2026-10-31; no real store URL exists yet). Bottom margin 72 / top 48 keep the content clear of Instagram's story UI. `ShareImageRenderer` (`core/services/share_image_renderer.dart`) mounts the card in the root overlay off-screen, captures a `RepaintBoundary` at pixel ratio 3 and writes it to the temp dir (`path_provider`, now a direct dependency); `ShareService.shareMatch(context, …)` / `shareDaily(context, result)` then call `Share.shareXFiles` with a Persian caption that also carries the code as text (so it can be copied). If rendering fails the old text share is the fallback. `shareInvite` (Profile/Friends) is still text. Tests: `test/features/share/share_story_card_test.dart` (renders a real 1080×1920 PNG; set `SHARE_CARD_OUT=<dir>` to also write the PNGs for eyeballing). **Not verified on a device** (share sheet, fonts in the release build).
The old text share card (`WordChain Daily #N … Play at wordchain.app`) is gone. Day N = days since `GAME_EPOCH_DATE`, 1-indexed. Each day's `daily_challenges` row (seed + start letter) is auto-generated by a scheduler job (every 5 min it makes sure today's and tomorrow's rows exist; the start letter comes from `engine/daily_letter.go`). `share_service.dart` → `shareDaily(context, DailyChallengeResult)` (story card above).

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

## 📈 Product Analytics (admin stage A8)

Self-hosted behaviour events + retention, shown in the admin panel page «تحلیل رفتار» (`/admin/analytics`). **No Firebase Analytics** (user's choice; Google is unreliable from Iran) and **no ClickHouse** (the prod host is 1 vCPU / 2 GB shared) — plain Postgres: a monthly-partitioned raw table plus rollups. Moving to ClickHouse later is a copy job (append-only table, stable schema). Original plan: **ANALYTICS_PLAN.md**.

- **Identity:** `install_id` (random UUID in `shared_preferences`, key `analytics_install_id`) tracks guests, who are most players. The server stamps `user_id` from the JWT on the upload request — **never from the body** — and links the install to the account (`analytics_installs.user_id`, latest account wins, a guest batch never unlinks), so a guest's pre-signup funnel joins up with the account. A bad/expired token is treated as a guest (the request still succeeds).
- **Client** (`core/services/analytics_service.dart`): `trackEvent(AnalyticsEvent.x, {props})` (a no-op until `AnalyticsService` is in get_it, so blocs/cubits need no constructor changes in tests) writes to the Drift table `local_analytics_events` — never straight to the network, so tracking works offline, survives a kill, and costs nothing during a solo/AI game. `flush()` uploads ≤100 events per request (≤5 requests per flush) and deletes rows only after a 2xx; a `400` drops the batch (it can never succeed), anything else keeps it. Flush triggers: app background, app foreground, every 60 s **except while on `/game`**, after a game ends, after login/signup. The buffer is capped at 5 000 rows (oldest dropped). **Sessions** = one foreground stint (`session_start` on launch/resume, `session_end {duration_ms}` on background). **Screens:** `RouterScreenTracker` listens to the GoRouter delegate (this also covers the bottom-nav tabs and `go()`; a `NavigatorObserver` would miss tab switches) and records `screen_view {duration_ms}` for the screen being left; background time is not counted, and a backgrounded screen is closed and re-entered on resume (so views are slightly over-counted, durations are right). Screen names are route paths (`/home`, `/game`, …); the splash is ignored.
- **Vocabulary** (fixed enum; the server drops unknown names, so add both sides — Dart `AnalyticsEvent`, Go `service.AnalyticsEventNames`, panel `lib/analytics.ts` `EVENT_LABEL`, which a test pins): `app_open session_start session_end screen_view signup login identify game_start game_end continue_used powerup_used daily_start daily_end queue_join queue_leave match_found ad_watched purchase_tap share friend_request challenge_sent word_suggest`. Daily Challenge games emit `daily_start/end` **instead of** `game_start/end`. `game_end` props: `mode opponent result(win|loss|finished) reason words score duration_ms`. **No phone, free text or word contents in props** (privacy; the privacy page discloses analytics, § Legal Pages). No opt-out switch yet.
- **Where events fire:** `GameBloc` (`_trackGameStart` in the solo path and `_handleWsGameStart`; `_trackGameEnd` from `_saveAndEmitFinal` and `_handleWsGameOver`, guarded to once per match; continue; power-ups), `LobbyCubit` (queue/match), `AuthCubit.verifyOtp` (signup/login + identify + flush), `AdService.showRewardedAd` (only when rewarded), `ShareService`, `FriendsRepository`, ZProfile `_purchase`. A game left mid-way has a start but no end (= abandonment).
- **Ingest** (`POST /api/v1/analytics/events`, public; `handler|service|repository/analytics.go`): body `{install_id, platform, app_version, events:[{client_event_id, name, ts(ms), session_id, screen, props}]}`; ≤100 events, ≤256 KB (`config.Analytics*`), props ≤1 KB JSON object, `duration_ms` must be a number 0..24 h (else dropped from props), screen `[A-Za-z0-9_/:.-]{1,64}`. A malformed event is *counted in `rejected`*, not a batch error, so one unknown name from a newer client cannot make a queue retry forever; a bad envelope is `400 validation_error`. Response `{data:{accepted, rejected}}` — duplicates are neither. Client timestamps outside [now−7 d, now+5 min] are replaced by server time (a wrong device clock must not file events in a far-off partition). Redis rate limit: 30 requests/min per install and 600/min per IP (carriers NAT many players), failing open if Redis is down → `429 rate_limited`.
- **Storage** (migration `014_analytics`): `analytics_events` is `PARTITION BY RANGE (ts)` by month — **`ts`, not `server_ts`**, because a unique index on a partitioned table must include the partition key and `(client_event_id, ts)` is the only pair that is identical on a client retry, which is what makes ingest idempotent (`ON CONFLICT DO NOTHING`; deviation from ANALYTICS_PLAN.md). Indexes: BRIN on `ts`, `(install_id, ts)`, `(user_id, ts)`, `(name, ts)`. `analytics_installs` (install → user, Iran-date `first_seen`/`last_seen`; `first_seen` only moves earlier because offline batches arrive late). Rollups, all keyed by Iran day: `analytics_daily_active (day, install_id, user_id, events)`, `analytics_daily_counts (day, name, count, uniques)`, `analytics_daily_screens (day, screen, views, total_ms, median_ms)`, `analytics_daily_sessions (day, sessions, total_ms)`. Partitions: the migration creates last/this/next month; `main` ensures them at startup and the scheduler every 5 min (an insert with no partition fails).
- **Scheduler** (`service.AnalyticsMaintenanceService`, off the ticker goroutine, one pass at a time): every 5 min ensure partitions; every 15 min `RefreshRecent` (rebuild today's + yesterday's rollups — the panel is up to 15 min behind); once per Iran day (Redis flag `analytics:rollup:<date>`) `RunDailyPass` rebuilds the previous `config.AnalyticsRollupLookbackDays` (8) days (late offline uploads) and drops raw partitions ending before `config.AnalyticsRawRetentionMonths` (6) months ago. Rollups are kept forever. `RollupAnalyticsDay` is idempotent (delete + insert in one transaction).
- **Admin API** (any role, read-only; `handler|service|repository/admin_analytics.go`): `GET /api/v1/admin/analytics/overview?days=` (DAU/WAU/MAU, stickiness = DAU÷MAU, new installs, avg session of the last 7 days, daily series), `/retention?from=&to=&by=install|user` (cohort × D0..D30; cohort = first-seen day for installs, first signed-in active day for users; `null` = that day hasn't happened; cached 5 min in Redis), `/funnel?steps=a,b,c&days=` (2–6 steps; **raw events**, per install, each step's first occurrence at/after the previous step's), `/screens?days=` (views, average and *approximate* median — views-weighted mean of the daily medians), `/events?days=&names=` (daily counts), `/users/:id/timeline` and `/installs/:id/timeline` (`?before=&limit≤500`; the user timeline covers every linked install, so the guest history before signup is included). `days` is 1..90, a bad parameter is `400 validation_error`.
- **Panel** (`admin/src/pages/Analytics.tsx`, `analytics/Timeline.tsx`, `InstallTimeline.tsx`, `lib/analytics.ts`): tabs نمای کلی · بازگشت کاربران (heat map, blends the blue token over the surface) · قیف · صفحه‌ها · رویدادها; a «رفتار» tab on `UserDetail`; `/analytics/installs/:id` for a guest. Nav item «تحلیل رفتار».
- **Build/ops:** the uploaded `app_version` is `version+build` read via `package_info_plus` (`core/services/app_version.dart`, also shown on the splash) in `AnalyticsService.start()` (`unknown` if it cannot be read). Migration 014 is applied by the normal deploy. After the first prod deploy the panel shows data once the first 15-minute rollup has run.
- **Not built / follow-ups:** an opt-out switch in ZProfile (the privacy page says honestly that none exists — update it when one ships); `identify` is also implicit (every batch carries the JWT) so existing signed-in users link on their next upload; on-device verification of the Flutter tracker (see ADMIN_PLAN.md § A8 log); the Drift v1→v2 migration has only been compiled, not run on a real upgrade.

---

## 📝 Word Suggestions (Phase 24 — 24a and 24b built, on-device check pending)

Why: `fa.txt` (24k words) can never be complete; a valid word rejected as `not_in_dictionary` costs the player a game. Players report missing words, an admin approves them, and approved words reach **all** modes without an app release (multiplayer instantly; solo/vs-AI through a dictionary delta the app fetches). Players can also flag AI words that are unreal or inappropriate. **Decisions (2026-10-27):** reward **25 coins** per approved word (`config.CoinWordSuggestion`); **guests may report** but earn nothing; **no reward for removal reports**; sessions 24a (backend + panel) and 24b (Flutter).

- **Still do a final dictionary top-up before launch** (same policy as § Appendix: Dictionary) — the report loop covers the long tail, it does not replace curation. The curated-list decision (no 162k list) stands.

### 24a — built (backend + admin panel)
- **Migration `015_word_suggestions`:** `word_suggestions` (unique `(word, kind)`, kind `add|remove`, status `pending|approved|rejected`, `outcome` add|remove|ai_block, denormalised `reporters` count, review note/by/at); `word_suggestion_reports` (PK `(suggestion_id, reporter_key)`, key `u:<user id>` or `i:<install id>` so a player counts once; `reason` not_a_word|inappropriate for removals); `dictionary_overrides` (`word` PK, `present`, `ai_blocked`, `seq` from `dictionary_overrides_seq`) — one row per changed word holding its desired state. Suggestion ids have gaps (a repeat report's upsert burns a sequence value) — harmless.
- **Go engine (`engine/dictionary.go`):** `fa.txt` stays the immutable base map; an atomic copy-on-write **overlay** (`engine.ApplyOverrides([]Override)`) holds added/removed/ai-blocked words, so every WS move and AI turn reads lock-free and an admin approval is live immediately. `IsValid`, `SuggestWord`, `SelectAIWord` all honour it; `IsAIBlocked`, `InBase` are exported. `engine/data/rejected_words.txt` (the 3,753 words rejected in the curation reviews, copied from `output/dictionary/`) is embedded; `engine.IsKnownRejected`. Overrides are loaded at startup (`service.DictionaryService.Load`, `main.go`) — **single server instance assumed** (each instance would need to re-Load).
- **Player endpoints (public, `handler/words.go`):** `POST /words/suggestions` `{word, kind: add|remove, reason (remove only), install_id}` — Bearer token optional (valid → the account is the reporter, bad → guest; a guest must send a UUID `install_id`, the same one as analytics) → `{status:"pending", already_reported}`. Rules: ≤`WordSuggestMaxRunes` (30), Persian chars/≥3 letters (`400 invalid_word`); `add` of a word already valid → `409 word_in_dictionary`; `remove` of a word not in the dictionary → `409 word_unknown`; a known-rejected word, an already-decided suggestion, or an already AI-blocked word → `409 word_already_reviewed`; Redis daily caps per reporter (`WordSuggestPerDay` 10) and per IP (`WordSuggestPerIPPerDay` 60), Iran day, fail-open → `429 rate_limited`. `GET /words/suggestions/mine` (auth) lists the player's reports with `status`, `outcome`, `rewarded`. `GET /dictionary/delta?since=N` → `{seq, more, reset, changes:[{word, present, ai_blocked}]}` served from memory (`no-store`), ≤`DictDeltaMaxRows` per call (loop while `more`); `reset:true` = the client's seq is ahead of the server's, drop the cached delta first. Persian entries for the new `respondError` codes are already in `client/lib/core/utils/error_messages.dart`.
- **Reward:** created **inside the approval transaction** for the earliest signed-in reporter (`inbox_rewards` kind `word_suggestion`, ref = word, detail = word, `coins` 25, claimed via the normal `/rewards` flow), plus a Persian FCM push (`AdminWordService.notifyApproved`). Idempotent via the `(user, kind, ref)` unique key.
- **Admin API (`handler|service/admin_words.go`, `repository/words.go`; reads any role, writes role ≥ operator, all audited as `word.approve|reject|set|dismiss_miss`):** `GET /admin/words/suggestions?status=pending|approved|rejected|all&kind=&q=&sort=reporters|recent&page=&page_size=` (rows carry `in_dictionary`, `ai_blocked`, `known_rejected` and policy `warnings`: `suffix_of_known`, `verb_prefix`, `ends_in_hamza`; plus `pending:{add,remove}` counts), `GET /admin/words/suggestions/:id` (with reporters), `POST /admin/words/suggestions/:id/approve {outcome, note}` (removals need `outcome` `remove|ai_block`; **`remove` requires a reason**, every other note is optional but ≥3 chars when given), `POST …/:id/reject {note}`, `POST /admin/words/bulk {ids ≤100, action: approve|reject, note}` (removals cannot be approved in bulk; failures reported per id), `POST /admin/dictionary/words {word, action: add|remove|ai_block|ai_unblock, reason}` (manual edit; reason required for panel sessions, optional for the key script), `GET /admin/dictionary/lookup?word=`, `GET /admin/dictionary/export` (words to fold into `fa.txt`: added / removed / ai_blocked), `GET /admin/dictionary/misses` + `POST …/misses/dismiss`. Approving an `add` also drops the word from the misses tally.
- **Misses tally:** `ws.Room` reports every multiplayer `not_in_dictionary` rejection (word only, no user) to `service.WordMissService` (Redis zset `dict:misses`, capped at `WordMissesKeep` 5000, fire-and-forget) via `RoomDeps.WordMisses`.
- **Panel (`admin/src/pages/Words.tsx`, `pages/words/*`, `lib/words.ts`; nav «پیشنهاد کلمات», `/admin/content/words`):** tabs پیشنهاد افزودن · گزارش حذف (both mounted so the tab badges show pending counts) · ردشده‌ها در بازی · ویرایش مستقیم (lookup, edit, export). Queue: search, status and sort filters, per-row approve/reject, «انتخاب همهٔ بدون هشدار» + bulk approve/reject, link to vajehyab for each word; removal rows offer «مسدود برای AI» (ai_block) and «حذف از دیکشنری» (typed confirmation + reason).
- **Tests:** `engine/overlay_test.go`; `repository/words_test.go` (real Postgres via `TEST_DATABASE_URL`); `service/words_test.go` (submit rules, rate limit, delta, approval + push, removal outcomes, bulk, manual edits, warnings); `ws/word_miss_test.go`; `admin/src/pages/Words.test.tsx`. Verified live against the local Docker backend (guest + signed-in submit, approve → delta + reward row, ai_block, panel UI approve).
- **Deploying 24a:** `bash scripts/deploy_backend.sh` (rebuilds the panel too). Nothing needs configuring; migration 015 runs at startup. **Deployed to prod 2026-10-27** (migration 015 applied at startup; no live check of the word-suggestion endpoints was made on prod).
- **Folding into fa.txt at release:** take the panel's export, append `added` to both `fa.txt` copies (byte-identical), delete `removed` from both; `ai_blocked` words stay in the file and in the overlay.

### 24b — Flutter client (built; not verified on a device)
- **Dictionary delta (`core/services/dictionary_delta_service.dart`):** `DictionaryDeltaService.start()` (called from `main()` right after DI, before `AdService.init`) applies the cached delta (`shared_preferences` key `dictionary_delta_v1`: `{seq, changes:[{w,p,a}]}`) synchronously, then refreshes in the background (`GET /dictionary/delta?since=<seq>`, loops while `more`, ≤20 pages, honours `reset` by dropping the cache) and again on every app resume (throttled to once per 10 min, `minRefreshGap`). It never throws and never gates the first frame; offline = the last delta. `DictionaryService` gained `applyChanges(Iterable<DictionaryChange>)`, `aiBlocked` and a `DictionaryService.withWords(...)` test constructor; `selectAIWord` skips `aiBlocked` words (the player may still type them). Known edge: after a server `reset` the words applied earlier in the same run stay until the next start.
- **Reporting (`features/words/`):** `WordSuggestionsRepository` (`suggestWord`, `flagWord(word, WordFlagReason.notAWord|inappropriate)`, `mine()`; guests send the analytics `install_id`, signed-in players are attributed by the Bearer token; errors → Persian via `errorMessageFor`), `WordReportCubit` (idle/sending/sent/failed; tracks the new analytics event `word_suggest {kind, source: game_over|chain|profile}` — added to the Dart enum, Go `AnalyticsEventNames` and the panel's `EVENT_LABEL` + its pinning test), `MyWordReportsCubit`. v1 is online-only (a failed send shows the Persian reason; no offline outbox).
- **ZOver (`features/words/view/z_over_report_word.dart`, wired in `z_over_screen.dart`):** in the loss body, when the player's own word was refused as `not_in_dictionary` (`rejectedWord` set, not `'???'`, `iWon != true`), a pill ««X» درست بود؟ گزارش بده» reports it in one tap and turns into «گزارش شد؛ ممنون» + a toast (a guest is told the reward needs an account). Never offered for wrong-letter / already-used / too-short / timeout. After a game with an opponent (1v1 or vs-AI, both loss and win bodies) a link «کلمه‌ای اشتباه یا نامناسب بود؟» opens `FlagWordDialog` (pick a chain word + reason → removal report); solo has none. **`GameBloc` now keeps the server's last `word_rejected` (`_lastWsRejection`) so a multiplayer loss carries `rejectedWord`/`rejectionReason`** (before, the 1v1 subtitle showed ««» توی فرهنگ لغت نبود» with an empty word); it survives the `game_over` that follows a declined continue.
- **Lives modes (solo + Daily Challenge) — report toast (`features/words/view/missing_word_toast.dart`):** these modes keep playing after a mistake, and Daily has no result screen (`ZOverScreen` is a transitional frame that auto-navigates to `/daily`), so a word refused as `not_in_dictionary` cannot be reported from ZOver there. Instead `showMissingWordToast(context, word)` shows an info `ZToast` — «X» تو لغات ما نبود، می‌خوای گزارش کنی؟ — with a ✓ beside the ✕ (label «گزارش بده», 7 s) that sends the word as an `add` suggestion (`WordReportCubit`, analytics `source: life_lost`) and confirms with a success/error toast. `GameBloc` keeps the refused word in `GameActive.lastMistakeWord` (set with `lastMistakeReason`, null for a timeout, cleared on the next accepted word). `_GameView` (`game_screen.dart`) fires it when `livesRemaining` drops with reason `not_in_dictionary`, and also on the Daily Challenge's *final* loss (`GameOver` with `mode == 'daily'`); the toast lives on the root overlay, so it survives the navigation to `/daily`. A solo game's final loss still uses the ZOver pill. Tests: `test/features/words/missing_word_toast_test.dart`, `test/features/game/game_bloc_life_lost_word_test.dart`, action cases in `z_toast_test.dart`. **Not verified on a device.**
- **Profile (`profile_word_card.dart`, `suggest_word_dialog.dart`, `my_word_reports_dialog.dart`):** a card «کلمه‌ای کم داریم؟» between the invite card/guest upsell and the settings row — «پیشنهاد کلمه» (for everyone; local checks via `DictionaryService.hasValidChars`, ≥3 letters, "already in the game") and, signed in, «پیشنهادهای من» (status per report: در انتظار بررسی / اضافه شد / رد شد / حذف شد / برای هوش مصنوعی مسدود شد, plus «سکه در جوایز»). Reward text uses `GameConstants.wordSuggestionCoins` (25, mirrors `config.CoinWordSuggestion`).
- **Rewards:** `rewardFace` renders kind `word_suggestion` («پاداش پیشنهاد کلمه», the word from `detail`, teal «ک» disc).
- **Tests:** `test/core/services/dictionary_delta_service_test.dart`, `test/features/words/*`, `test/features/game/game_bloc_rejected_word_test.dart`, `test/features/rewards/reward_format_word_test.dart`, new cases in `z_over_screen_test.dart` (the harness now registers a fake `WordSuggestionsRepository` — any test that renders a loss with a `not_in_dictionary` rejection needs one).
- **Goldens:** the four `z_profile_*` goldens were regenerated (the new card moves the layout; they passed on a clean HEAD here). **The `z_over_screen` win/loss-final goldens will also differ on a machine where they pass** (the flag link adds a row) — regenerate them there (`flutter test test/features/game/z_over_screen_test.dart --update-goldens`); on this Linux box those four, plus the solo/play/friends/login/daily/home/splash/bottom-nav/shared-widget goldens, already fail on a clean HEAD, so they were not touched.
- **Still to do:** verify on a device/emulator (guest + signed-in report from ZOver and from the profile; approve in the panel and watch the word become valid in solo after the next resume; reward appears in `/rewards`); an offline outbox for reports; the privacy text now exists and covers reported words (§ Legal Pages); no opt-out switch for the new analytics event.
- **Risks:** moderation load (mitigated by ranking + auto-reject of known-rejected), reward farming (approval-gated + limits), brief client/server dictionary drift (multiplayer stays authoritative), offensive text stored in reports.

---

## 📜 Legal Pages — Terms & Privacy (2026-10-27)

Public, no-login pages: **`https://amirabbasataei.ir/terms`** («قوانین و مقررات استفاده») and **`/privacy`** («سیاست حریم خصوصی»). Required by Cafe Bazaar / Myket as the privacy-policy URL. **The text is a draft that has not been reviewed by a lawyer** — see the review list below.

- **Hosting (option a):** server-rendered once at startup and **embedded in the Go binary** (`backend/internal/legal`, handler `handler.LegalHandler` in `handler/legal.go`, mounted in `main.go` after `/health`). It ships with `scripts/deploy_backend.sh`; **no nginx change** (nginx already proxies `/` to the backend). Routes: `GET|HEAD /terms`, `/privacy`, `/legal/assets/:name` (never `/api/v1/*` or `/admin`). Unknown paths keep gin's plain 404. ETag + `max-age=3600` on pages, `max-age=86400` on assets.
- **Content lives in** `legal/templates/terms.html` and `privacy.html` (Go `html/template` fragments, `{{define "body"}}`), wrapped by `layout.html` and styled by `legal.css`. Headings are `<h2 id="…">`; **the table of contents is generated from them** (`buildTOC`), so add a section by adding an `<h2 id>`; it is auto-numbered in Persian digits (CSS counter). Owner name, contact email, version and date are constants in `legal/legal.go` (`Version`/`VersionFa`, `UpdatedISO`/`UpdatedJal`/`UpdatedFa`, `OwnerFa`, `ContactMail`). **When the text changes materially, bump `Version` + the date together** (current: **1.0, 1405/08/05 = 2026-10-27**); a future re-acceptance flow can compare against it.
- **Design:** ZColors light/dark tokens as CSS variables (`prefers-color-scheme`), Vazirmatn 400/700 as self-hosted **WOFF2** (`legal/assets/`, converted from `client/assets/fonts`; OFL.txt is served beside them), RTL, ~65ch measure, sticky TOC on ≥900px and a collapsible one on phones (both rendered, one hidden; no JS), skip link, 44dp nav targets, print stylesheet. No external scripts/fonts/requests. **CSP is strict**: `default-src 'none'; style-src 'sha256-<hash of legal.css>'; font-src 'self'; …` — the stylesheet is inline and allowed by hash (computed at startup), so don't add inline `style=` attributes or scripts. The runtime image has no MIME database, so asset content types are set explicitly in `NewLegalHandler`.
- **Tests:** `handler/legal_test.go` (200 + content type + headers, no external resources, TOC ↔ headings, HEAD/304, assets, no collision with `/api` and `/admin`, unknown paths 404).
- **Client links:** `core/services/legal_links.dart` (`LegalLinks`, `LegalDoc.terms|privacy`, registered in get_it; URLs = `DioClient.baseUrl` + `/terms|/privacy`, so an `API_BASE_URL` build opens its own backend; opener injectable for tests; `url_launcher` with `LaunchMode.externalApplication` — plain Android intent / iOS `openURL`, no Google services). `openLegalDoc(context, doc)` (`core/widgets/legal_doc_opener.dart`) shows a Persian `ZToast` (`legalPageOpenFailedMessage`) when the browser cannot be launched. Entry points: the login sentence («با ورود، **قوانین** و **حریم خصوصی** زنجیر را می‌پذیرم.», `features/auth/view/widgets/legal_consent_text.dart`, two inline spans; inline links are exempt from the 44dp rule, line height raised to 1.9) and two 44dp `ProfileChunkButton`s at the bottom of ZProfile's settings (`ProfileSettings.onTerms/onPrivacy`, guests too). Tests: `test/core/services/legal_links_test.dart`, `terms and privacy links` group in `z_login_screen_test.dart`, `legal links` group in `z_profile_screen_test.dart`.
- **What the pages claim (keep it true; update both pages when a fact changes):** phone + OTP via Kavenegar, 13+, one account per phone; guests play on-device but **anonymous analytics events are still sent** and local matches (even pre-login ones) are uploaded after sign-in; self-hosted analytics with a random install ID, linked to the account after sign-in, raw events 6 months, daily rollups (which include the install/user id) with **no expiry**, **no opt-out switch**; reported words stored with the reporter; third parties = Kavenegar, FCM (messaging only), Tapsell (rewarded ads, Android; its own policy linked), ArvanCloud, own server; nginx logs 14 days; DB backups 7 daily + 4 weekly; preset taunts only, no free chat; coins virtual/non-refundable; **no real payments exist yet** (premium granted by admin); accounts can be banned; **no in-app account deletion** — deletion is by email to the owner with a 30-day promise (unimplemented operationally: there is no delete tooling, FKs on `matches`/`match_players` mean it must anonymise); governing law Iran.
- **Not built / follow-ups:** an in-app «حذف حساب» flow (and the admin tooling behind the manual process); an opt-out switch for analytics; recording «accepted terms vX at time T» on the user (display-only for now: the login sentence is the only acceptance; add `users.terms_version/terms_accepted_at` + a `verify-otp` field when the text next changes); the Tapsell SDK is initialised with `setUserConsent(true)` and no consent screen (see `AdService.init`); clean up stale unverified-phone rows; nothing here has been checked on a device.
- **Lawyer-review list:** the limitation-of-liability clause, the governing-law/jurisdiction line, the under-18 guardian wording, the account-ban / loss-of-coins terms, the 30-day deletion commitment, retention periods stated as commitments, the Tapsell consent handling, and whether an individual may publish without a registered entity or e-commerce (enamad) notice.

---

## 🎓 Tutorial

**Removed — no tutorial.** Product decision (Phase 17): the first-time tutorial was dropped. `tutorial_screen.dart`, the `/tutorial` route, the `tutorial_completed` first-launch redirect, and Profile → Help "replay tutorial" were deleted in `fa5811d`. Do not rebuild it.

---

## 🏆 Leaderboard & Weekly Reset

- Redis Sorted Set `leaderboard:global:weekly` — score added at end of **multiplayer games only** (`ws.Room` is the sole `AddScore` caller; solo, vs-AI and Daily Challenge scores are not added — todo.md 2.4).
- **All-time board («همیشه»):** `GET /leaderboard?type=alltime` ranks `player_stats.total_score` (lifetime, never reset; DB-backed, AI user excluded). `LeaderboardService.AddScore` increments it together with the weekly Redis score, so it counts exactly the games the weekly board counts (currently multiplayer only — Daily Challenge scores are not added to either). Counts only from migration 008 onward; no backfill.
- `GET /leaderboard?type=friends` fetches friend IDs, retrieves scores via `ZSCORE` from the same set. Its `player_rank`/`player_score` are the requester's *global* weekly values, not their place among friends (the client reads that from the entries — todo.md 2.13).
- **ZBoard client (`features/leaderboard/`):** four tabs — «این هفته» (`type=global`), «امروز» (`GET /daily/leaderboard`, today's Daily Challenge; rows carry `chain_length`, no avatar, no player score), «همیشه» (`type=alltime`), «دوستان» (`type=friends`). Each tab loads on demand and fails on its own; the weekly note shows the real prizes and the countdown to the Saturday 00:00 Iran-time reset (`untilIranWeekReset`). Per-stage detail in REDESIGN_PLAN.md § ZBoard.

**Weekly reset (Saturday 00:00 Iran time = end of Friday, the Iranian week):**
1. Query top 3 → insert `weekly_leaderboard_rewards` (idempotent)
2. Award coins: 1st →500, 2nd →300, 3rd →100
3. Send push notifications to rewarded users
4. Delete Redis key

---

## 🧪 Testing Strategy

Tests written **inside the phase that introduces the code**.

**Backend (Go):** Unit tests for `engine/`, `service/`, `scheduler/`. Repository tests use a real Postgres: `testutil.NewPostgres` creates a fresh migrated database on the server named by `TEST_DATABASE_URL` (locally `postgres://wordchain:wordchain@localhost:5433/wordchain?sslmode=disable`, port 5433 per `docker-compose.override.yml`) and skips when it is unset — `testcontainers-go` is not a dependency. Handler tests use `httptest` with stubbed service. WS tests use `httptest.Server` with real client. Target ≥ 70% coverage on `engine/` and `service/`.

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

- **Production host (`root@185.110.191.158`, Ubuntu 26.04, 1 vCPU, 2 GB RAM + 2 GB swap) is a shared multi-site host** (Zanjir, Ham-Ketab on `varaqa.ir`, more to come). Layout, port map, adding a site, HTTPS, backups and recovery: **`docs/server-runbook.md`**; design/history: `docs/server-plan.md`. Everything server-side comes from `deploy/` in this repo: `deploy/host/` → `/opt/infra` (shared PostGIS Postgres `infra-postgres`, nginx shared config + per-site files, systemd timers, `new-site` / `site-https` / `site-db` / `pg-backup` / `pg-restore-test` / `arvan-ips-refresh`), applied with `bash scripts/host_sync.sh`; `deploy/sites/wordchain/compose.yml` → `/opt/wordchain/compose.yml` (app + Redis; DB = database/role `wordchain` on the shared Postgres, host `postgres` on the external `infra` network). Secrets only in root-only `/opt/*/.env` (all rotated 2026-10-11) and `/opt/wordchain/secrets/fcm-service-account.json`. Only nginx is public: `https://amirabbasataei.ir` (through ArvanCloud; edge HTTPS enabled and verified 2026-10-13: valid cert, HTTP/2, API/admin/WS route all reachable; plain `http://` is 301-redirected to https by the origin's :80 server, ACME exempt) (the legacy `:8080` listener was removed 2026-10-13 — no installed clients remain); the app binds `127.0.0.1:18080`; unknown hosts are dropped; ufw allows 22/80/443 (a stale 8080 allow rule may remain, harmless); SSH is key-only. Nightly backups (`/var/backups/infra`, 7 daily + 4 weekly, weekly restore test). **Redeploy: `bash scripts/deploy_backend.sh`** (`--dry-run`, `--logs`): builds the panel and a `linux/amd64` image **locally**, ships it with `docker save | ssh docker load`, sets `APP_IMAGE` in `/opt/wordchain/.env`, `docker compose up -d app`, polls `/health`; the server never builds images (that hung the old rsync+build deploy). **Client:** `DioClient.baseUrl` defaults to `https://amirabbasataei.ir` (WS (`wss://`) and avatar URLs derive from it; `--dart-define=API_BASE_URL=http://10.0.2.2:8080` for a local backend); Android cleartext is allowed only in the debug manifest (local dev backend); release builds are HTTPS-only.
- Migrations are embedded via `io/fs` (`backend/migrations/embed.go`) and auto-run at server startup. Current set: `001_init`, `002_friend_challenge_room`, `003_phone_auth_referral` (drops email/password, adds phone/OTP/referral columns), `004_ai_system_user`, `005_daily_retries`, `006_referral_rewards` (superseded by `007_inbox_rewards`), `008_total_score` (adds `player_stats.total_score` for the all-time board), `009_xp` (adds `player_stats.xp` for profile levels), `010_premium_perks` (adds `users.premium_until` + `users.avatar_id`), `011_perks_catalog` (`taunts` + `avatars` tables; seeds the 9 taunts, avatars are uploaded with `scripts/perks_admin.sh seed`), `012_admin` (`admin_users` + `admin_audit_log`), `013_user_ban` (`users.banned_at` + `ban_reason`), `014_analytics` (partitioned `analytics_events` + `analytics_installs` + `analytics_daily_*` rollups), `015_word_suggestions` (`word_suggestions`, `word_suggestion_reports`, `dictionary_overrides`).
- **Ads (Tapsell Mediation, Android only):** the app key is a manifest placeholder in `client/android/app/build.gradle.kts`; the zone id is compile-time `--dart-define`s read in `core/services/ad_service.dart` (`AdZones`). Copy `client/tapsell.example.json` to `client/tapsell.json` (gitignored), fill in the rewarded zone id, and pass `--dart-define-from-file=tapsell.json` to `flutter run`/`build`. An empty id silently disables ads. Policy: only player-initiated rewarded ads — no interstitials and no banners (the Tapsell banner is a native overlay that leaked across screens and covered `ZBottomNav`; removed).

---

## 🚧 Open Issues & Follow-ups

Tracked in detail in REDESIGN_PLAN.md; listed here so they aren't lost. 

**Phase 17 placeholders (canvas UI rendered, no backend yet — never fake client-side):**
- **Best-of-5 rounds** (ZVersus) — the static «دست ۱ از ۵» indicator was removed (it was a placeholder with no backend); needs new WS round events + server round state + match-level winner rule before re-adding.
- **Multiplayer lives** — not built (see Lives).
- **Badges** (ZProfile) — not built; the canvas's badges row is not drawn at all (no schema fields, no endpoint).
- **Levels** (ZProfile) — implemented: `player_stats.xp` is credited with each game's score at game end (`GameService.AddXP`: solo/AI/daily via `CreateSoloGame`, multiplayer via `ws.Room` `XPSvc`). Curve in `config.XPForLevel`/`LevelFromXP` (step to level L+1 = 1000×L); `GET /profile/stats` returns `xp`, `level`, `xp_in_level`, `xp_for_next`. Level titles live in `GameConstants.levelTitles`. Counts from migration 009 onward (no backfill); guests have no level.
- **Typing indicator** (ZVersus) — not built; needs a new WS event.
- **Long-word bonus in Go scorer** — Flutter-only today.

**Known bugs / gaps (pre-existing, flagged not fixed):**
- **Longest word is the player's own words only.** vs-AI chains are shared, so `longestOwnWord` (`core/services/ai_opponent.dart`; player = even indices) feeds local stats and `SyncService` uploads it as `longest_word` on `POST /game/solo`; the server honours it only if it appears in `word_chain` (older clients fall back to the whole chain). Values stored before this fix (an AI word) are never lowered — `player_stats.longest_word` / local `LocalPlayerStats.longestWord` only grow; reset by hand if needed.
- `test/core/widgets/shared_widgets_golden_test.dart` (light + dark) fails on a clean checkout too (1.05% pixel diff) — verified with `AvatarTile` reverted to HEAD; unrelated to Phase 22.
- **Fixed:** the iOS-simulator blank white screen. Cause: `NotificationService.init()` awaited `FirebaseMessaging.getInitialMessage()` before `runApp`; without `GoogleService-Info.plist`/APNs it never completes (hangs, doesn't throw, so the `try/catch` didn't help). Now `main.dart` runs Firebase setup in the background (`_initFirebase()`, unawaited, after `runApp`) and `getInitialMessage()` has a 3s timeout. Rule: Firebase/push calls must never gate the first frame. Push itself still doesn't work on iOS until `GoogleService-Info.plist` + an APNs key are added.
- ZProfile no longer draws the canvas's «صدا و لرزش» and «یادآور» toggles (nothing was persisted, no reminder scheduled — rebuilt 2026-10-25 without them); add them back only together with a real setting.
- **`player_stats.wins` and `best_match_streak` are never written** (the server's only stats writers are `IncrementMatchStats` — `total_matches` + `longest_word`, solo/AI/daily uploads only — and `RecordGamePlayed`/`AddXP`), and local `wins` is never incremented, so a «برد» stat would always read 0 and ZProfile shows none. «بلندترین زنجیر» is the local `bestMatchStreak` (max of local chain length and the server's 0). `total_matches` does not count 1v1 games. `GET /profile/stats` sends no coin balance (the coin pill reads `AuthCubit.coins`).
- Kavenegar SMS delivery unverified end-to-end (no account yet; dev bypass OTP `1111`).
- **FCM setup (done client-side, Firebase project `zanjir-269aa`):** `main.dart` initialises Firebase with `DefaultFirebaseOptions` and, while a user is signed in, registers the token (`NotificationService.registerToken`, also on token refresh). The OS permission is **not** asked at launch: the first time a signed-in user taps the Friends tab, `maybeAskNotificationPermission` (`core/widgets/notification_permission_dialog.dart`) shows an explainer dialog once (flag in `shared_preferences`) and requests permission only if they accept; `AuthCubit.logout` deregisters it first. Foreground pushes show as a SnackBar (`foregroundStream`). **Server delivery needs the service-account key:** download it from Firebase console → Project settings → Service accounts → Generate new private key and save it as `backend/secrets/fcm-service-account.json` (gitignored, mounted at `/secrets`), then `docker compose up -d --build app`. Until then sends are logged no-ops. **Dev caveat:** in Iran the Docker container can't reach Google (only the host does, via Nekoray), so FCM sends time out from the container; fine from a foreign server. Pushes carry no `data.route` yet, so tapping one just opens the app; iOS also needs `GoogleService-Info.plist` + APNs key (not done).

---

## ⚠️ Important Notes for Claude Code

- **After any backend change, rebuild and restart the backend** (locally it runs in Docker: `cd backend && docker compose up -d --build app`; production: `bash scripts/deploy_backend.sh`) and **always update CLAUDE.md** .

- **Read REDESIGN_PLAN.md too while Phase 17 is in progress.** Record each stage's outcome, decisions, and flagged issues there.
- **Verify on-device.** Phase 17 found multiple bugs that only a live run exposed (Stage 4 multiplayer was non-functional end-to-end despite passing analysis). Don't mark a stage complete from `flutter analyze`/tests alone.
- **Never implement outside the current phase's scope.** Flag missing items from prior phases without silently fixing them.
- **Always check previous phases' output** before writing code that depends on it (verify actual method signatures).
- **Dictionary is dual:** `fa.txt` lives in both `backend/internal/engine/data/` and `client/assets/words/`. Keep them byte-identical. Admin-approved words/removals live in the runtime overlay (`dictionary_overrides`), not in these files, until folded in at release (§ Word Suggestions).
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
| `ADMIN_API_KEY` | no | (random 32+ chars) | Script access to `/api/v1/admin/*` via `X-Admin-Key` (acts as owner, audit actor `script`). With no key **and** no admin user the routes return 404 |
| `ADMIN_SESSION_TTL` | no | `2h` | Idle timeout of an admin panel session (sliding; the absolute cap is a fixed 12h) |
| `ADMIN_IP_ALLOWLIST` | no | `203.0.113.7,10.0.0.0/8` | Comma-separated IPs/CIDRs allowed to reach `/api/v1/admin/*`; others get 404. Empty = unrestricted. Uses gin `ClientIP()`, so it is only as trustworthy as the proxy's forwarding headers |

---

## 📎 Appendix: Dictionary & Word Frequency List

**Persian dictionary (`fa.txt`)** — the only word data in the project. 24,199 words, one word per line, no spaces, no teh marbuta (ة) or diacritics. Stored at `backend/internal/engine/data/fa.txt` and `client/assets/words/fa.txt` (byte-identical). History: 162,626 (noisy) → 17,414 in commit `2758a1c` → 17,321 → 21,527 on 2026-10-09 → 24,199 on 2026-10-13.

**Decision (2026-10-09): the curated list is final; do not restore the 162k list.** It is the 17.3k curated list plus 4,205 words that passed *all* of: present in the Hunspell `fa` dictionary (or Wiktionary lemma) **and** OpenSubtitles frequency ≥ 30, not a verb conjugation/plural/colloquial spelling, then a manual review of every candidate. Policy: countries/cities/historic figures in, foreign first names out; infinitives and bare past forms («رفت») in, personal conjugations and imperatives out; no words ending in ء. The 3,750 words rejected in that review are kept in `output/dictionary/rejected_words.txt` (untracked) so a future rebuild does not re-add them; the added words are visible in `git diff` of `fa.txt`. Source licenses (Hunspell fa, Wiktionary, OpenSubtitles) were **not** checked — verify before commercial release. Trap letters stay ژ ظ ث ذ ض (still the five rarest starts: 33–69 words).

**2026-10-13 top-up (+2,673 words, appended at the end of `fa.txt`):** from a 453k-word candidate dump (`distinct_words.txt`, untracked, ordered roughly by quality). Pipeline: Persian letters + ZWNJ only, ≥3 letters, not already in `fa.txt`/`rejected_words.txt`; dropped anything that is `known word + clitic/plural/ezafe/است/comparative`, `می/نمی` forms, `ب/ن` verb forms, Arabic `ال…` phrases; kept only candidates with evidence (Hunspell and (OpenSubtitles freq ≥ 30 or file rank < 30k), or rank < 20k) and then hand-picked every word (infinitives incl. compound verbs, compounds, nisba adjectives, adverbs, cities/provinces/historic names; no words ending in ء). Colloquial, foreign-name and conjugated forms were rejected. Trap letters unchanged (still the five rarest starts: 38–75 words).

The English `word_freq_ranks.txt` and `engine/frequency.go` were deleted — there is no English data left in the project.
