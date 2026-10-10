# ADMIN_PLAN.md — Phase 23: زنجیر Admin Panel

Read this (and CLAUDE.md) at the start of every admin-panel session. Run one stage per session, in order A1 → A2, then A3–A6 in any order, A7 last. Record each stage's outcome, decisions and flagged issues in the log at the bottom.

## Status

| Stage | Title | Status |
|---|---|---|
| A1 | Backend foundation: admin auth, sessions, roles, audit | [x] Complete |
| A2 | Frontend scaffold, theme, shell, login, embedding | [x] Complete |
| A3 | Dashboard (real data only) | [ ] Not Started |
| A4 | Users & economy (incl. ban) | [ ] Not Started |
| A5 | Content & catalogue (taunts, avatars, daily, leaderboards) | [ ] Not Started |
| A6 | Live ops, matches & notifications | [ ] Not Started |
| A7 | Admins, 2FA, audit log, hardening, release | [ ] Not Started |

Theme reference image: `~/Downloads/panel.png` (copy it to `admin/design/reference.png` in A2 so it lives in the repo).

## Technology decision
| Concern | Choice | Why |
|---|---|---|
| Backend | Existing Go/Gin server, new `handler/admin_*.go` → `service/admin_*.go` → `repository/admin_*.go` (3 layers, per CLAUDE.md) | Reuses repos/services, DB, Redis, Hub; no new service on the 2 GB box |
| Frontend | React 18 + TypeScript + Vite, in a new top-level `admin/` dir | Mature ecosystem for data-heavy dashboards; Node 22 + pnpm already installed |
| Styling | Tailwind CSS v4 with CSS-variable tokens + Radix primitives (shadcn/ui-style components, copied in, not a dependency) | Native `dir="rtl"` support, logical properties (`ps-`/`pe-`/`start-`/`end-`) |
| Data | TanStack Query + React Router | Caching, pagination, mutations with invalidation |
| Charts | Apache ECharts (`echarts-for-react`) | Smooth gradient areas, rounded gradient bars, donut — exactly the reference's chart style; custom font + Persian-digit formatters |
| Icons / dates | `lucide-react`; `date-fns-jalali` | Jalali dates; Persian digits via a small `toFa()` util (mirror of `client/lib/core/utils/persian_digits.dart`) |
| Serving | `vite build` → `backend/internal/adminui/dist`, embedded with `//go:embed all:dist`, served by Gin at `/admin/*` with SPA fallback | One deploy, same origin → httpOnly cookies, no CORS |
| Auth | `admin_users` table, bcrypt, **server-side sessions in Redis**, httpOnly `SameSite=Strict` cookie, TOTP 2FA (A7) | Revocable; no admin JWT confusion with player JWTs |

