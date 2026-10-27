> **Status (2026-10-27): implemented.** Contract, deviations (partition key `ts`, router-delegate screen tracking) and open items are in CLAUDE.md § Product Analytics and ADMIN_PLAN.md § A8 log. The text below is the original plan.

# Product analytics (behaviour events + retention) — self-hosted, no Firebase

## Context
We want to see what players do (signup → vs-AI game → n seconds on a screen → Daily Challenge …) and retention (D1/D7/D30 cohorts) inside the admin panel. Today nothing records this: ADMIN_PLAN A3 explicitly notes "no DAU history — `player_stats` keeps only the last played date". Firebase Analytics is ruled out (user's choice; Google reachability from Iran is also unreliable).

## Verdict on ClickHouse: not now — use Postgres
- Prod is **1 vCPU / 2 GB RAM, shared** with Postgres, Redis, nginx and other sites. ClickHouse wants several GB of RAM on its own; it would starve the host.
- Volume is small: even 5k DAU × ~80 events ≈ 400k rows/day ≈ 150M rows/year. A **monthly-partitioned Postgres table** with a BRIN index on time plus a **nightly rollup** handles that; dashboards read only the rollups.
- The event table is append-only with a stable schema, so moving to ClickHouse later (when rows reach hundreds of millions or queries get slow) is a copy job, not a redesign.
- Off-the-shelf alternatives (PostHog / Umami / Matomo self-hosted) are also too heavy for this host and would live outside our admin panel.

Difficulty: moderate — roughly 2–3 sessions. Treat it as a new admin stage (e.g. **A8 — Analytics**, after A6/A7 or in between).

## Design

### 1. Identity
- `install_id`: random UUID generated on first launch, stored in `shared_preferences` — lets us track **guests**, who are most new players (guest mode is first-class and needs no server).
- `user_id`: attached when signed in. On login/signup the client sends an `identify` event linking `install_id → user_id`, so a guest's pre-signup funnel joins up with the account.
- Retention is counted per install (all players) and per user (signed-in) — both views in the panel.

### 2. Client (Flutter) — `core/services/analytics_service.dart`
- `track(name, {props})`, `screen(name)`. Events go into a **Drift table `local_analytics_events`** (schema version bump + migration), never straight to the network — consistent with "the backend is never called during an active solo/AI game" and survives app kills.
- Flush in batches (≤ 100 events) to the server on: app background, app foreground, every ~60 s while not on `/game`, and after a game ends. Drop rows on 2xx; keep on failure; cap the table (e.g. 5 000 rows, drop oldest).
- **Screen time**: a `NavigatorObserver` on the `GoRouter` (`core/router/app_router.dart:92`) records `screen_view` with `duration_ms` of the previous screen. The four tabs live in a `StatefulShellRoute`, so tab switches don't hit the observer — also hook `ZBottomNav` taps / `TabRefreshBus` (`core/utils/tab_refresh.dart`). App background pauses the current screen's timer (`WidgetsBindingObserver`, as `ChallengeWatcher` does).
- Explicit events at a small, fixed vocabulary (enum on both sides, unknown names rejected server-side): `app_open`, `session_start/end`, `signup`, `login`, `identify`, `game_start {mode, ai_level}`, `game_end {mode, result, words, score, duration_ms}`, `continue_used {method}`, `powerup_used`, `daily_start/end`, `queue_join/leave`, `match_found`, `ad_watched`, `purchase_tap`, `share`, `friend_request`, `challenge_sent`.
- Each event: `client_event_id` (UUID, for dedup), `name`, `ts` (client time), `session_id`, `screen`, `props` (small JSON), app version, platform.

### 3. Backend (Go, handler → service → repository)
- Migration `014_analytics`:
  - `analytics_events (id bigserial, client_event_id uuid, install_id uuid, user_id uuid null, session_id uuid, name text, screen text, props jsonb, client_ts timestamptz, server_ts timestamptz default now(), app_version text, platform text)` — **partitioned by month on `server_ts`**, BRIN on `server_ts`, btree on `(install_id, server_ts)`, unique on `(client_event_id, …)` for idempotent retries.
  - `analytics_installs (install_id pk, user_id null, first_seen date, last_seen date, platform, app_version)`.
  - Rollups (Iran-time days, `config.IranDate`): `analytics_daily_active (day, install_id, user_id)` and `analytics_daily_counts (day, name, count, uniques)`.
- `POST /api/v1/analytics/events` — **public** (guests), optional JWT to fill `user_id` server-side (never trust a client-supplied user_id), Redis rate limit, max batch size/body size, name whitelist, props size cap, clamp `client_ts` skew.
- Scheduler job (existing 1-min ticker in `internal/scheduler/`): nightly rollup for yesterday (Redis flag like `payout:daily:<date>`), create next month's partition, drop raw partitions older than N months (e.g. 6) — rollups kept forever.
- Retention query from `analytics_installs.first_seen` × `analytics_daily_active` → cohort matrix (D0…D30), cached in Redis for a few minutes.

### 4. Admin panel — new page «تحلیل رفتار»
- Endpoints under `/api/v1/admin/analytics/*` (any role, read-only): `overview` (DAU/WAU/MAU, stickiness, new installs, avg session length), `retention?from&to&by=install|user` (cohort heatmap), `funnel?steps=…` (e.g. app_open → game_start → game_end → signup), `screens` (views + median time per screen), `events` (counts over time per name), `users/:id/timeline` and `installs/:id/timeline` (the "User A did X then Y" view; also a tab on the existing `UserDetail.tsx`).
- Charts via the existing `components/charts/EChart.tsx` + `useChartColors`; Persian digits / Jalali dates per admin rules.

### 5. Privacy
- No phone, no free text, no word contents in props. Mention analytics in the privacy text; optional opt-out switch in ZProfile later.

## Critical files
- New: `client/lib/core/services/analytics_service.dart`, Drift table in `core/database/app_database.dart` (+ DAO), `backend/migrations/014_analytics.*.sql`, `backend/internal/{handler,service,repository}/analytics.go`, `.../admin_analytics.go`, scheduler job, `admin/src/pages/Analytics.tsx` (+ timeline tab in `pages/UserDetail.tsx`).
- Touched: `core/router/app_router.dart` (observer), `core/widgets/z_bottom_nav.dart`, `main.dart` (lifecycle + DI), `GameBloc` / daily / lobby cubits (event calls), `core/di/`.
- Docs: CLAUDE.md (new section + migration list + endpoint list), ADMIN_PLAN.md (new stage + log).

## Suggested staging
1. Backend ingest + tables + rollup job + tests (repo tests with testcontainers).
2. Flutter tracker (Drift buffer, flush, screen observer, core events) + bloc tests; verify on-device that events land in Postgres.
3. Admin page: overview, retention heatmap, funnel, screens, per-user timeline.

## Verification
- `go test ./internal/...` (ingest validation, dedup, rollup, retention SQL against Postgres container).
- `flutter test` (AnalyticsService buffer/flush with mocked dio; observer durations).
- On-device: play guest solo → sign in → open Daily; check `analytics_events` rows and that the guest install is linked to the user; run the rollup manually; check the panel's timeline and retention page with `pnpm -C admin dev`.
- Rebuild backend (`docker compose up -d --build app`) and update CLAUDE.md / ADMIN_PLAN.md.