**Security note (public over plain HTTP, user's choice):** passwords and session cookies are sniffable until TLS exists. Mitigations built in: short idle session TTL (2h, absolute 12h), login rate-limit + lockout, mandatory TOTP from A7, role-based permissions, full audit log, optional `ADMIN_IP_ALLOWLIST` env. Adding a domain + TLS later is strongly recommended and needs no panel changes.

## Visual system (from panel.png, mirrored to RTL)
- Layout: fixed **sidebar on the right** (logo «زنجیر» + collapse arrow, grouped nav with small grey uppercase-style section labels, active item = filled rounded pill, chevrons pointing left for expandable groups); topbar with search field, theme toggle, notification bell with red count badge, admin avatar/name/role block at the **far left**; footer copyright line.
- Tokens (`admin/src/styles/tokens.css`, dark default + light variant via `data-theme`): page bg `#0f1215`, surface/card `#171a1e`, raised `#1d2025`, border `#272b31`, sidebar `#14171a`, active item `#2a2e34`, text `#e8eaed`, muted `#8b919a`; accents: blue `#0a84ff`, orange `#ff6a2b`, pink/red `#ff2d55`, green `#19c32c`, yellow `#ffc400`. Cards: radius 8px, 1px border, card header row with title + `⋯` menu separated by a hairline.
- Stat card pattern (reference bottom-right): title, big number, coloured icon at the end, mini bar sparkline of 14 days, coloured `+25%`/`-10%` delta — all digits Persian.
- Font: **Estedad** (Variable woff2 + `OFL.txt` from github.com/aminabedi68/Estedad releases) in `admin/public/fonts/`, `@font-face` with `font-display: swap`; tabular numerals for tables.
- Rules mirroring the app: Persian digits everywhere, «٬» thousands separator, Jalali dates (Iran time UTC+3:30), logical CSS properties only (never left/right), no hex in components (tokens only).

---

## Stage A1 — Backend foundation: admin auth, sessions, roles, audit
- Migration `012_admin`: `admin_users(id uuid pk, username unique, password_hash, role text check in ('owner','operator','viewer'), totp_secret text null, disabled_at, last_login_at, created_at)`; `admin_audit_log(id bigserial, admin_id uuid null, actor text, action text, target_type, target_id, payload jsonb, ip inet, created_at)` + index on `(created_at desc)`.
- `repository/admin.go`, `service/admin_auth.go` (bcrypt; Redis sessions `admin:sess:<32-byte random>` → `{admin_id, role, created_at}` with sliding 2h / absolute 12h TTL; login rate limit `admin:login:<ip>` 5 per 15 min), `service/admin_audit.go` (`Record(ctx, actor, action, target, payload)`).
- `middleware/admin.go`: extend `RequireAdmin` to accept **either** the session cookie (`zanjir_admin`) **or** the existing `X-Admin-Key` (actor = `script`, so `scripts/perks_admin.sh` keeps working); `RequireRole(min)`; CSRF guard: mutating requests must carry `X-Requested-With: zanjir-admin` (plus SameSite=Strict). Keep 404-when-unconfigured behaviour: panel enabled when at least one admin user exists or key set.
- Routes: `POST /api/v1/admin/auth/login`, `POST /admin/auth/logout`, `GET /admin/auth/me`. Existing taunt/avatar admin routes move under the new middleware and write audit entries.
- Bootstrap CLI: `cmd/adminctl` (`create-user`, `set-password`, `disable`), added to the Dockerfile build; `scripts/admin_user.sh <username> [role]` runs it on prod via `ssh … docker compose exec app /adminctl …` (password prompted, never in argv).
- Error codes stay English (operator-only, per `adminError` in `handler/perks_catalog.go`); the panel maps them to Persian.
- Tests: service tests (password, lockout, session expiry), handler tests with `httptest` (login/logout/me, role denial, CSRF header, key fallback).
- Docs: update this file's status + log, add an "Admin panel" section to CLAUDE.md (Phase 23 row already exists); add env vars (`ADMIN_SESSION_TTL`, `ADMIN_IP_ALLOWLIST`) to the appendix. Rebuild backend (`docker compose up -d --build app`).

## Stage A2 — Frontend scaffold, theme, shell, login, embedding
- `admin/` Vite React TS project (pnpm), Tailwind v4, `index.html` with `lang="fa" dir="rtl"`; vite `base: '/admin/'`, `build.outDir: '../backend/internal/adminui/dist'`.
- Download Estedad into `admin/public/fonts/` (+ `OFL.txt`); tokens.css as above; dark/light toggle persisted in `localStorage` (try/catch).
- Component kit in `admin/src/components/ui/`: `Card` (header + `⋯` menu), `StatCard` (number, icon, sparkline, delta), `DataTable` (server pagination, sort, empty/loading/error states), `Button`, `Input`, `Select`, `Dialog`, `ConfirmDialog` (typed confirmation for destructive actions), `Badge`, `Tabs`, `Toast`, `Avatar`, `Skeleton`.
- Shell: `AppLayout` (right sidebar with groups: داشبورد · کاربران · محتوا [تیکه‌ها، آواتارها، چالش روزانه، جدول امتیازات] · عملیات زنده [اتاق‌های زنده، مسابقه‌ها، اعلان‌ها] · مدیریت [مدیران، گزارش فعالیت]), topbar, footer, collapsible sidebar, mobile drawer.
- `lib/api.ts` (fetch wrapper with `credentials: 'include'`, CSRF header, 401 → login redirect, Persian error map in `lib/errors.ts`), `lib/fa.ts` (digits, number/compact formatting, Jalali dates), `auth` context via `GET /admin/auth/me`, route guard, Persian **login page** styled like the reference.
- Go: `internal/adminui/embed.go` (`//go:embed all:dist`, committed `dist/.gitkeep`, "panel not built" fallback page) + `handler/admin_ui.go` serving `/admin` and `/admin/*` with `index.html` fallback, long cache for hashed assets, CSP/security headers. Gitignore `dist/*` except `.gitkeep`.
- `scripts/deploy_backend.sh`: build the panel (`pnpm -C admin install --frozen-lockfile && pnpm -C admin build`) before rsync. `dev.sh`/README: `pnpm -C admin dev` with Vite proxy `/api` → `localhost:8080`.
- Placeholder pages for every nav item. Verify in Chrome: login, RTL shell, both themes, mobile width.

## Stage A3 — Dashboard (real data only)
- Backend `GET /admin/dashboard/summary`: total registered users, new today/7d, premium active, coins in circulation (`SUM(users.coins)`), matches today by mode, daily-challenge participants today, unclaimed rewards, live rooms + connected players (new `Hub.Snapshot()` in `ws/hub.go`), matchmaking queue length (Redis), FCM configured flag.
- `GET /admin/dashboard/timeseries?days=30`: per-day signups, matches (multiplayer vs uploaded solo/AI), daily-challenge attempts, coins awarded via claimed rewards — Iran-time day buckets (`config.IranLocation`).
- UI mirroring the reference: big smooth gradient area chart «فعالیت روزانه» (signups vs matches), rounded gradient bar chart «مسابقه‌ها در ۷ روز», donut «سهم حالت‌ها» (solo / AI / 1v1 / daily), 2×3 grid of `StatCard`s with 14-day sparklines and period-over-period deltas. Auto-refresh every 60s. No invented metrics (e.g. no DAU history — `player_stats` stores only the last played date; note this in ADMIN_PLAN.md).

## Stage A4 — Users & economy
- Endpoints: `GET /admin/users?q=&filter=premium|banned|new&sort=&page=` (search by phone, username, referral code, id); `GET /admin/users/:id` (profile, `player_stats`, XP/level via `config.LevelFromXP`, coins, premium, avatar, referrer + referred users, inbox rewards, recent matches, daily attempts, friends count, device token count).
- Actions (role ≥ operator, all audited with a required reason): adjust coins ± (reuse `UserRepository.AwardCoins`/`SpendCoins`), or grant as a claimable inbox reward (`CreateInboxReward`, new kind `admin_gift`); grant/extend/revoke premium (same semantics as `scripts/grant_premium.sh`); rename (reuse `AuthService.UpdateUsername` validation); clear avatar; **ban/unban**.
- Ban: migration `013_user_ban` (`users.banned_at`, `ban_reason`); enforced in `verify-otp`, `refresh`, `RequireAuth`, WS handshake, queue join, challenge create; banned users excluded from leaderboards. New error code `account_banned` → Persian entry in `client/lib/core/utils/error_messages.dart` (test enforces it).
- UI: users table (avatar, username, phone masked except for owner, coins, level, premium crown, joined Jalali date, status badge), user detail page with tabs (خلاصه · مسابقه‌ها · پاداش‌ها · معرفی‌ها) and action dialogs. Optionally switch `grant_coins.sh`/`grant_premium.sh` to call the API (keep SQL fallback).

## Stage A5 — Content & catalogue
- Taunts: table with inline edit, add, delete, drag-to-reorder (`sort_order`) on the existing `PUT/DELETE /admin/taunts/:id`; char counter vs `config.TauntMaxTextRunes`.
- Avatars: image grid (`GET /avatars/:id/image`), upload/replace (client-side type + 256 KB check, then existing multipart `PUT /admin/avatars/:id`), delete with confirmation showing how many users currently use it (new count endpoint).
- Daily challenge: new `GET /admin/daily?from=&to=` (rows of `daily_challenges` + attempt counts), `GET /admin/daily/:date` (board via `DailyRepository.GetDailyLeaderboard`, attempts, payout status from Redis `payout:daily:<date>`), `PATCH /admin/daily/:date` to change the start letter of **future** days only (validated against letters with enough words, using the engine dictionary).
- Leaderboards: weekly / all-time / weekly-rewards history (`weekly_leaderboard_rewards`) read-only views reusing `LeaderboardService`.

## Stage A6 — Live ops, matches & notifications
- Live rooms: `GET /admin/live` from `Hub.Snapshot()` (room id, mode, status, players, current turn, chain length, entry fee, started-at); auto-refresh 5s; room detail read-only; owner-only "close room" with entry-fee refund via the room's existing cancel path (only if the Room exposes a safe cancel — investigate first; otherwise skip and note).
- Matches: `GET /admin/matches?mode=&status=&user=&from=&to=` and `GET /admin/matches/:id` (players, scores, winner, continue usage, word chain from `game_state`/word list rendered as Persian chain chips).
- Notifications: compose form (title/body Persian, preview as a phone banner), target = all / one user / segment (premium, active in last N days); sends via `NotificationService.SendToAll`/`SendToUser`; shows "FCM not configured" warning when `configured()` is false; history from the audit log.

## Stage A7 — Admins, audit log, hardening, release
- Admin accounts (owner only): list/create/disable/reset password/change role; self-service password change.
- TOTP 2FA (`github.com/pquerna/otp`): enrolment with QR on first login, then required for every login; recovery via `adminctl reset-2fa`.
- Sessions page: list my active sessions (Redis), revoke one/all.
- Audit log viewer: filters by admin, action, target, date range; JSON payload drawer; links to target user/match.
- Hardening: `ADMIN_IP_ALLOWLIST`, CSP + `X-Frame-Options`, login lockout tuning, bundle size check, 404/500 pages.
- Release: prod setup (`/opt/wordchain/.env` new vars, first owner via `scripts/admin_user.sh`), deploy, end-to-end check on prod; CLAUDE.md + ADMIN_PLAN.md final update.

---

## Critical files
- New: `admin/**`, `backend/internal/adminui/`, `backend/cmd/adminctl/`, `backend/internal/{handler,service,repository}/admin_*.go`, `backend/migrations/012_admin.*`, `013_user_ban.*`, `scripts/admin_user.sh`, `ADMIN_PLAN.md`.
- Modified: `backend/cmd/server/main.go` (route wiring), `backend/internal/middleware/admin.go`, `backend/internal/ws/hub.go` (`Snapshot`), `backend/internal/config/config.go`, `backend/Dockerfile` (adminctl), `scripts/deploy_backend.sh`, `.gitignore`, `CLAUDE.md`, `client/lib/core/utils/error_messages.dart` (A4).
- Reuse: `UserRepository.AwardCoins/SpendCoins/CreateInboxReward/GetPerks/UpdateUsername`, `CatalogService` + `CatalogHandler`, `DailyRepository.GetDailyLeaderboard`, `LeaderboardService`, `NotificationService.SendToAll/SendToUser`, `config.IranLocation`/`LevelFromXP`, `respondError`/`adminError`.

## Per-session workflow
1. Read CLAUDE.md + `ADMIN_PLAN.md`; state "Implement Phase 23 — stage A<n>".
2. Implement backend (3 layers, slog, `fmt.Errorf %w`, sentinel errors) then UI.
3. Rebuild backend (`cd backend && docker compose up -d --build app`), `pnpm -C admin build`.
4. Update `ADMIN_PLAN.md` + CLAUDE.md; user commits (Claude never commits unless asked).

## Verification (every phase)
- `cd backend && go test ./internal/...` (new handler/service tests per phase); `pnpm -C admin typecheck && pnpm -C admin lint && pnpm -C admin test` (vitest for `lib/fa.ts`, `lib/errors.ts`, key components).
- Run locally (`docker compose up`, `pnpm -C admin dev`), create an admin with `adminctl`, and drive the panel in Chrome (claude-in-chrome): login, each new page, RTL correctness, Persian digits, dark/light, 390px width, every mutation shows up in the audit log and in the DB.
- A4/A6 also check effects in the mobile app where relevant (ban blocks login/WS; push arrives; coins visible after `GET /rewards`).

---

## Stage log

### A1 — Backend foundation (2026-10-10) — complete
Built exactly as specified, with these decisions/deviations:
- **Migration `012_admin`** as planned (`admin_audit_log.admin_id` is `ON DELETE SET NULL`, so deleting an admin keeps their history).
- **Files:** `repository/admin.go`, `service/admin_auth.go`, `service/admin_audit.go`, `handler/admin_auth.go`, `middleware/admin.go` (rewritten), `cmd/adminctl`, `scripts/admin_user.sh`, `Dockerfile` builds `/adminctl`, config consts in `config.go` (`Admin*`). Routes wired in `cmd/server/main.go`; taunt/avatar PUT/DELETE moved behind `RequireRole(operator)` and now write audit rows.
- **`RequireAdmin(key, sessions)`** signature changed (adds the session service). Enabled ⇔ key set **or** ≥1 active admin (cached 5s). A request that sends `X-Admin-Key` but is wrong gets `invalid_admin_key` (unchanged); no credentials → `admin_unauthorized`.
- **Sessions re-validate against the DB each request** (disabled/role changes are immediate) rather than trusting the role stored in Redis. Password change / disable revoke all sessions via the `admin:sessions:<id>` index set (also the basis for A7's sessions page). `adminctl` connects to Redis for that; if Redis is unreachable it prints nothing special and sessions simply expire on their own — acceptable, noted.
- **Login throttle** counts failures only: per IP 5 and per username 10 per 15 min (plan said 5/15min per IP; the username counter closes IP-rotation guessing, at the cost that anyone can lock a known username for 15 min — A7 can tune).
- **Added beyond the plan:** `adminctl enable`, `ADMIN_IP_ALLOWLIST` enforcement (`RequireAdminIP`, plan only listed the env var in A1) and an `auth.login_blocked` audit action.
- **Test deps:** `github.com/alicebob/miniredis/v2 v2.35.0` (tests only) and `golang.org/x/term v0.40.0` (adminctl password prompt). Pinned deliberately: the latest miniredis forces `go 1.26`, which would break the `golang:1.25-alpine` image build.
- **Verified live** (local Docker, curl): login (cookie flags, last_login), wrong password / unknown user (identical 401), CSRF header required on login + writes, `/me` for session and for key, viewer denied taunt writes (403 `insufficient_role`), owner write + audit row with payload, key fallback still works, logout invalidates the session, `adminctl disable` ends a live session, 6th failed login → 429 + `Retry-After`. `go test ./internal/...` passes. The "404 when nothing configured" case is covered by unit tests only — the local container has `ADMIN_API_KEY` set. Local DB now contains test admins `tester` (owner) and `peeker` (viewer), password `test-pass-12345` — dev only.
- **Flagged, not fixed:** gin trusts all proxies (existing behaviour) so `ClientIP()` is spoofable via `X-Forwarded-For` unless nginx overwrites it; check `/etc/nginx/conf.d/wordchain.conf` sets `proxy_set_header X-Forwarded-For $remote_addr` before relying on the IP limit/allowlist in A7. Locally every request shows the Docker gateway `172.20.0.1`.


### A2 — Frontend scaffold, theme, shell, login, embedding (2026-10-10) — complete
Built as specified (`admin/` React 18.3 + TS 5.9 + Vite 8 + Tailwind v4, pnpm), with these decisions/deviations:
- **Files:** `admin/src/{styles,lib,auth,components,layout,pages}`; Go side `backend/internal/adminui/{embed.go,dist/.gitkeep}` + `handler/admin_ui.go` (+ `admin_ui_test.go`), wired in `cmd/server/main.go`. `.gitignore` ignores `admin/node_modules` and `backend/internal/adminui/dist/*` except `.gitkeep`.
- **Serving:** `GET|HEAD /admin` and `/admin/*` with `index.html` fallback; a missing file *with an extension* is a 404 (broken asset link), not the shell. `assets/*` → `immutable` 1-year cache; other files (fonts, favicon) 1 day; `index.html` → `no-cache`. Headers: strict CSP (`script-src 'self'`, `frame-ancestors 'none'`, …), `X-Frame-Options: DENY`, `nosniff`, `Referrer-Policy: no-referrer`. The UI honours the same rules as the API: 404 when no admin/key is configured, and `ADMIN_IP_ALLOWLIST` applies. If `dist/index.html` is missing the server answers 503 with a "panel not built" page.
- **CSP consequence:** no inline scripts, so the pre-paint theme script lives in `public/theme-init.js` (loaded from `<head>`, no flash of wrong theme).
- **Theme:** `src/styles/tokens.css` is the only file with hex values (dark default; `data-theme="light"` variant). Tailwind utilities come from `@theme inline` (`bg-surface`, `text-muted`, …). Theme choice persisted in `localStorage` (try/catch). `src/test/lint-rules.test.ts` (like the Flutter token test) fails on hex outside tokens.css and on physical utilities (`ml-/pr-/left-/text-left`…). Font: Estedad v8.5 variable woff2 + `OFL.txt` in `public/fonts/`.
- **Kit:** Button, Input, Select, Card (+`⋯` menu), StatCard, DataTable (server pagination/sort, skeleton/empty/error), Dialog, ConfirmDialog (typed confirmation), Badge, Tabs, Toast, Avatar, Skeleton on Radix + Tailwind. A dev-only gallery at `/admin/kit` (`import.meta.env.DEV`, excluded from the prod bundle) shows all of them with clearly labelled sample data.
- **Shell:** right-hand sidebar (collapsible, state persisted; 390px → drawer from the right), topbar with search (→ `/users?q=`, A4), theme toggle, bell, admin name/role menu at the far left, Jalali-year footer. **The bell has no count badge** — there is no notification source yet and the panel shows real data only. «مدیران» is hidden for non-owners. Every nav item has a placeholder page naming the stage that builds it; unknown paths show a 404 page.
- **Auth:** `AuthProvider` restores the session via `GET /admin/auth/me`; any later 401 clears the session and returns to `/login` (with `from` redirect). Login shows the Persian error map (`lib/errors.ts`) and, on `rate_limited`, locks the form with a Persian `mm:ss` countdown from `Retry-After`.
- **Deps pinned off "latest":** React 18.3.1 (plan), TypeScript ~5.9 (typescript-eslint compatibility). ECharts is **not** added yet (A3). `deploy_backend.sh` now runs `pnpm -C admin install --frozen-lockfile && pnpm -C admin build` before the rsync (also during `--dry-run`); `pnpm build` clears `dist/` (keeping `.gitkeep`) first.
- **Verified:** `pnpm typecheck`, `lint`, `test` (37 vitest tests: `fa`, `errors`, `api`, Login, DataTable/ConfirmDialog/StatCard, design-rule scan) and `go test ./internal/...` pass. Driven against the Docker backend at `http://localhost:8080/admin/`: login success, wrong password (Persian alert), rate-limit (429 → disabled form + `۱۵:۰۰` countdown), deep-link reload with the cookie session, 404 page, RTL geometry (sidebar at the right edge, admin block at the far left), dark/light themes (+ persistence across reload), collapsed sidebar, 390px drawer (opens from the right, closes on navigation, no horizontal scroll), logout (guard redirects to login), Estedad loading, no console errors besides the expected 401/429 responses.
- **Verification caveat:** the claude-in-chrome extension was not connected in this session, so the browser run used headless Google Chrome 153 driven by `puppeteer-core` (installed in the scratchpad, not in the repo) instead. Screenshots were reviewed by eye; no scripted visual-regression exists.
- **Flagged, not fixed:** the 5th wrong password already returns `rate_limited` (A1 limit semantics, per-IP 5). Test runs lock the local IP for 15 min — clear with `docker compose exec redis redis-cli --scan --pattern 'admin:login:*' | xargs redis-cli del`. Bundle is 367 kB (121 kB gzip) before ECharts. `dev.sh` is unchanged (it only starts the backend); the panel dev server is `pnpm -C admin dev`.
