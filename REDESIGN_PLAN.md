# REDESIGN_PLAN.md — زنجیر Visual Redesign

Screen-by-screen plan for implementing the Claude Design canvas in Flutter.

**Design source:** `https://claude.ai/design/p/4a90de7c-3340-476f-922d-213a9dcd6307` (`Zanjir.dc.html`)
**Access note:** WebFetch/browser access to `claude.ai/design/...` URLs returns 403 (needs claude.ai login not available to those tools). The reliable path is the `DesignSync` tool: `method: "get_file"` with `projectId: "4a90de7c-3340-476f-922d-213a9dcd6307"` and `path: "<File>.dc.html"` — this works even though `list_projects` doesn't surface this project (it's a canvas, not a design-system project). Per-screen files confirmed present via `list_files`: `ZHome`, `ZSolo`, `ZPlay`, `ZOver`, `ZLobby`, `ZVersus`, `ZDailyBefore`, `ZDailyAfter`, `ZBoard`, `ZProfile`, `ZFriends` (each `<Name>.dc.html`), plus `Zanjir.dc.html` (token sheet + screen imports) and `Vajechin Word Chain.dc.html`.
**Status:** Stages 1–4 complete and on-device verified; Stages 5–6 code complete (on-device verification pending); Stage 7 partially complete.
**Phase:** Phase 17 in the CLAUDE.md status table and PLAN.md (added — see PLAN.md Phase 17).

---

## 0. Summary

The design is **not a re-skin of the current UI — it is a different visual system.**

| | Current app | Design |
|---|---|---|
| Ground | Dark-only navy `#0B0E1C` | Warm paper `#F6F1E7` / warm-plum dark `#211D26` |
| Modes | Dark only (`themeMode` hardcoded) | Full light + dark, same markup, different token values |
| Language | English labels | Persian, RTL-native |
| Type | Material defaults | Vazirmatn 400–900 |
| Elevation | Blur shadows | **Zero blur** — solid offset edges only |
| Accent | One primary blue | Four co-equal accents (indigo/teal/amber/coral) |

Practically every widget's *visuals* get rewritten; nearly every widget's *state contract* survives. Blocs, cubits, repositories, and DI are untouched throughout.

**Design canvas contents:** 11 screens × 2 modes + a token sheet. Sections 2 (light) and 3 (dark) are the *same components* with different CSS variable values — that property is the single most important thing to preserve in the Flutter port.

---

## 1. Spec conflicts — settle before writing code

The design encodes game mechanics that contradict `CLAUDE.md`. Listed rather than silently resolved.

| # | Design shows | CLAUDE.md says | Where |
|---|---|---|---|
| 1 | **Lives** — «۲ جان», «سه جان داری؛ هر کلمهٔ نادرست یکی کم می‌کند» | First invalid word ends the match; one continue per player | ZSolo, ZVersus, ZDailyBefore |
| 2 | **Wager + turn-length picker** — 10/15/20s, بدون شرط / ۲۰ سکه / ۱۰۰ سکه | Turn timer fixed per variant (15s / 8s); no wagering in the coin economy | ZLobby | **→ Superseded 2026-10-03: picker removed, replaced by a fixed entry fee (see Stage 6 follow-up).**
| 3 | **Best-of-5 rounds** — «دست ۳ از ۵» | Single shared chain; first mistake loses | ZVersus |
| 4 | **Long-word bonus** — «۷ حرف · امتیاز دوبرابر» | base + speed + streak + rarity; no length multiplier | ZVersus |
| 5 | **Levels & badges** — «سطح ۱۲ · واژه‌باز», «نشان‌ها ۶ از ۲۴», accuracy %, unique-word count | No level, badge, accuracy, or unique-word fields in `player_stats` | ZProfile |
| 6 | **Referral codes** — «با کد دعوت، ۵۰ سکه بگیر · ZNJR-۴۸۲» | No referral system; not in the coin economy table | ZFriends, ZLobby |

Additional smaller drift:
- ZOver prices continue at **۵۰ coins**; spec says **25** (`GameConstants.continueCostCoins`).
- ZBoard has **4 tabs** (این هفته / امروز / همیشه / دوستان); spec has global-weekly + friends only.
- ZVersus shows a **typing indicator** («مریم دارد می‌نویسد») — no such event exists in the WebSocket protocol.
- ZDailyBefore states a **10s** turn timer; spec says Daily uses 15s.

### Recommendation

- **Adopt 1 and 4.** Lives is a better solo loop than instant death and is mostly `GameBloc` state; the long-word bonus is one line in the scorer. Both are cheap and self-contained.
- **Render 2, 3, 5, 6 as designed but wired to placeholders**, tracked as follow-up backend work. Each is a genuine backend feature (schema + Go service + API); half-building four subsystems mid-redesign would stall the visual work.

### Decisions (final)

1. **Lives** — Adopted as designed. Two lives, replacing instant-death-on-first-mistake, for both solo and multiplayer.
2. **Wager + turn-length picker (ZLobby)** — Originally "build as designed". **Revised 2026-10-03:** game-type, turn-length and wager pickers all removed; Classic is the only variant and the turn is fixed (15s). The wager became a **fixed entry fee** (20 coins per human player, winner takes the 40-coin pot, free vs the AI fallback) — implemented for real in the backend (`ws.Room.chargeEntryFees`/`settleEntryFees`).
3. **Best-of-5 rounds (ZVersus)** — Build the visual UI as designed (round indicator, "دست ۳ از ۵"), wired to a placeholder. Round count is a **fixed constant (best of 5)**, not lobby-configurable — confirmed by the user; not a canvas-driven decision (canvas access wasn't needed for this one in the end). Real round-tracking logic (WS protocol + Go backend: round wins, round transitions, match-level winner) is separate follow-up backend work, not part of this visual redesign.
4. **Long-word bonus** — Adopted as designed.
5. **Levels & badges (ZProfile)** — Rendered as designed, wired to placeholders. Backend work (schema + fields) is follow-up.
6. **Referral codes** — Backend implemented (migration `003_phone_auth_referral`, `POST /auth/verify-otp` signup-time linking + `POST /referral/redeem` post-login). Client wired via `ReferralBottomSheet`, shared by ZLogin's teaser card (signup, +100 coins) and a new Profile → Settings entry (post-login, +50 coins, one-time). ZLobby's room-code invite row was removed on 2026-10-03 (no join-by-code feature; friend challenges are the way to play a friend).

**Drift fixed to match spec (not the canvas):**
- ZOver continue price: 25 coins (`GameConstants.continueCostCoins`), not the canvas's 50.
- ZDailyBefore turn timer: 15s (spec), not the canvas's 10s.
- ZBoard tabs and the ZVersus typing indicator: keep as noted in the follow-up list below — typing indicator needs a new WS event, not built now; turn banner ships without it.

**Phase bookkeeping:** Phase 17 — Visual redesign (زنجیر) added to the CLAUDE.md status table and PLAN.md, rather than editing the completed phases in place.

---

## 2. Stage 1 — Foundation

Everything else depends on this stage. Nothing below it can start until it lands.

### 2.1 Token system

`lib/core/theme/` is rewritten from a flat colour list into a token system:

```
core/theme/
  app_tokens.dart      ZColors extends ThemeExtension<ZColors>
                       ~28 named tokens × 2 value sets (light/dark) + lerp
  app_typography.dart  Vazirmatn TextTheme — the 8 roles from token sheet 4b
  app_spacing.dart     space 4·8·12·14·18·22·26 (screen gutter 18);
                       radii tile 8–12 / chip 999 / card 16–20 / sheet 24–28;
                       tile sizes 26 · 34 · 42–56 · 96; hit target ≥ 44
  app_elevation.dart   solidEdge(deep, y) → [BoxShadow(blurRadius: 0, offset)]
  app_motion.dart      180ms easeOutBack · 140ms easeOut · shake 90ms×2 ·
                       timer 1s linear · theme cross-fade 200ms
  app_theme.dart       light/dark ThemeData wiring the extension
```

**The core discipline: a screen never names a hex value.** Screens read `context.z.indigo`, `context.z.onIndigo`. Light/dark then costs nothing per screen — which is exactly how the design file works. Any hardcoded colour in a screen file is a bug.

Token list (from design sheet 4a) with confirmed hex values, pulled via `DesignSync get_file` on `Zanjir.dc.html` (CSS custom properties on sections `#t2` light / `#t3` dark match the 4a table):

| token | light | dark |
|---|---|---|
| paper | `#F6F1E7` | `#211D26` |
| surface | `#FFFFFF` | `#2B2632` |
| line | `#E3DCCC` | `#3B3543` |
| wash | `#F0EBE0` | `#38313F` |
| ink | `#1E1B2E` | `#F2EDE3` |
| ink60 | `#6B6780` | `#B9B2C2` |
| ink40 | `#8B8798` | `#8E8799` |
| indigo / indigoDeep | `#4C5FE0` / `#3546B8` | `#7180EE` / `#414FB6` |
| teal / tealDeep | `#16A38F` / `#0E8071` | `#2CBBA4` / `#178A79` |
| amber / amberDeep | `#F5A524` / `#C97F0C` | `#F7B44A` / `#C1832A` |
| coral / coralDeep | `#EF4B3C` / `#C22E22` | `#F4685A` / `#BE4034` |
| onIndigo / onIndigoSoft | `#FFFFFF` / `#C9D0FA` | `#14122B` / `#221F4A` |
| onTeal / onTealSoft | `#FFFFFF` / `#BFEDE5` | `#0C2A25` / `#0F3B33` |
| onAmber | `#3A2606` | `#2A1A04` |
| onCoral | `#FFFFFF` | `#2C0E09` |
| inkSurface / inkSurfaceDeep | `#1E1B2E` / `#0C0A16` | `#F2EDE3` / `#C8C0B2` |
| onInkSurface / onInkSurfaceSoft | `#FFFFFF` / `#9F9BB0` | `#211D26` / `#6A6273` |
| tintIndigo | `#E7EAFD` | `#2A2E52` |
| tintTeal | `#E1F4F0` | `#123A34` |
| tintCoral | `#FDEAE7` | `#452724` |

Notes from the token sheet: tile hues keep identity in dark mode (lightened ~12%, paired with dark ink labels where contrast demands it). Dark ground is warm plum `#211D26` (hue ≈ 300, not 0-chroma black) — all four accents stay in play, no single glowing signal color. The player's own chain bubble inverts to cream in dark mode so the "ink on paper" metaphor survives at night.

**Typography roles** (Vazirmatn, letter-spacing 0 everywhere except the wordmark at −0.5px; Persian digits ۰۱۲… everywhere, thousands separator «٬»):

| role | size / weight | line height |
|---|---|---|
| display (score, seed letter) | 40–60 / 900 | 1.0 |
| screen title | 19–21 / 900 | 1.25 |
| chain word — active | 21 / 900 | 1.0 |
| chain word — history | 16–19 / 800 | 1.0 |
| card title | 13.5–15 / 800 | 1.3 |
| body | 12.5 / 500–600 | 1.6 |
| meta / label | 11–11.5 / 600 | 1.4 |
| button | 15–17 / 900 | 1.0 |

**Elevation:** zero blur shadows anywhere. Solid offset edge in the accent's deep variant — cards `0 3px 0 line`, tiles & primary buttons `0 4px 0 accent-deep`. Pressed state removes the offset and translates Y +3.

**Motion:** tile drop / word commit 180ms `easeOutBack`; bubble enter (chain) 140ms fade + 8px slide `easeOut`; timer bar linear 1s ticks, turns coral under 5s; wrong word shake 90ms×2 at 6px amplitude; theme switch 200ms color cross-fade with no layout change; Rive/Lottie reserved for streak flame, game-over burst, match-found handshake only.

### 2.2 Other Stage 1 work

- **Vazirmatn font** — not currently in `pubspec.yaml`. Vendor the .ttf files (400/500/600/700/800/900) to `assets/fonts/` and declare them.
- **Persian digits** — `core/utils/persian_digits.dart`. Every number in every screen renders as ۰۱۲۳ with «٬» thousands separator. One formatter, used everywhere.
- **Theme mode** — `main.dart:65` hardcodes `themeMode: ThemeMode.dark` and no light theme exists. Add a `ThemeCubit` + `shared_preferences` persistence, driven by the حالت شب toggle in ZProfile.
- **RTL audit** — `main.dart:71` wraps the tree in `Directionality.rtl` with a comment admitting the tree was never audited. Now it matters: `EdgeInsets.only(left:)` → `EdgeInsetsDirectional`, `Row` alignment → `start`/`end`.
- **Bottom nav** — the design draws a custom bar (square glyphs, Persian labels خانه / جدول / دوستان / من). Replaces the Material `BottomNavigationBar` in `_MainShell` (`core/router/app_router.dart:130`).

### 2.3 Shared widgets — `lib/core/widgets/`

Extracted because they repeat across three or more screens:

| Widget | Appears in |
|---|---|
| `LetterTile` (size, accent, rotation, solid edge) | **all 11** — the atom of the whole system |
| `SolidCard` (surface + 1px line + `0 3px 0 line`) | all 11 |
| `AccentButton` / `NeutralButton` (press → remove offset, translateY +3) | 8 |
| `CoinPill` (۱٬۲۴۰ + amber dot) | 4 |
| `TintChip` | 6 |
| `AvatarTile` (32–64px rounded-square initial) | 5 |
| `SectionHeader` | 4 |
| `StreakStrip` (7–8 day chips) | ZHome, ZDailyBefore, ZDailyAfter |

### 2.4 Stage 1 — done

Landed: `core/theme/{app_tokens,app_typography,app_spacing,app_elevation,app_motion,app_theme,theme_cubit}.dart`, vendored Vazirmatn (400/500/600/700/800/900, `assets/fonts/`, declared in `pubspec.yaml`), `core/utils/persian_digits.dart`, all eight shared widgets in `core/widgets/`, and `ZBottomNav` wired into `_MainShell` (`core/router/app_router.dart`) with Persian labels (خانه/جدول/دوستان/من) — Material icons stand in for the canvas's bespoke square glyphs, which aren't available as assets.

`AppColors`/`AppTheme.dark` (the legacy flat palette) are kept byte-identical and still drive all 11 unmigrated screens directly — they don't read `Theme.of(context)`, so a straight removal would have broken every screen before its redesign stage. `AppTheme.dark` now also carries `fontFamily: 'Vazirmatn'` and the `ZColors.dark` extension, so the global font swap applies immediately everywhere and new `context.z`-based widgets (bottom nav, shared widgets) resolve correctly. `ThemeCubit` defaults to `ThemeMode.dark` and isn't yet exposed as a UI toggle (that lands with ZProfile in Stage 5) — switching to light now would look broken, since unmigrated screens ignore the active theme entirely.

**Verification:** `flutter analyze` — no issues. `flutter test` — all existing tests pass unchanged. Could not visually verify on a running app in this sandbox: web fails (Drift/sqlite3 has no WASM setup for this project's web target — pre-existing, unrelated to this change), iOS simulator fails during Xcode's Swift Package Manager resolution (Firebase binary CDN 404s — pre-existing, unrelated), and the Android emulator fails to boot in this sandbox. Visually confirm the new bottom nav and font on a real device/CI before starting Stage 2.

---

## 3. Stage 2 — Core loop

| Screen | Reuses | New |
|---|---|---|
| **ZHome** ← `features/home/view/home_screen.dart` (545 ln) | `_StreakBadge`, `_DailyChallengeButton`, `_ResumeCard`, `_GuestBanner`, `_QuickPlayCard` logic + nav wiring | Wordmark (5 rotated letter tiles), streak strip, indigo daily hero, 2×2 mode grid, weekly-rank teaser row |
| **ZSolo** ← `features/game/view/game_screen.dart` `_SoloHeader` + `_ActiveGameScreen` | `GameBloc` contract unchanged; `word_input.dart` logic | **New chain renderer** — vertical spine rail (2px line), tiles stepping 26→34px and opacity .4→1 down the list, stat strip (طول زنجیر / رکورد / جان) |
| **ZPlay** ← same screen, AI mode | Same bloc; `_PowerupRow` / `_PowerupButton` logic | **Second chain renderer** — chat-style alternating bubbles: opponent = `surface` + border on the start side, you = inverted `inkSurface` on the end side |
| **ZOver** ← `_GameOverScreen` (`game_screen.dart:781`) | `GameOver` state, share + continue actions | Full-bleed `inkSurface` hero band with 28px bottom radius, tumbling letter tiles, score card, chain-tail chips |

**Structural note:** today one `WordChainList` serves both solo and AI. The design wants **two distinct renderers**. Keep `WordChainList` as the shared scroll / auto-scroll shell and give it two presentation strategies rather than duplicating the controller logic (`features/game/view/widgets/word_chain_list.dart`).

### 3.1 Stage 2 — ZHome, ZSolo, ZPlay, ZOver all landed

Landed: `home_screen.dart` rewritten against `context.z` tokens — wordmark (5 rotated `LetterTile`s, rectangular 38×48 variant), streak card (`StreakStrip` rewritten to render real trailing-7-day weekday letters computed from `StatsDao`'s `dailyStreak`/`lastPlayedDate`, replacing the earlier checkmark-based guess now that the canvas was confirmed), indigo daily-challenge hero (real seed letter + backend `todaysBest` + a locally-computed hours-to-next-midnight-UTC countdown, best-effort network fetch with graceful fallback), 2×2 mode grid (تک‌نفره / حریف هوشمند / رویارویی آنلاین, same nav destinations as the old `_QuickPlayCard`s), and a weekly-rank teaser row (real `playerRank` from `LeaderboardRepository`). `_ResumeCard` and `_GuestBanner` kept their exact trigger conditions, restyled onto `SolidCard`. The mode-select and difficulty bottom sheets were also restyled onto tokens (not in the canvas, but shown directly from ZHome — leaving them on the legacy dark-only `AppColors` would break under light mode).

Widget API additions made to support this (all backward compatible — neither widget had any other call site yet): `LetterTile` gained optional `height`/`radius`/`fontSize` overrides for the wordmark's non-square tiles; `SolidCard` gained `elevated` (the streak card has no offset shadow in the confirmed design, unlike every other card).

The two top-right icon buttons in the canvas (settings-like square, notification-like circle) have no defined behavior in the mock. The first is temporarily wired to `ThemeCubit.toggle()` so light/dark can actually be checked on-device before ZProfile ships the real حالت شب switch in Stage 5 — flagged here so it isn't mistaken for a deliberate final placement; replace when ZProfile lands.

**Verification:** `dart analyze` and `flutter test` clean. Actually launched on an iOS 26 simulator (`flutter run`) — first launch hit a real bug (`Row(crossAxisAlignment: stretch)` inside the unbounded-height scroll column threw `BoxConstraints forces an infinite height` and silently blanked the entire body below the top bar; fixed by wrapping in `IntrinsicHeight`). Confirmed via on-device screenshots, both themes, including a temporary data-injection pass (reverted before commit) to exercise the streak card and daily hero, which a fresh guest session doesn't otherwise populate.

**Entry-flow fix (predates the ZSolo rebuild):** `home_screen.dart`'s تک‌نفره card used to open a bottom sheet asking Classic vs. زمان‌دار before every solo game. Tapping تک‌نفره now goes straight into Classic (`_startSolo` pushes `/game` directly, no sheet); زمان‌دار moved to a small indigo-colored tappable segment inline in ZSolo's own header subtitle ("⏱ حالت زمان‌دار" / "🎯 حالت کلاسیک" to switch back), which restarts the match in the other mode immediately if no words have been played yet, or behind a confirm dialog if the chain is non-empty. `_showModeSheet` is unchanged and still used for the AI-difficulty flow (`_startVsAi`), which wasn't in scope for this fix.

> **2026-10-03:** Time Attack was removed from the whole app, so the inline زمان‌دار/کلاسیک toggle described above no longer exists — ZSolo/ZPlay headers are plain subtitles and there is no mode switch.

**ZSolo** ← new `features/game/view/z_solo_screen.dart`. Vertical spine chain renderer: each row is a `LetterTile` (accent cycling indigo→teal→amber→coral by index) + word + `"index · +score"` meta, opacity/size ramped by distance from the most recent word (`_rampSizes`/`_rampFonts`/`_rampOpacity`, floor at the oldest step for long chains) with the spine line rendered as small per-gap segments (not one absolutely-positioned line — the canvas's continuous line is always occluded by the tiles anyway, so per-gap segments reproduce it exactly without fighting `ListView`'s scroll extent). The most recent word gets the raised/embossed tile + a `"+score · تازه"` tint chip. Stat strip: طول زنجیر (`wordChain.length`), رکورد تو (`StatsDao.bestMatchStreak`, fetched once in `initState`), and either lives pips (classic) or remaining match time (time_attack, third tile swaps since lives don't deplete outside classic — see Lives below).

**ZPlay** ← new `features/game/view/z_play_screen.dart`. Chat-bubble renderer: opponent bubbles (`surface` + border, aligned to the RTL start/right side) always show the difficulty label; "you" bubbles (`inkSurface` fill, aligned end/left) only show a "تو · +score" label on the most recent one, matching the canvas exactly. A real bug caught before it shipped: `wordScores` only ever accumulates the player's *own* words (see `GameBloc._onWordSubmitted`), so it isn't parallel to `wordChain` once the AI's interspersed words are counted — a bubble's score has to be looked up by a separate "my move" counter, not by chain index (`z_play_screen.dart`'s `_BubbleChain.build` tracks `myMoveIndex` for this). Footer has 4 power-up slots (hint/freeze/extra-time/shield) vs. ZSolo's 3 — freeze only applies with an opponent.

**ZOver** ← new `features/game/view/z_over_screen.dart`. Merges what used to be two separate screens (the `ContinuePrompt` overlay and `_GameOverScreen`) into the canvas's single design: `inkSurface` hero band (inverts to cream in dark mode, by design — see the token sheet's note on `inkSurface`) with 3 decorative tumbling tiles, a score card, a near-miss bar ("N کلمهٔ دیگر تا شکستن رکوردت مانده بود") or a new-record banner (mutually exclusive, both driven by `StatsDao.bestMatchStreak` vs. `chainLength`), chain-tail chips, then either the continue actions (ad/coins/share, only while `canContinue && !isSaved && continueTimeRemaining > 0`) or just share+home. Reused for both solo and vs-AI game-overs; **routes only when `state.opponentType != null`** — true multiplayer's WS-driven `GameOver` never sets that field (see `_handleWsLossEvent`/`_handleWsGameOver` in `game_bloc.dart`), so it's the correct discriminator (the existing `GameOver.isMultiplayer` getter was the wrong one to reuse here — despite its name it's also `true` for vs-AI once `opponentScore > 0`). Multiplayer keeps the legacy `ContinuePrompt`/`_GameOverScreen` pair untouched (Stage 4). Daily-mode `GameOver`s are intercepted first and just show the existing saving-spinner, since ZDailyAfter (Stage 3) owns the real result screen. Continue price fixed at `GameConstants.continueCostCoins` (25), not the canvas's 50, per the decision already recorded above. `ShareService` gained a small `shareMatch({score, chainLength})` (the canvas's "اشتراک‌گذاری نتیجه" button) alongside the existing daily-only `shareDaily`.

**Lives (adopted per decision 1, scoped down from the plan):** implemented in `GameBloc` for **solo + classic mode only** (`GameConstants.soloLives = 2`) — not vs-AI (ZPlay's canvas has no lives strip at all, unlike ZSolo/ZVersus/ZDailyBefore) and not time_attack (existing early-finalize-on-any-mistake behavior for time_attack was left untouched rather than silently extended by the lives change — flagged as a pre-existing spec/code mismatch below, not fixed here). A mistake in solo/classic with lives remaining decrements `GameActive.livesRemaining` and keeps the match going (`GameState.lastMistakeReason` surfaces a transient "you lost a life" banner); the match only actually ends via the existing `_handleGameOver` path once lives hit 0. True multiplayer/AI lives (decision 1's full scope) are deferred to Stage 4.

**Long-word bonus (decision 4):** added to `GameBloc._calculateScore` only (words ≥ `GameConstants.longWordBonusMinLength` (7) double their score) — Flutter-side only, since solo/AI never touch the Go backend's scorer (per CLAUDE.md, solo/AI run entirely on-device). The Go backend scorer is unchanged; that's a separate, not-yet-scoped follow-up for when multiplayer picks up this bonus too.

**Small pre-existing gap fixed in passing:** `StatsDao.recordGameResult` never actually updated `bestMatchStreak` (it just carried the existing value forward unchanged) — meaning "your record" had no real data source. Added a `chainLength` parameter, now `max(existing, chainLength)`; `GameBloc._saveAndEmitFinal` passes `over.chainLength`.

**Flagged, not fixed (out of this stage's scope):**
- `GameBloc._onWordSubmitted`'s validation regex (`^[a-z]+$`) only accepts Latin lowercase letters, meaning as written it would reject every real Persian word before ever reaching `DictionaryService.isValid` — yet `DictionaryService` itself (and its test suite) is fully Persian/ZWNJ-aware. This looks like a leftover from an earlier English prototype of the bloc that was never updated when the dictionary went Persian; it's a Phase 5 (engine)/Phase 2 (game feature) concern, not a Phase 17 visual one, so it was left untouched and is called out here rather than silently patched.
- ~~Time Attack ends the match on the first mistake~~ — moot: Time Attack was removed entirely on 2026-10-03.
- ZPlay's ادامه‌"انجماد حریف" (freeze) power-up, like Extra Time and Shield, is rendered per the canvas but left as a disabled/inert placeholder (`enabled: false`), matching the current app's existing behavior for those three — the power-up inventory/spend system is Phase 16 territory and wasn't touched.

**Verification:** `flutter analyze` and `flutter test` clean throughout. Actually launched on the same iOS 26 simulator used for ZHome (`flutter run`), both themes, all three screens, via a temporary preview-harness route (`/_preview/:screen?theme=`) that rendered each screen directly off a hand-built `GameActive`/`GameOver` fixture through the real DI container — reverted before commit, `git diff` on `app_router.dart` confirmed clean. Caught and fixed two real bugs this way: the hint power-up's "؟" glyph had no indigo badge behind it (invisible white-on-cream) — now `ZHintIcon`; and `ZWordInput`'s `TextField` was silently inheriting the legacy dark theme's navy `filled` decoration through the ambient `InputDecorationTheme` — fixed with an explicit `filled: false`. A few things that looked like bugs at a glance turned out not to be on closer inspection (worth recording so they aren't re-litigated): the "‎+score · index" meta text's bidi ordering renders correctly once actually zoomed in; Vazirmatn's isolated-form "ه" glyph looks like a teardrop/almost-"۵" shape at small sizes but is byte-verified correct in every case checked.

---

## 4. Stage 3 — Daily Challenge — complete

`ZDailyBefore` / `ZDailyAfter` ← `features/daily/view/daily_screen.dart`, fully rewritten on tokens. `DailyCubit`/`DailyRepository` untouched, per plan.

**ZDailyBefore**: back header (weekday + numeric date, see below), indigo seed-letter hero (96×106, `ZTileSize.dailySeed`, built as a raw `Container` like `ZHome`'s `_DailyHero` rather than through `LetterTile` — the canvas's surface-bg/indigo-text combo doesn't match any of `LetterTile`'s accent variants), three-row rules card, streak card (reuses the shared `StreakStrip` widget rather than redrawing the canvas's plain bars, for one visual system app-wide), ink-filled primary CTA, "دیدن جدول امروز" secondary button routed to `/leaderboard` (flagged below — no per-day leaderboard view exists yet).

**ZDailyAfter**: teal result hero (chain length + rank + score — no fabricated percentile/total-player-count, see below), chain chips with longest-word highlight and «+N دیگر» overflow, streak card with "+۱ امروز" badge, live-ticking countdown to next-midnight-UTC (`Timer.periodic`, disposed), share button, "جدول امروز"/"بازی تک‌نفره" row, and the **retry button + comparison card preserved** — the canvas has no retry UI at all, but it's real spec'd functionality (`POST /daily/retry`, 25 coins) that a visual redesign shouldn't silently drop, so it's kept and restyled rather than removed.

**Real-data-only policy**: the canvas shows several stats the API doesn't provide — ZDailyBefore's "۸٬۲۳۰ نفر امروز بازی کردند · میانگین ۱۲ کلمه" (global player count / average words) and ZDailyAfter's "بهتر از ۷۸٪ بازیکن‌ها" (percentile). `DailyChallenge` has no such fields. Rather than fabricate numbers, these were replaced with real fields already available: `todaysBest` for the before-hero's subtitle, and `rank`/`score` (no percentile) for the after-hero. Flagging in case a backend field for this is wanted later.

**Calendar date**: the canvas shows a full Jalali calendar date ("شنبه ۱۶ شهریور ۱۴۰۵"). At the time this stage was written, the app had no Jalali calendar conversion anywhere, so the Persian weekday name plus the real Gregorian day/month in Persian digits was substituted instead ("پنجشنبه ۱۰/۰۹"). **Update**: a later commit (`9e6db14`, pre-Stage-4) added the `shamsi_date` package app-wide, and `daily_screen.dart`'s header now does a real `Jalali.fromDateTime()` conversion, matching the canvas's full Jalali date (e.g. "پنجشنبه ۱۶ شهریور"). The Gregorian-substitute described above is superseded.

**Lives extended to Daily** (per user decision, matching the original conflict-table scope of ZSolo/ZVersus/ZDailyBefore): `GameBloc._onWordSubmitted`'s and the timeout handler's lives-gate now also cover `mode == 'daily'` (previously `classic`-only), so a Daily attempt costs a life on a mistake instead of ending instantly, using the same `GameConstants.soloLives` (2, not the canvas's literal "سه جان"/3 — kept consistent with the already-adopted 2-life decision). Daily's separate `dailyMaxWords` (20-word) cap is untouched. `ZSoloActiveScreen`'s header (already the actual Daily gameplay screen, since `game_screen.dart` routes any `opponentType == 'solo'` match there regardless of mode) now shows "چالش روزانه" instead of "تک‌نفره" and hides the زمان‌دار mode-switch toggle for `mode == 'daily'` — that toggle would have silently abandoned the tracked daily attempt and restarted as a fresh time_attack solo match, a real bug that predates this stage but was only surfaced by building Daily out properly.

**Bugs fixed before starting this stage** (reported and user-approved, not part of the visual work):
1. `_startVsAi`'s difficulty sheet was chaining into the legacy classic/زمان‌دار mode sheet right after (`home_screen.dart`, same leftover-sheet pattern as the earlier `_startSolo` fix). Now goes straight to a classic vs-AI match; `_showModeSheet` (now unused) removed. Side effect: there's currently no UI path to start Time Attack vs AI (ZPlay has no inline mode toggle, unlike ZSolo) — flagged, not silently fixed.
2. `GameBloc._onWordSubmitted`'s character-validation regex (`^[a-z]+$`, Latin-only) was rejecting every real Persian word in solo/AI play before it ever reached `DictionaryService.isValid` — a total block on core gameplay. Same bug also existed in `tutorial_screen.dart`. Both fixed to use a new `DictionaryService.hasValidChars()` (extracted from `isValid`'s own correct Persian-character check) instead of duplicating the character-class regex by hand.

**Verification**: `flutter analyze` and `flutter test` clean throughout. Verified interactively on the iOS 26 simulator via a temporary preview harness (`DailyPreviewScreen` in `daily_screen.dart` + a `/_preview/daily/:variant?theme=` route in `app_router.dart`, `initialLocation` pointed at it for a cold-start screenshot instead of live taps — this session had no working tap/type automation into the simulator, see below) — both screens, both themes, via `xcrun simctl io ... screenshot`. Caught and fixed one real bug this way: the chain-chip highlight was computed as the longest word across the *entire* chain, which frequently fell inside the "+N دیگر" overflow and never appeared — fixed to compute over the visible chips only. Harness fully reverted before commit (`git diff` on `app_router.dart` empty).

**Simulator interaction gap**: this session could not drive touch/keyboard input into the iOS simulator (no `cliclick`/`idb` installed, and AppleScript/System Events lacked accessibility permission) — screenshots and the preview-harness technique substituted for live tap-through verification. Worth fixing the environment (grant accessibility access, or install `cliclick`) before the next session that needs on-device interaction testing, e.g. the actual word-submission flow.

---

## 5. Stage 4 — Multiplayer — complete, verified on-device 2026-09-17

`ZLobby` fully rewritten on tokens (`features/lobby/view/lobby_screen.dart`); `LobbyCubit`/`LobbyState`/`LobbyRepository` untouched. `ZVersus` is a new screen (`features/game/view/z_versus_screen.dart`), replacing the legacy `_ActiveGameScreen`/`_MultiplayerHeader`/`_TurnIndicator`/`_NextLetterBar`/`_PowerupRow` block in `game_screen.dart` (now deleted — confirmed unreferenced elsewhere before removing) the same way ZSolo/ZPlay replaced their legacy counterparts in Stage 2. `game_screen.dart` now wraps `ZVersusActiveScreen` in the pre-existing `_OpponentContinueOverlay`/`_DisconnectedBanner` Stack rather than the screen owning it, so those two overlays (and the legacy English `ContinuePrompt`/`_GameOverScreen` pair for multiplayer game-over, per Stage 2's note) stay untouched and out of this stage's declared scope — REDESIGN_PLAN.md's own Stage 4 bullet list only ever named the active-game header/turn-banner/locked-input, not game-over or the overlays.

**ZVersus**: dual score header (real avatars via first-letter `LetterTile`, real `opponentUsername`/scores), a colored turn-banner pill (teal/`tintTeal` on my turn, coral/`tintCoral` on the opponent's, matching the canvas's coral-only frame) with an inline countdown bar, and the same chat-bubble shared-chain renderer as ZPlay (opponent bubbles bordered/left, mine on `inkSurface`/right) but keyed off the real `myPlayerId`/`opponentUsername` instead of AI-difficulty labels. Footer reuses `ZWordInput`'s existing `isOpponentThinking` lock (`enabled: state.isMyTurn`) — same component, no protocol change, so the copy reads "‌[نام] در حال فکر کردن…" rather than the canvas's generic "منتظر نوبت…"; close enough in meaning not to fork the shared widget for one string. Added a small back button (not in the canvas at all) since a live match has to stay leaveable — same category of "flag a real functional need beyond the canvas" as the VS-AI mode-toggle fix earlier this stage, not a style choice.

**Decision-table items resolved for this stage** (see §1):
- **Decision 1 (lives)** — **not extended to multiplayer, despite being in the "adopt" bucket.** `GameBloc`'s multiplayer path is 100% server-authoritative (`_onWordSubmitted` just forwards `submit_word` over WS; `word_rejected` is immediately followed by `loss_event`, confirmed by reading the handler — no grace period exists server-side). A lives chip here would either be decorative-and-misleading (shows "۲ جان", match still ends on the first mistake) or require real Go backend changes, which are out of this Flutter-only redesign phase. Omitted the canvas's "۲ جان" footer chip entirely rather than fake it — flagging for a real decision once/if the Go WS protocol grows a lives concept. `GameConstants.soloLives`/`GameActive.livesRemaining` untouched (still solo/daily-only, exactly as before).
- **Decision 2 (wager + turn-length picker)** — **revised 2026-10-03.** The pickers (game type, turn length, wager) are gone from ZLobby. In their place: an info row «ورودی ۲۰ سکه · جایزهٔ برنده ۴۰ سکه» backed by a real entry-fee system (config `EntryFeeCoins`, mirrored `GameConstants.entryFeeCoins`). Fee is charged server-side when the second human joins, the winner receives 2× fee, a draw refunds both, AI-fallback matches are free, and `match_cancelled` aborts a match if someone can no longer pay. ZOver shows the net coin change.
- **Decision 3 (best-of-5 rounds)** — rendered as a static "دست ۱ از ۵" (new `GameConstants.multiplayerRoundsTotal = 5`), never incremented — no round-tracking WS event exists. Placeholder per the decision, not silently dropped. **Update: the placeholder was later removed from ZVersus (and `multiplayerRoundsTotal` deleted).**
- **Referral/invite (decision 6, ZLobby)** — the canvas's room-code invite card was built (create-room/join-by-code, backend + UI) and then **removed on 2026-10-03** by product decision. The lobby keeps only the real friends list whose «دعوت» sends a friend challenge.
- **Typing indicator** — per the decision table, deliberately **not built** (needs a new WS event; turn banner ships without it, exactly as decided).

**Real-data-only policy, again**: the canvas's "حریف‌های اخیر" list (fabricated per-opponent win/loss records) and "۳٬۴۰۱ آنلاین" badge on the Find-Match button have no backing endpoint. Dropped the online-count badge outright; replaced the recent-opponents list with a "دوستان" card backed by the real `FriendsRepository.fetchFriends()` (real username + real weekly score, no fabricated record), and wired its "دعوت" button to the **real** `POST /challenges` call (`FriendsRepository.sendChallenge`) instead of a fake room-code join — arguably more useful than the canvas's non-functional version, since Friends/Challenges (Phases 11/12/14) are already fully built. A small "نوع بازی" (classic/زمان‌دار) toggle was added above the decorative pickers — not in the canvas at all — because the canvas drops the classic/time-attack choice entirely in favor of the turn-length picker, and silently losing the ability to queue for multiplayer Time Attack would repeat the exact regression class just fixed for VS-AI earlier this stage.

**Follow-up backend work (confirmed out of scope, not faked client-side)** — re-audited 2026-09-17: `backend/` has no round-tracking concept (a wager/entry-fee system has since been built, 2026-10-03) anywhere (checked the WS protocol, `internal/service`, and migrations). Building either further requires real Go work, not more Flutter:
1. ~~**Wager**~~ — done 2026-10-03 as a fixed entry fee (no wager field on `POST /match/queue`; see Decision 2). Coin-economy entry added to CLAUDE.md.
2. **Best-of-5 rounds** — new WS events (`round_won`/`round_transition` or similar), server-side round state in the match/game service, and a match-level (not chain-level) winner rule. Today the server only knows a single shared chain that ends on the first mistake.

Per the no-fake-mechanics rule already applied to multiplayer lives (decision 1 above), neither was built as client-only fake state — both stay the cosmetic pickers/placeholder described above until this backend work happens.

**Verification (2026-09-17)**: `flutter analyze` clean throughout. Verified interactively on-device (iOS 26 simulator, real backend + Postgres + Redis running locally, real WS multiplayer match against the AI-fallback opponent — dark theme; light theme not independently re-tapped this pass, but both screens are 100% `context.z` token-driven with zero hardcoded colors, the same pattern already confirmed in both themes for Stages 1–3, so risk is low). This pass caught and fixed real, previously-hidden bugs that static analysis and the earlier code-only pass had missed — multiplayer was **completely non-functional end-to-end** before these fixes:
1. **`POST /match/queue` client timeout** (`lobby_repository.dart`) — the endpoint deliberately long-polls up to `AIFallbackWaitSec+5` (35s) server-side, but the app-wide Dio client's `receiveTimeout` was 10s, so every non-instant match failed client-side before the server could ever respond. Fixed with a per-request 40s timeout override, scoped to this one call.
2. **Match-found signal never reached the client** (`lobby_cubit.dart`) — `joinQueue`'s 200 response already contains the resolved `room_id`/`is_ai` (the long-poll's whole point), but the repository discarded the body and `LobbyCubit` waited only on an FCM push notification to learn the match had started — a channel not configured for local/simulator use. Fixed by parsing the response into a `MatchQueueResult` and emitting `LobbyMatchFound` directly from it (the push listener stays as a documented backup for the app-backgrounded case).
3. **`/api/v1/ws/game/:roomID` mounted behind header-only `RequireAuth`** (`backend/cmd/server/main.go`) — `ServeWS` was written to self-authenticate via the `?token=` query param (its own doc comment says so — a WS handshake can't carry an `Authorization` header), but it was routed inside the `protected` group, so the header-checking middleware rejected every real WS connection attempt with 401 before `ServeWS` ever ran. Moved the route out of `protected`.
4. **`_handleWsGameStart` crashed on every `game_start` event** (`game_bloc.dart`) — cast `gameState['players']` (a plain `List<String>` of user IDs per `gameStartState` in `room.go`) as `List<Map<String, dynamic>>`, throwing `type 'String' is not a subtype of type 'Map<String, dynamic>'` and leaving `GameBloc` stuck in `GameLoading` (a blank screen) forever. Also read a `current_player` key that doesn't exist — the real field is `current_turn` — so `isMyTurn` always fell back to `true`. Fixed to match the real wire shape; `opponentUsername` is left `null` (the server sends no username over WS at all — `ZVersusActiveScreen` already has a generic "حریف" fallback for this).
5. **Next-letter hint corrupted for every word** (`backend/internal/ws/room.go`, both `processSubmitWord` and `sendCurrentState`) — computed as `word[len(word)-1]`, the last *byte* of a UTF-8 string, not the last rune; every Persian word is multi-byte per letter, so this always produced a garbage/mojibake character (rendered as "§" in the client) instead of the real required starting letter. Fixed by exporting `engine.lastLetter` as `engine.LastLetter` (already correct — ZWNJ-stripped, rune-safe) and calling it from both sites, guaranteeing the hint always matches what `engine.ValidateMove` will actually accept.

All five are real client/backend contract bugs caught only by an actual live match, exactly the class of bug this project's testing convention (CLAUDE.md/session notes) already flags on-device verification for. None are new backend feature work — all are fixes to code from already-"Complete" phases (7–9) that never worked as designed. `go build`/`go vet`/`flutter analyze` clean after all fixes; `go test ./internal/engine/... ./internal/ws/...` still has pre-existing failures unrelated to this session's changes (confirmed via `git stash` — see below), not introduced by any of the above.

**Flagged, not fixed (out of this session's scope)**:
- `ws: UpdatePlayerScore failed ... invalid input syntax for type uuid` — the AI opponent's synthetic user ID (`"ai:" + difficulty + ":" + roomID[:8]`, not a real UUID) gets written to a UUID column when persisting final scores on match end/disconnect. Pre-existing (Phase 9), reproduces on every AI match's game-end path; a real bug but a persistence/stats-schema fix, not a Stage 4 visual-redesign item.
- `go test ./internal/ws/...` has 3 pre-existing failures (`TestRoomWordAccepted`, `TestRoomWordRejectedWrongLetter`, `TestRoomAlternatingTurns`) and `go test ./internal/engine/...` has 4 (`TestSelectAIWord_*`, all "expected a word, got empty string") — confirmed via `git stash` to already fail identically before any change made this session. Both contradict CLAUDE.md's ≥70%-coverage/passing-tests convention for "Complete" phases; worth a dedicated follow-up session, not investigated further here.
- Wager (§1 decision 2) and best-of-5 round tracking (§1 decision 3) remain the documented cosmetic placeholders — confirmed again this session that neither has any backend support to wire to (no wager field/coin-economy entry anywhere in `backend/`, no round concept in the WS protocol or Go service layer). Per the same no-fake-mechanics rule already applied to multiplayer lives, neither was built as client-only fake state.
  - _Update 2026-10-03:_ the wager part is superseded — a real fixed entry fee now exists (see Decision 2). Best-of-5 remains a placeholder.

### Stage 4 (continued) — ZLogin (ZPhone), ZOtpVerify (ZOtp)

- Screens: 3l (Login), 3m (OTP Verify) — canvas files `ZPhone.dc.html`/`ZOtp.dc.html`. Superseded the email/password `ZLogin`/`ZRegister` pair this section originally described: the design moved to phone number + 4-digit OTP (no password at all), so email/password auth was **fully removed**, not incrementally wired — `backend/internal/service/auth.go`, `repository/user.go`, `handler/auth.go` all rewritten; migration `003_phone_auth_referral` drops `email`/`password_hash` and adds `phone`, `otp_*`, `referral_code`, `referred_by`, `phone_verified_at`.
- Implementation checklist:
  - [x] `ZLoginScreen` (`features/auth/view/z_login_screen.dart`) — phone input (grouped Persian digits, LTR), carrier auto-detect line, terms checkbox gating submit, `POST /auth/send-otp`, referral teaser card
  - [x] `ZOtpVerifyScreen` (`features/auth/view/z_otp_verify_screen.dart`) — 4-box OTP row (display-only boxes driven by a hidden TextField and the system number keyboard; the canvas's hand-drawn keypad was dropped (`otp_keypad.dart` deleted)), "ویرایش" pops back to ZLogin preserving the entered phone (route push, not go), server-driven resend countdown (voice-call fallback later removed), `POST /auth/verify-otp` incl. optional referral code
  - [x] Error states mapped to Persian messages client-side from the server's machine-readable codes (`invalid_code`, `code_expired`, `too_many_attempts`, etc.) — see `_mapOtpError`/`_mapSendError` in the two screens
  - [x] Loading/submit state on both screens
  - [x] Success flow: both new- and existing-user verify-otp success → `context.go(returnPath ?? '/home')`
  - [x] Real on-device/simulator interactive verification (taps, keypad, countdown, RTL + Persian-digit rendering, both referral entry points) — done by AmirAbbas on-device using the `1111` dev/test OTP bypass code (no Kavenegar account purchased yet); both referral entry points exercised, no bugs found. Real SMS delivery via Kavenegar is still unverified end-to-end pending account purchase — the OTP flow itself is confirmed working via the bypass code, not via an actual sent SMS.

**Referral system** (decision 6, §1): built alongside this screen pair since the referral teaser card lives on ZLogin itself. See the updated §1 decision-table row and `CLAUDE.md`'s new "Referral Code System" section for the full design (two entry points sharing one `ReferralBottomSheet` widget, +100/+50 coins, no referrer-side reward yet).

**Verification note**: backend (`go build`, `go vet`, `go test`) is clean, including new nil-DB unit tests for the OTP/referral paths. `flutter analyze` and `flutter test` are clean across the whole client. The Postgres migration was **not** verified against a live database this session (no Docker daemon available in the environment) — run it against a real Postgres before shipping. **Update**: both screens have since had a live on-device tap-through by AmirAbbas — phone entry, custom keypad, OTP verify (via the `1111` dev bypass code, since no Kavenegar account is purchased yet), resend countdown, and both referral entry points (ZLogin teaser + Profile → Settings) were all exercised with no bugs found. Real SMS send/deliver through Kavenegar itself remains unverified end-to-end — that's blocked on purchasing a Kavenegar account, not a code gap.

---

## 6. Stage 5 — Secondary screens — complete, verified on-device 2026-09-28

- **ZBoard** → `features/leaderboard/view/z_board_screen.dart` (replaces `leaderboard_screen.dart`) — podium pedestals, rank rows, sticky self-row on `inkSurface`. **Ships 2 of the canvas's 4 tabs** (این هفته / دوستان): «امروز» and «همیشه» have no data source (the backend only keeps the weekly Redis set), so they were dropped rather than faked. Restoring them is scheduled in PLAN.md Phase 18.
- **ZProfile** → `features/profile/view/z_profile_screen.dart` (replaces `profile_screen.dart`) — stat grid, `_LevelCard`/`_BadgesCard` as honest placeholders (level 1, no fabricated badges; decision 5), settings list with the real حالت شب switch and the Settings → referral entry.
- **ZFriends** → `features/friends/view/z_friends_screen.dart` (replaces `friends_screen.dart`) — requests / friends sections on the existing `FriendsCubit`.
- **Tutorial dropped** in the same commit (`tutorial_screen.dart`, `/tutorial` route, first-launch redirect, Profile → Help). Confirmed by the user as a product decision — not to be rebuilt.

**Follow-ups done 2026-09-28**: ZHome's top-right square was a temporary `ThemeCubit.toggle()` QA affordance; now that ZProfile has the real switch it opens `/profile` (settings) with a settings icon. `ThemeCubit` now defaults to `ThemeMode.system` (see Stage 6) and `toggle()` takes the on-screen `Brightness`, so ZProfile's switch reads correctly under a system default.

**Verification (2026-09-28, Android 16 emulator, real local backend, both themes)**: ZBoard (both tabs), ZFriends, ZProfile (incl. the حالت شب switch flipping the whole app live), ZHome, ZSolo and ZOver tapped through with real data. Fixed on the spot:
1. **ZHome weekly-rank row**: the three overlapping dots needed 66px but sat in a 46px box and overlapped the «جدول هفته» title. Widened, added a gap, and made the offset direction-aware (`PositionedDirectional`).
2. **ZProfile settings rows** rendered empty icon squares. They now carry Material icons (moon / speaker / bell), same stand-in approach as `ZBottomNav`.
3. **Solo matches never reached the server** (pre-existing, Phase 1/7): `SyncService` sent `word_chain` as the Drift JSON *string* while the API binds `[]string`, so every upload got 400. And since any non-409 error aborted the loop, the oldest row blocked all later ones forever. It also uploaded still-`active` matches with no `ended_at`. Fixed: decode the chain, skip active matches, and skip (log) a row rejected with 4xx instead of aborting. Verified: the 6 backlogged matches uploaded, and ZProfile's «بازی‌شده» went 0 → 6.
4. **Daily streak never advanced from solo games** (pre-existing, Phase 7/10): `StatsRepository.IncrementMatchStats` wrote `last_played_date` *before* `StreakService.RecordGamePlayed` ran, so the streak service always saw "already played today". `IncrementMatchStats` no longer touches that column. Verified: after backdating the dev account's last-played date by one day, a new solo game moved `daily_streak` 0 → 1.

Known cosmetic-only elements (scheduled in PLAN.md Phase 18): «صدا و لرزش» / «یادآور چالش روزانه» rows, ZHome's bell.

---

## 7. Stage 6 — Undesigned screens — code complete 2026-09-28; needs a live multiplayer match to verify

Tutorial is out of scope (dropped, see Stage 5). Login/register were superseded by ZLogin/ZOtp in Stage 4. What remained were the multiplayer-only legacy screens:

- **Multiplayer game-over + continue prompt → `ZOverScreen`.** Rather than design a new screen, ZOver now serves every match type. `game_screen.dart` routes every `GameOver` to it. ZOver identifies true multiplayer by `opponentType == null` and adds an «امتیاز حریف» line for duels. It hides «رکورد تو» (a solo chain-length record) in multiplayer.
- **New `GameOver.iWon`** (set in `_handleWsGameOver` from `winner == myPlayerId`). The legacy screen guessed the winner from scores (`score > opponentScore`), which is wrong whenever the higher scorer loses by making the mistake. `iWon` is null while my own continue window is open, so the hero reads «زنجیر پاره شد!» until the server decides.
- **Bug fixed in passing**: after a forfeit, the bloc is already in `GameOver` when the server's `game_over` arrives. `_handleWsGameOver` then rebuilt the result from a null `GameActive`, giving an empty chain and 0 length. It now falls back to the previous `GameOver`'s chain/mode/score.
- `_OpponentContinueOverlay` and `_DisconnectedBanner` restyled on tokens, in Persian. The scrim is `paper` at 88% so it works in both themes. The grace period reads `GameConstants.reconnectGraceSec` (new, 30).
- `friend_challenge_sheet.dart` restyled on tokens, in Persian. Timer copy is read from `GameConstants`, and it closes via `context.pop()`. **Replaced 2026-10-17 by `friend_challenge_dialog.dart` (see § Friend challenge dialog).**
- Loading/error states in `game_screen.dart` restyled. The error state uses `NeutralButton`.
- **Deleted as dead code**: `continue_prompt.dart`, `word_chain_list.dart`, `timer_bar.dart`, `word_input.dart` (no remaining references; the Z screens use `z_game_shared.dart`).
- **Legacy palette removed**: `AppColors` and the hand-built `AppTheme.dark` are gone. `AppTheme.light`/`dark` are now both built from `ZColors` by one `_build()`. `ThemeCubit` defaults to `ThemeMode.system` now that every screen honours both themes (the design is light-first).
- ZVersus's timer track used `Colors.black` at 8%, invisible on dark tints. It is now the accent colour at 18%.

---

## 8. Stage 7 — Tests — partially complete 2026-09-28

- **No goldens existed** (the plan's "re-baseline `WordChainList`/`TimerBar`" was moot, and both widgets are now deleted).
- Added `test/core/widgets/shared_widgets_golden_test.dart`: a light + dark golden of every shared widget (Vazirmatn loaded via `test/helpers/z_test_app.dart`). `StreakStrip` is excluded because it depends on `DateTime.now()`. Goldens were generated on Linux; regenerate with `flutter test --update-goldens` if rendering differs on macOS CI.
- Added `test/core/theme/token_coverage_test.dart`: fails on `Color(0x`, named `Colors.*` hues, or `AppColors.` in `lib/features`, `lib/core/widgets`, `lib/core/router`.
- Added `test/features/game/z_over_screen_test.dart` covering the multiplayer win/loss/continue variants and solo/AI regressions.
- **Remaining**: goldens for the ZSolo/ZPlay chain renderers and widget tests for the other Z screens' primary states.

---

## 9. Open decisions — resolved

Both prior open items are settled (see §1 Decisions and the header note above): the six conflicts are decided, and Phase 17 is recorded in CLAUDE.md and PLAN.md.


---

## Post-Stage-7 changes (2026-10-03) — ZLobby simplification, Time Attack removal, entry fee

- **Time Attack removed from the entire app** (Flutter + Go): Classic is the only match variant besides Daily. Gone: lobby game-type picker, solo/vs-AI mode toggles, `timeAttack*` constants, `matchTimeRemaining`, the `time_limit` game-over reason, the room's 90s match timer (`handleMatchTimeout`), and `time_attack` from queue/WS/challenge validation. Friend-challenge sheet is now a confirmation sheet that always sends Classic. Existing DB rows with `mode = 'time_attack'` are left as-is (no migration).
- **ZLobby coin pill showed ۰** — it read `ProfileRepository.fetchStats().coins`, a key the backend never sends (same bug previously fixed on Home/Profile). It now reads the live balance from `AuthCubit`.
- **Entry fee replaces the wager picker** — fixed 20 coins per human player, winner takes the 40-coin pot, draw refunds both, free vs the AI fallback. Server pre-checks balance on queue join and challenge create/accept (`402 insufficient_coins`); the authoritative charge happens at match start. WS additions: `game_start.state.entry_fee`, `game_over.payout`, `match_cancelled { reason: "insufficient_coins", player_id }`. Client: `GameBloc.onCoinsChanged` keeps `AuthCubit` in sync; `GameOver.entryFee/coinsNet` feed a «سکه» line on ZOver. Unstarted rooms now free a leaving player's seat so nobody is charged alongside an absent player.
- **Room-code invite removed** (was built the same day, then removed by product decision): no `POST /rooms`, `/rooms/join`, hub code map, or lobby UI. Friend challenges are the only way to play a specific friend.
- **Known gap:** when a challenged friend can't afford the fee on accept, the client shows its generic error message (the server returns `402 insufficient_coins`).

---

## ZHome v2 — mascot-led home (2026-10-16) — code complete; light + dark verified on the iOS simulator

**Source:** canvas turn 6 (`Zanjir.dc.html` frames **6a light / 6b dark**, "A · mascot-led"), component `ZHome3A.dc.html`. Variant B (`ZHome4`, world-led), `ZHome3` and the old 5a `ZHome2` are ignored. ZHome (v1, Stage 2) is fully replaced.

**Code (ZHome only):** `features/home/view/home_screen.dart` is now just the loader (stats / daily / level fetch, navigation, difficulty sheet); everything visual lives in `features/home/view/widgets/`:
`home_view.dart` (layout + `HomeViewData`), `home_scene_background.dart`, `home_hud.dart`, `home_logo.dart`, `home_hero.dart`, **`home_hero_chain.dart`** (self-contained: `words` + `mascotMood` + `animate`), **`home_mascot.dart`** (self-contained: `mood` + `animate`, exposes `size` / `gripPoint` — a Rive artboard can replace both without touching ZHome), `home_daily_ribbon.dart`, `home_chest.dart`, `home_progress_path.dart`, `home_buttons.dart`, `home_nav.dart`, `home_icons.dart` (token-coloured inline SVGs), `home_motion.dart` (`HomeClock` ticker + loop curves; reduced-motion aware), `chunky.dart` (`ChunkyBox` — outline + hi highlight + solid depth edge).
The hero is authored on a 396×352 canvas and scaled to the screen (0.8–1.1×); the page scrolls on very short phones.

**New tokens (added, nothing overwritten):** `core/theme/app_scene_tokens.dart` → `ZScene` ThemeExtension (`context.zs`): `outline, hi, sky1-3, blobIndigo, blobTeal, ring, particle, particleNear, vignette, tile, tileDeep, indigoInk, tealInk, coralInk, chain, glow, rays, track`, light + dark values from frames 6a/6b. `core/theme/app_game_metrics.dart` → `ZGame` (outline 3/2.5, depth 3/5/6/8, pressed edge 2, HUD 36/48/44, Play 76·r26, online 58·r22, logo 60·stroke 7·shadow 6, hero canvas, nav tile 60×48 lift 30, min label 11.5) and `ZGameMotion` (all loop periods). `AppTheme._build` registers `ZScene`.

**Design issues fixed rather than copied:** XP label is rendered LTR as current / target («۳۲۰ / ۵۰۰»; the canvas's RTL layout flipped it) and its text switches ink/onAmber over the empty/filled part of the bar (ink on amber was ~1.7:1 in dark); the ribbon's date chip uses `ink` on `surface` (canvas used `onAmber` — invisible in dark); all labels ≥ 11.5sp (canvas had 10px); settings button 44dp (canvas 40), whole coin pill is a 44dp tap target; milestone numbers, countdown and nav labels meet contrast in both themes.

**Real data:** coins (`AuthCubit`), streak (`StatsDao`), level/XP (`ProfileRepository.fetchStats` → `level`, `xpInLevel`, `xpForNext`; guests show level ۱ / ۰ of ۱٬۰۰۰), chest state + red dot + tag (`RewardsCubit.unclaimedCount > 0`; chest → `/rewards`), friends-tab badge (`MessagesCubit.count` = pending requests + challenges), ribbon date (Jalali, Iran time) + live countdown (`untilIranMidnight`, ticks every second), ribbon dot (daily not yet played), play → solo classic, «حریف هوشمند» → difficulty sheet, «رویارویی آنلاین» → lobby / login, ribbon → `/daily`.

**Placeholders / follow-ups (not real data):**
- «۳٬۴۰۱ نفر آنلاین» — no endpoint reports players online. Shown **in debug builds only** (`kDebugMode` in `home_screen.dart`, marked `PLACEHOLDER`); release shows the real line «با بازیکنان دیگر به رقابت بپرداز». Needs a backend count.
- Hero word chain (سیب → باران → نمک → کتاب → برف) is a static decorative sample (valid chain, all in `fa.txt`, unit-tested).
- Milestones ۱۳/۱۴/۱۵ are derived (`level + 1…3`); the chest/crown have no reward behind them yet. Level rewards need backend work.
- The two decorative avatar chips on the online button («م», «س») are not real players.
- Mascot moods `cheer` / `sad` exist but nothing sets them yet (always `idle`).
- Rive: `HomeHeroChain` + `HomeMascot` are the swap points ("home_hang" artboard in the canvas notes).

**Deliberate deviations from the canvas (flag for review):**
- **Nav:** resolved by the dock below — one shared bar on all four tabs (the earlier split of `HomeNav` on Home + flat `ZBottomNav` elsewhere is gone).
- **Removed from Home** (no slot in the canvas): the inbox (✉) and rewards (🎁) icons, the weekly-rank teaser, the streak-week card, the guest register banner. Rewards stay reachable via the chest; pending requests/challenges via the Friends tab (which already lists them) — `/messages` still exists but has no entry point from Home. The «ادامهٔ بازی» resume pill was kept (shown only while a solo/AI match is active) because losing it would orphan interrupted games.
- ZProfile's XP label has the same RTL number-flip (`'$a / $b'` in an RTL row) — not touched (out of scope).

**Verification:** `flutter analyze` clean; `flutter test` — new `test/features/home/home_view_test.dart` (chain validity + dictionary, formatting, no overflow at 320×568 / 360×640 / 393×852 / 430×932 in both themes, Play press/release, nav indices, chest tag, reduced-motion = no scheduled frames). Simulator run, light + dark, compared to the canvas frames — see the session report for the screenshot diff notes.

---

## Bottom dock — all four tabs (2026-10-16) — code complete; light + dark verified on the iOS simulator

**Source:** canvas turn 7, component `ZNav.dc.html` (light/dark token values from the 7aL/7aD rows and the 7p/7q component sheets). A floating rounded panel (3px outline, r24, solid 5px depth edge + outline ring) in the `--dock` plum (a dark slab in both themes), filled colourful glyphs, the selected tab a raised chunky tile in its own accent (home indigo · board amber · friends coral · me teal). Labels 14sp / 900.

**Code:** `core/widgets/z_bottom_nav.dart` (`ZBottomNav`, now the dock; `friendsBadge` param). `_MainShell` (`core/router/app_router.dart`) shows it on every tab, feeds the badge from `MessagesCubit.count`, and sets `extendBody` on the home tab so Home's sky scene runs under the floating dock. `HomeView` pads its content by `MediaQuery.paddingOf(context).bottom` (the dock height under `extendBody`). **Removed:** `home_nav.dart` (`HomeNav`), `HomeView.onTab`/`friendsBadge`, `HomeScreen._selectTab` and the now-pointless `MessagesCubit` builder in `HomeScreen`, the four nav glyphs of `HomeGlyph`. Tab behaviour unchanged (indices = `MainTab`, `goBranch` + `TabRefreshBus.notify`, re-tap = initial location).
Glyphs are the canvas SVG paths drawn with the existing `flutter_svg` (token-coloured inline SVG, same approach as `home_icons.dart`) — no new package, no CustomPainter needed.

**New tokens (added, nothing overwritten):** `ZScene` (`context.zs`): `dock`, `dockDeep`, `dockSheen`, `onDock`, `onDock60`, `onCoralSm` (light + dark). `ZGame`: `dockRadius 24, dockMarginH 12, dockMarginBottom 14, dockPaddingTop/H/Bottom 8/4/8, dockDepth 5, dockTabHeight 58, dockGlyph 32, dockGlyphSelected 30, dockGlyphTop 4, dockLabelHeight 18, dockLabelSize 14, dockTileWidth 62, dockTileHeight 50, dockTileRadius 17, dockTileTop -15, dockBadge 22`. (`ZGame.navTile*`/`navLift` from the old HomeNav are now unused — left in place.)

**Decisions / deviations:**
- **Floating margin on Home:** `extendBody` + bottom padding, so the scene continues behind the dock (verified: no paper-coloured strip, nothing hidden). The other tabs end above the dock; the strip under it is `paper`.
- On notched phones the bottom margin is `max(14, safeBottom − 12)` so the dock clears the home indicator.
- The raised tile pokes ~4px above the panel (canvas geometry: `margin-top:-30` in a flex-end box), so the dock reserves 4px above itself; no content is covered. Every tab was checked scrolled to its end (Profile's last row, «خروج از حساب», sits fully above the dock).
- The badge hides on the selected friends tile (as drawn in the canvas); capped at «۹۹+».
- Label colours on the dock meet contrast in both themes (`onDock60` on `dock` ≈ 8:1); selection is also carried by the raised tile + label weight/colour, not hue alone. Tap cells are 58dp tall; text scale is clamped to 1.2 inside the dock.
- Pressed: glyph dips 2px, a selected tile loses 3px of depth edge and sinks 3px (90ms, `ZGameMotion.press`); selection animates glyph/tile up over 200ms. Reduced motion → instant.

**Bugs caught by tests, not by the device run:** the badge `Container(alignment:)` expanded to fill the whole tab (the account on the simulator had no pending requests, so only the golden showed it).

**Tests:** new `test/core/widgets/z_bottom_nav_test.dart` (tab indices, RTL order, badge + cap, semantics, press, 44dp, no overflow 320/360/430 in both themes) and `z_bottom_nav_golden_test.dart` (light/dark × home/friends selected, with badge); `home_view_test.dart` now lays Home out with ~100dp dock padding at 320×568…430×932 and no longer tests the (removed) in-view nav. `shared_widgets_*` goldens regenerated — they were already failing on a clean checkout (1.05% diff, see CLAUDE.md) and the gallery's bottom nav changed.

**Follow-ups:** `ChunkyBox` (features/home) duplicates the dock's tile recipe — hoist it to `core/widgets` and reuse. The badge is only refreshed where `MessagesCubit.refresh()` is called (Home init/resume, Messages screen) — it can be stale after a request is handled on the Friends tab. A live check of the badge with real pending requests is still outstanding (verified via golden + widget tests only).

**Home gear button (follow-up, 2026-10-16):** the top-left button on Home used to `context.go('/profile')` (ZHome v2 placeholder); it is now the quick light/dark switch — `ThemeCubit.toggle(Theme.of(context).brightness)`, same cubit/persistence as ZProfile's حالت شب row (`home_screen.dart`; semantics label reuses that row's string). The glyph is unchanged (gear/sun). Covered by `test/core/theme/theme_cubit_test.dart`; on the simulator one tap flipped dark → light and stayed on Home (further top-of-screen taps from the click tool were flaky, so the light → dark direction is verified by the unit test only).

---

## ZSolo — "A · mascot-led" restyle (2026-10-16) — code complete; light + dark verified on the iOS simulator

**Source:** canvas turn 7, `ZSoloA.dc.html` (frames 7dL/7dD «تک‌نفره کلاسیک — spine»; 7eL/7eD «زمان‌دار (toggle)» is **not** built), `ZScene.dc.html` (`calm`), `zmotion.js`. Pushed outside the shell → no dock. **Daily Challenge reuses this screen** (`ZSoloActiveScreen`, `mode == 'daily'`).

**Code:** `features/game/view/z_solo_screen.dart` (layout only) + new reusable pieces in `features/game/view/widgets/`: `z_game_hud.dart` (`ZGameBackButton`, `ZScorePill`, `ZTimerRing`, `ZLivesChip`, `ZWordsChip`), `z_game_chain.dart` (`ZSpineChain`: bottom-anchored scrolling chain, word tiles, links, dashed next-word slot, earlier-words hint), `z_game_power.dart` (`ZChunkyPowerupTile`). Opt-in variants on the shared widgets (default = legacy look, ZPlay/ZVersus untouched): `ZPowerupBar(chunky:)`, `ZWordInput(chunky:)` in `z_game_shared.dart`. `HomeSceneBackground(calm:)` (Home unchanged; the diff is mostly re-indent). `ChunkyBox` now lives in `core/widgets/chunky.dart` (hoisted in its own commit). `ChunkyPressable` (home_buttons.dart) is imported from the home feature — hoist it with the next screen.

**New tokens (added only):** `ZScene.amberInk` (`#9A5C06` light / `#F7B44A` dark, canvas `--amberInk`); `ZGame.game*` metrics (back 44, score pill 50, timer ring 60/core 42, chip 36, heart 22×20, row tile 44/56, row index 30, points 44, link 14×28, input 66/r22, send 52×50, power tile 66/disc 32/badge 24).

**Real data:** score, word count, per-word points (`wordScores`), `livesRemaining`/`soloLives`, `turnTimeRemaining` of 15 s, record = `StatsDao.bestMatchStreak` (this *is* the longest chain — `StatsDao` stores `max(existing, chainLength)`, and Profile already calls it «بلندترین زنجیر» — so «رکورد N» next to «N کلمه» is accurate; no wording change), power-up counts / coin prices / guest hints / need-coins sheet (unchanged logic), mistake banner, daily subtitle (`dailyMaxWords`).

**Deliberate deviations from the canvas:**
- **No کلاسیک / زمان‌دار toggle** and no «۸ ثانیه · سقف ۹۰» subtitle — Time Attack was removed from the product; the subtitle shows the real «۱۵ ثانیه». Re-add only if the product brings timed mode back.
- **Input contract kept:** the player still types the whole word; the teal start-letter tile is a cue only (the canvas draws the letter pre-filled + «ردک»). Pre-filled-letter input is a follow-up (changes `WordSubmitted`/hint-word behaviour).
- **Chain is scrollable** (all words reachable), bottom-anchored, auto-follows the newest word. The «↑ n کلمهٔ قبلی» chip is a pinned hint (n = words before the last six), shown only at the newest word and only when the viewport is ≥ 300 dp (hidden with the keyboard up so it can't cover rows); words fade under the HUD.
- Daily subtitle shortened to «حداکثر ۲۰ کلمه» (was «روزی یک بار · حداکثر ۲۰ کلمه») so it fits beside the ring at 320 dp; below 350 dp the pill drops its subtitle and scales down.
- Entrance slide-ins (`data-e`) are not built; the newest word's drop-in, the next-word slot pulse and the urgent timer pulse are.

**Design defects fixed:** spent lives are drawn as empty hearts (canvas only shows full ones) with a semantic label; the timer ring pulses only at ≤ 5 s (canvas: always) and never with reduced motion; the coin price (real server behaviour) is the corner badge when none is owned (amber, text — not colour alone); the badge sits on the *end* corner via `PositionedDirectional` (canvas used physical `left`); `amberInk` was missing from the token set; points pills forced LTR; all labels ≥ 12 sp; back button 44 dp; semantics on back / timer / lives / send / power-ups / words; contrast of every ink-on-tile, chip and banner pairing asserted ≥ 4.5:1 in both themes (white on `teal` letter tile is the large-text 3:1 case). The scene stays fixed behind the keyboard (`resizeToAvoidBottomInset: false`, content pads itself).

**Placeholders / follow-ups:** none fake. Follow-ups: pre-filled start letter; timed mode if wanted; ~~`zShowEndGameDialog` (shared dialog) is still the legacy style~~ (done in the Dialogs session below); ZOver (next) — its «رکورد» line already uses the same stat; ~~hoist `ChunkyPressable`~~ (done, `25c4d92`).

**Tests:** new `test/features/game/z_solo_screen_test.dart` (states: empty / mid-game / long chain / daily / lives / mistake / power-ups / send dispatches `WordSubmitted` / back dialog; reduced motion schedules nothing; no overflow 320×568, 360×640, 393×852, 430×932 × light/dark with and without a long chain, plus 375×667 with a 260 dp keyboard; contrast table) and 3 goldens in `test/features/game/goldens/` (mid-game light/dark, daily light). `flutter analyze` clean; `flutter test` 108 pass (the previously failing shared-widgets goldens pass on this checkout).

**Simulator (iPhone 17 Pro, light + dark):** solo play end to end — empty chain, first word, 4-word and 8-word chains, a lost life + banner, game over → ZOver, the real Persian keyboard with the layout above it (chip hidden), hint → send, timer urgency. Not seen live: **Daily Challenge** (today's attempt was already used on the test account and a retry spends 25 real coins on production — covered by the widget test + golden instead), the guest variant (the simulator was signed in), a resumed game (initial rows don't drop in), 320×568 on a device. Note: the simulator talks to **production**; the hint runs spent coins (10 per use; Home showed 665 → 645 at its last refresh, so the real spend is likely higher) and the solo games synced matches/XP to the signed-in account.

---

## ZPlay — "A · mascot-led" restyle (2026-10-16) — code complete; light verified on the iOS simulator (partial), dark + full flow NOT verified live

**Source:** canvas turn 7, `ZPlayA.dc.html` (one 396×812 frame, tokens switch light/dark), shared pieces from `ZSoloA` / `ZScene`. Pushed outside the shell → no dock. Used only for **vs-AI** (`opponentType` `ai_*`); solo/daily stay on ZSolo, 1v1 on ZVersus.

**Code:** `features/game/view/z_play_screen.dart` (layout only: header + level/bonus chips + mapping of the shared chain to bubbles). New reusable pieces:
- `core/widgets/z_disc_avatar.dart` (`ZDiscAvatar.me` / `.robot`), `core/utils/avatar_initial.dart` (`avatarInitial(name)` — first letter, «ت» for guests / non-letters).
- `features/game/view/widgets/`: `z_game_bubbles.dart` (`ZBubbleChain`, `ZBubbleEntry`), `z_game_scaffold.dart` (`ZGameScaffold` = sky scene + keyboard padding, `ZGameFooter` = input + power-ups), `z_game_scroll.dart` (`ZChainScroller`: bottom-anchored scroller with fade + auto-follow, now also used by `ZSpineChain`), `z_game_word.dart` (`ZChainHue`/`zChainWordSpan` shared-letter colours, `ZPointsPill`, `ZDropIn`; extracted from `z_game_chain.dart`), `ZVersusPill` + `ZTimerRing(calm/paused)` in `z_game_hud.dart`, `ZNextLetterSlot` (extracted from the spine's `_NextSlot`).
- Opt-in extensions of existing widgets (legacy look is the default): `ChunkyBox.borderRadius`, `ZWordInput(chunky: true)` now has a chunky «در حال فکر کردن…» state and `longWordMinLength` (the «۷ حرف · دوبرابر» tag).
- ZSpineChain (ZSolo) was refactored onto the shared scroller/hue/slot pieces — ZSolo's three goldens still match pixel-for-pixel.

**Convention for head-to-head screens (ZVersus must follow):** *me* on the **start** side (right in RTL) with the indigo disc, the opponent on the **end** side with the robot disc; the flat bubble corner sits next to the disc; dashed next-word slot on the side of whoever is to move. (The pre-restyle ZPlay had you on the end side.)

**New tokens/metrics (added only):** `ZGame.gameVersusPillHeight 56, gameDisc 36, gameDiscSmall 28, gameBubbleAvatar 34, gameBubble 48, gameBubbleLast 54, gameBubbleTail 6`. No new colours — everything is existing `ZColors`/`ZScene`.

**Real data:** your score (`state.score`), opponent score (`opponentScore`, accumulated by the bloc for the AI), whose turn, timer, level + dots (`opponentType`), chain + owners (`wordOwners`), your points per word (looked up by move count — `wordScores` only holds the player's words), power-up counts/prices (unchanged logic), long-word rule (`GameConstants.longWordBonusMinLength` ×2). Avatar initial from `AuthCubit` username.

**Deviations from the canvas (flagged):**
- Opponent name: canvas «هوشیار» → real levels آسان / متوسط / سخت with 1/2/3 dots (approved).
- **Pill avatars step down with width** (36 → 28 → none): the pill's flex layout only fits at the canvas's 396 dp; «نوبت حریف» is wider than the canvas's «نوبت تو». On a 393–402 dp phone the header discs are the 28 dp size (measured by `TextPainter`; stable across turns — it measures the longer label). The in-chain discs are unaffected.
- «۷ حرف · دوبرابر» **floats over the input card** (top-end) instead of sitting inline — inline squeezes the field to ~48 dp on 320 dp phones. Visible only while the typed word has ≥ 7 characters (`word.length`, same rule as `GameBloc._calculateScore`).
- Canvas has no «opponent thinking» state and no empty-chain state: added (chunky card with spinner — a static text with reduced motion; «حالا با «ا»» dashed slot / «اولین کلمه رو بنویس» on an empty chain; the ring is dimmed while the AI plays because the clock is not running).
- Timer ring: teal wedge + ink number (canvas) while calm, switches to the solo ring's coral + pulse at ≤ 5 s.
- Older bubbles all share one size (canvas) — the legacy size ramp is gone.

**Defects fixed rather than copied:** labels 10.5/11 sp → ≥ 12 sp; 34 dp back button → 44 dp; physical-side tail/badge → directional (`BorderRadiusDirectional`, `PositionedDirectional`); points pill forced LTR; scores that don't fit scale down instead of overflowing (99 999 tested); semantics on discs-less pill, bubbles, level chip (`سطح N از ۳`), ring; reduced motion = no scheduled frames (no spinner/pulse/drop-in); contrast of every pairing asserted ≥ 4.5:1 (indigo initial on disc 3:1 large text).

**Follow-ups (not built):**
- **The soft keyboard is dismissed on every AI turn** (pre-existing: `ZWordInput` swaps the `TextField` for the thinking card, so focus is lost and the player must tap the field again). The chunky variant has the same behaviour; fix = keep the field mounted/disabled or re-request focus when `isMyTurn` flips back.
- Pre-filled start letter (same as ZSolo), opponent typing indicator, Rive mascot for the AI disc.
- ~~ZVersus should adopt `ZBubbleChain` / `ZVersusPill` / `ZGameScaffold`~~ — done, see § ZVersus below.
- ~~`zShowEndGameDialog` is still the legacy dialog.~~ (done in the Dialogs session below.)

**Tests:** new `test/features/game/z_play_screen_test.dart` — `avatarInitial` unit test; states (empty, signed-in initial vs guest «ت», mid-game with my-only points + both scores, level dots 1/3, opponent thinking, power-ups, send dispatches `WordSubmitted`, long-word tag from 7 letters, back dialog); reduced motion (nothing schedules frames, no spinner); no overflow at 320×568 / 360×640 / 393×852 / 430×932 × light/dark (empty, 10-word chain with 99 999 scores, opponent thinking) + 375×667 with a 260 dp keyboard and the tag; contrast table; goldens `z_play_mid_light/dark`, `z_play_thinking_dark`. `flutter analyze` clean; `flutter test` 134 pass (ZSolo goldens unchanged).

**Simulator (iPhone 17 Pro, light):** seen live — empty chain (your turn), the header pill with 28 dp discs, level chip + bonus chip, input card with price badges on the power-ups, ring running teal and switching to coral at ≤ 5 s, real play: «نام» scored 49, the AI answered «منور» for 64 (pill + result screen agreed), the continue/game-over screens after a timeout. **Not seen live:** dark mode, the bubble chain on a phone (only in the goldens — a pasted/typed word flow was too slow to automate), the 7-letter tag, the opponent-thinking card, hard/medium levels, 320 dp, soft-keyboard-open layout (golden/test only), guest variant (simulator is signed in as `amirabbas`).
**Production side effects:** the debug app talks to production — several short vs-AI games (0–2 words, mostly timeouts/losses) were finished and synced to the account (matches/XP), no hints or continues were bought (coins stayed ۴۶۰).

---

## Consolidation status (as of 2026-10-17)

The numbered "items 1, 2, 5" the brief refers to are not written down in this file or in `docs/`, so they cannot be matched one-to-one; this is what the history shows.

**Landed (all pure moves / dedupes, behaviour unchanged):**
- `f8b9141` `ChunkyBox` → `core/widgets/chunky.dart`.
- `25c4d92` `ChunkyPressable` and the motion helpers (`HomeClock`, `HomeLoop`, reduced-motion check) → `core/widgets/` (`chunky_pressable.dart`, `motion.dart`). This closes the old "hoist `ChunkyPressable`" follow-up from the ZSolo section.
- `3b6365d` shared game frame (`ZGameScaffold`/`ZGameFooter`), `avatarInitial`, the chain index peg, shared test helpers (`test/helpers/contrast.dart`, `game_fakes.dart`).
- `790955a` `ZChunkPill` (`core/widgets/chunky_pill.dart`) and the duplicated HUD/bubble/chain pieces merged onto it.

**Still open:**
- ~~ZVersus still has its own header, bubbles and pill~~ — adopted the shared pieces in the ZVersus session (below).
- Two mascots: `HomeMascot` (hanging from the chain, home only) and the new standing `ZMascot`. They are different drawings; keep both, do not merge.
- `ZBackButton` (legacy 34px, `z_game_shared.dart`) is still used by Daily (no longer by ZVersus or ZLobby); `ZGameBackButton` (44px) is the new one.
- `ZEmptyState` and `ZLoadState` (loading + failed load) now exist (ZFriends session, 2026-10-25) and only the Friends tab uses them. **Still duplicated, not migrated:** `_ErrorView` in `daily_screen.dart` and `z_profile_screen.dart`, `_ErrorState` in `z_board_screen.dart`, and the bare `CircularProgressIndicator` loading states of `messages_screen.dart`, `rewards_screen.dart`, `daily_board_screen.dart`, `z_profile_screen.dart`, `daily_screen.dart`.
- ~~The ribbon title (swallow-tail) is not a shared widget yet~~ — `ZRibbonTitle` (`core/widgets/z_ribbon_title.dart`) landed with ZLobby (below).
- Sheets without a canvas frame (referral, edit username, avatar picker, buy coins, taunt tray) are still Material bottom sheets; they get a `ZTray` frame in their screens' sessions. (Add friend became a `showZDialog` card in the ZFriends session; the friend challenge was already a dialog.)
- `ZInviteButton` (the amber «دعوت به بازی») is shared by the lobby and the Friends tab since the ZFriends session.

---

## Dialogs session (2026-10-17) — code complete; goldens + widget tests, not seen on a device

**Source:** canvas turn 8 `ZExitConfirm.dc.html` (frames 8a–8e: in-context + one per mode), turn 7 frame 7p (level picker, `ZPlayA` `level-picker`), `ZMascot.dc.html`, `zmotion.js` (`dropin`, `pop`, `sag`, loops).

**Shared frame (new):** `core/widgets/z_dialog.dart`
- `showZDialog(context, builder:)` — every non-screen modal goes through it: centred card, `scrim` token backdrop (flat, no blur), 12px side inset, max 372 wide, scrolls when tall, keeps the caller's text direction. Entrance = `dropin` (−48px, canvas spring, 520ms); reduced motion = 200ms fade.
- `ZDialogCard` — 3px outline, r28, solid 6px edge, optional `mascot` standing on the top edge.
- `ZDialogButton.primary` (58 / r20 / 5px edge, accent) and `.secondary` (50 / r18 / 4px edge, coloured label + icon), both on `ChunkyPressable`.
- `core/widgets/z_mascot.dart` — `ZMascot(mood: idle|happy|sad|thinking|surprised, size, shadow, animate)`, the canvas's **standing** mascot drawn in code (no letter on it — checked in `ZMascot.dc.html`: the body is a plain amber box). Built here because the exit dialog needs it (sad / surprised); ZOver will reuse it. All five moods are drawn so ZOver/ZLobby/ZDaily don't reopen it. `HomeMascot` is untouched.

**Exit confirm** — `features/game/view/widgets/z_exit_confirm.dart`: one `ZExitConfirm` with `ZExitMode { solo, ai, online, daily }`; `zShowEndGameDialog(context)` (same name/signature, callers unchanged: `ZGameBackButton` in `z_game_scaffold.dart` for ZSolo/ZPlay, and ZVersus' back button) derives the mode from the running `GameActive` (`zExitModeOf`) and ends the game with `GameEnded` on leave. Primary = stay (also scrim tap), leave is secondary in `coralInk`. The dialog closes itself if the game ends underneath it.

| Mode | Caller | What leaving really does | Canvas claim → what the dialog says |
|---|---|---|---|
| solo (`classic` + `solo`) | ZSolo back | `GameEnded` → local match finished and saved, score/chain counted in stats + XP, synced; no continue offered | «ذخیره نمی‌شه» is false → «بازی همین‌جا تموم می‌شه … امتیازت همون‌طور که هست ثبت می‌شه»; cards = real chain length + score |
| ai | ZPlay back | same as solo; the server records every solo/AI upload as the player's win, there is no loss record | «باخت در کارنامه» is false → no loss mentioned; cards = score + chain length |
| online | ZVersus back | `GameEnded` shows the result screen locally; the server only learns when the socket closes (leaving ZOver), then opponent gets `opponent_disconnected`, 30 s grace, then wins and takes the pot; entry fee only exists against a human (`bloc.entryFee`, new getter) | rank «−۱۵ رتبه» does not exist → dropped; coin card + line only when `entryFee > 0`; card «باخت / نتیجهٔ بازی» |
| daily | ZSolo (daily) back | same save; the attempt is posted with its score to the daily board; the streak is kept (the game counts as played); prizes depend on rank; a paid retry exists | «تا فردا نمی‌تونی»، «۶ روز رکورد پیاپی»، «۵۰ سکه جایزهٔ امروز» are false → «تلاش امروزت همین‌جا تموم می‌شه و با همین امتیاز توی جدول امروز ثبت می‌شه»; cards = chain + score |

Header of the cards: «تا همین‌جا ثبت می‌شه» (kept) for solo/ai/daily, the canvas's «اگه بری از دستت می‌ره» only for online, where something is actually lost. Stay/leave labels follow the canvas («ادامه می‌دم» / «برمی‌گردم»; «خروج» / «تسلیم و خروج»), replacing «ادامه بازی» / «پایان بازی».
- **Clock:** the canvas pauses the clock for solo/AI/daily. Solo and vs-AI now pause (`GamePaused`/`GameResumed`, the same mechanism the need-coins sheet used). **Daily does not pause** and says «تایمر متوقف نمی‌شه» like online: it is ranked and prized, and the back button would be a free "think as long as you like" button. One line to flip: `zExitPausesClock`.

**Level picker** — `features/home/view/widgets/home_level_dialog.dart` (`showAiLevelDialog`, `AiLevelDialog`, `aiLevels`): replaces the Home bottom sheet. Cards آسان / متوسط / سخت with the canvas robot faces and the flavour names خواب‌آلود / هوشیار / بدقلق, 1–3 speed bars (no seconds), radio, default **متوسط**, «شروع بازی» CTA, close button; tapping a card only selects. `HomeScreen._startVsAi` pushes `/game` with `GameRouteArgs(mode: 'classic', opponentType: <chosen>)` exactly as before. Subtitle: «هرچه سخت‌تر، سریع‌تر و کم‌اشتباه‌تر» — the canvas's «… و بددهن‌تر» describes AI trash-talk that does not exist.

**Restyled onto the frame:** `showInsufficientCoinsDialog` (earn rows are chunky rows now; API unchanged), the notification-permission dialog (happy mascot), and the power-up need-coins sheet (now a dialog; still pauses and resumes the game). All three had no canvas frame — derived from the exit dialog.

**Tokens (added only):** `ZScene.scrim` (`#1E1B2E` @45% light, `#08060C` @60% dark — the canvas hardcodes 45% / 28% in the frames, the token sheet says these). `ZGame.dialogRadius 28, dialogDepth 6, dialogInset 12, dialogMaxWidth 372, dialogMascotLift 62, dialogMascotSize 88, dialogPrimaryHeight 58/Radius 20, dialogSecondaryHeight 50/Radius 18`; `ZGameMotion.dialogEnter 520ms, dialogEnterReduced 200ms, mascotPop 420ms`.

**Tests:** `test/features/game/z_exit_confirm_test.dart` (mode mapping, copy per mode incl. "no invented rank/streak/prize", pause/resume/end events, scrim = stay, auto-close, reduced motion, no overflow 320×568…430×932 × both themes × 4 modes + 1.6× text, contrast, 6 goldens), `test/features/home/ai_level_dialog_test.dart` (default, selection ≠ start, result, close, scrim, radio semantics, overflow, 2 goldens), `test/core/widgets/z_dialog_test.dart` (scrim token, dismissal, width, scrolling, direction, entrance, buttons, coins + notification behaviour and goldens), `test/core/widgets/z_mascot_test.dart` (all moods, sizes, no text, reduced motion, 2 goldens). Helpers: `ScriptedGameBloc` (`test/helpers/game_fakes.dart`), `zTestApp(reduceMotion:)` sets the flag app-wide so routes see it.

**Deviations from the canvas:** copy adapted where false (table above); no pill pause for daily; dialog entrance has no 300ms delay (the canvas `dropin` carries one for chain rows); mascot loops are re-derived from `zmotion.js` (breathe/hop/sag/ponder/pop/blink/tear/dots) with a ticker, not a port; the picker's character names are flavour only.

**Flagged, not fixed:**
- **Leaving an online game does not forfeit it.** `GameEnded` only finalises locally; no message goes to the server and the socket stays open until the player leaves ZOver. The opponent keeps playing against an absent player until the 30 s disconnect grace. The dialog says «می‌بازی», which is where it ends up. A real fix needs an explicit forfeit on the WS protocol.
- The old sheets' before-state could not be captured for the level picker and the need-coins sheet (private widgets); before/after goldens exist for the exit, coins and notification dialogs (before images: scratchpad `goldens/before/`, not committed).

**Not verified:** nothing was run on a device or simulator. Goldens are generated on Linux like the rest. `test/core/widgets/shared_widgets_golden_test.dart` (2), `z_bottom_nav_golden_test.dart` (4), `z_play_screen_test.dart` / `z_solo_screen_test.dart` / `home_view_golden_test.dart` goldens (9) fail on a clean checkout too (1.5–2.9% pixel diffs — confirmed with `git stash`); not caused by this work.

---

## Friend challenge dialog (2026-10-17) — code complete; widget tests + goldens, not seen on a device

**Source:** canvas turn 9, `ZInviteConfirm.dc.html` (frames 9a in context on ZFriends, 9b card only; light + dark). Replaces the Material bottom sheet `friend_challenge_sheet.dart` (deleted).

**Code:** `features/friends/view/friend_challenge_dialog.dart` — `showFriendChallengeDialog(context, friendUsername:)` → `Future<bool>` (true only for «بفرست»; «بی‌خیال», the scrim and back all give false) on the shared `showZDialog` / `ZDialogCard` / `ZDialogButton`. `_FriendRow._challenge` (`z_friends_screen.dart`) awaits it and then calls `FriendsCubit.sendChallenge(friend.userId, 'classic')` — the same call, arguments, guards (`insufficient_coins` → earn-coins dialog, other errors → toast) and navigation as before; nothing is sent until the player confirms. `ZDialogButton` gained `icon` (primary) and `height` / `radius` / `depth` (secondary). New `GameConstants.challengeValidHours = 24` (mirrors the backend's 24h expiry).

**Layout (canvas):** two 60px discs (me indigo with my initial from `AuthCubit`, the friend coral with theirs — the opponent colour of the game screens) joined by an amber chain link; title «X را به بازی دعوت کنی؟» (the name in a bidi isolate); one line of body; the lobby's two tiles «ورودی ۲۰ سکه ← جایزهٔ برنده ۴۰ سکه» from `GameConstants`; a fee note; «بی‌خیال» + wider primary «بفرست» with the send glyph.

**Copy adapted where the canvas claims something the product does not do:**
- «براش اعلان می‌ره و تا ۲ دقیقه منتظر جوابش می‌مونی.» → «براش اعلان می‌ره و تا ۲۴ ساعت وقت داره جواب بده.» A challenge stays answerable for 24h (`friend_challenges.expires_at`); the 120 s is how long a *room* waits once the invite is accepted (`RoomWaitTimeoutSec`), and the challenger is not blocked meanwhile (`ChallengeWatcher` pulls them into the room).
- «ورودی وقتی کم می‌شه که دعوت رو قبول کنه.» → «سکه وقتی کم می‌شه که بازی شروع بشه، نه همین حالا.» The fee is taken in `Room.chargeEntryFees` when the second player has joined and the match starts; accepting only creates the room, and a room nobody joins within 120 s is cancelled without charging. (Balance is *checked* at send and at accept — `402 insufficient_coins` — which is unchanged.)
- The canvas note «Tapping «دعوت شد» again withdraws without a dialog» is not built: there is no cancel-challenge endpoint (listed in `todo.md` § 2.1), and the Friends row still says «رویارویی» rather than «دعوت به بازی».
- The old sheet's rule line («کلاسیک · هر نوبت ۱۵ ثانیه · اولین اشتباه می‌بازد») is not in the canvas and is gone; Classic is still the only mode sent.

**Tests:** `test/features/friends/friend_challenge_dialog_test.dart` — copy and numbers, initials (Persian, Latin, empty, signed-out), result values (confirm / cancel / scrim), an integration test through `ZFriendsScreen` proving `sendChallenge('friend-7','classic')` is called only after confirming and never on cancel, no overflow 320×568…430×932 × both themes, a 32-letter name at 1.6× text, contrast, 2 goldens. **Before golden:** captured from the old sheet before the change (scratchpad `goldens/before/challenge_sheet_{light,dark}.png`, not committed).

---

## ZOver — "A · mascot-led" result screen (2026-10-17) — code complete; widget tests + goldens, not seen on a device

**Source:** canvas turn 7, `ZOverA.dc.html` (frames 7iL/7iD «پایان — باخت», 7jL/7jD «پایان — برد»; `ZOver.dc.html` is the pre-mascot version), `ZMascot.dc.html`, `zmotion.js`. One screen for solo, vs-AI and 1v1 (`ZOverScreen`); daily still shows only the saving frame until `ZDailyAfter` takes over.

**Code:** `features/game/view/z_over_screen.dart` (data + routing: which layout, which actions) and three widget files in `features/game/view/widgets/`: `z_over_hero.dart` (`ZOverEnter` stagger, `ZOverLossHero` with the broken-chain art, `ZOverWinHero` with rays/confetti), `z_over_cards.dart` (`ZOverScoreCard`, `ZOverRecordBar`, `ZOverVersusPill`, `ZOverChip`), `z_over_actions.dart` (`ZOverContinueActions`, `ZOverFinalActions`). Built on the frame `ZGameScaffold` (header = coin pill + ✕, body scrolls, footer = pinned actions), `ZMascot` (sad / happy), `ChunkyBox`/`ChunkyPressable`, `ZDialogButton.primary/secondary`, `ZDiscAvatar`, `zChainWordSpan` (shared-letter colours), `DashedBorderPainter`, `ZCoin`, `showInsufficientCoinsDialog` (continue-with-coins when the balance is short — unchanged logic).
**Hoisted / added shared pieces:** `core/widgets/z_hud_coin_pill.dart` (`ZHudCoinPill`, pure move of Home's private `_CoinPill`; no `onTap` → plain read-out without the «+»), `core/widgets/z_rays.dart` (`ZRaysPainter`, pure move out of `home_chest.dart`), `core/widgets/z_stroked_text.dart` (`ZStrokedText`: outlined sticker title with solid drop shadow), `ZGameBackButton(close: true)` (✕). Home renders byte-identically after the moves (checked by diffing the Home golden test images before/after). Tokens: none new; metrics `ZGame.over*`.

**Layouts:** *loss / not yet decided / ended by the player* — «زنجیر پاره شد!» (stroked coral), the reason pill, sad mascot, the last three words as tiles joined by chain links with the final link broken and a dashed «ر؟» slot (letters coloured like in the game), score card (big score + stat tiles + record bar), then the actions. *win* (`iWon == true`) — «بردی!», happy mascot over rays and confetti, head-to-head pill, reward chips, actions. Actions: while the 15 s continue window is open → «ادامه با ویدیو», «ادامه با ۲۵ سکه», share, home(decline); once decided → primary «بازی دوباره», «خانه», «هم‌رسانی».

**Adapted where the canvas doesn't match the product:**
- **Continue price ۵۰ → ۲۵** (`GameConstants.continueCostCoins`), as already decided.
- **No rounds.** Canvas win shows «۳–۲» rounds and «در ۵ دست مقابل مریم ک.». → the pill shows the two final *scores* (mine first, mine on the start side like the game screens), caption «مقابل حریف» / «مقابل حریف هوشمند · آسان» (the 1v1 opponent's name is not in `GameOver`/the WS state; its disc is the coral «ح»).
- **Reward chips are real:** «+۴۰ سکه · جایزهٔ برنده» → «+N سکه · سود این بازی», the *net* of the entry fee (`coinsNet`; the pot is 2× the fee, the winner nets 1×), shown only for a paid 1v1 win; «+۱۲۰ امتیاز تجربه» → «+score» — the game's score *is* the XP (`GameService.AddXP`), hidden for guests (no level); «بهترین کلمه · دوبرابر» → «بلندترین کلمه» of the chain (the ×2 long-word bonus is Flutter-only and the chain includes the opponent's words, so «دوبرابر» was dropped).
- **Dropped:** the level-progress bar (۱۲ → ۱۳, ۷۴۰/۱٬۰۰۰) — it would need a `GET /profile/stats` round trip that can race the XP credit (solo uploads sync later); the «دوباره با مریم» rematch → «بازی دوباره» (solo: new solo; vs-AI: same level; both `pushReplacement('/game')`) and «حریف جدید» for 1v1 (→ `/lobby`; there is no rematch); disabled until the result is saved.
- **«باختی!»** for a lost duel (the canvas only draws the chain-broken loss); the old 😞/🏆/🎉 emoji are gone (they don't sit well inside a stroked title).
- **«۳۰ ثانیه» chip on the video button dropped** — nothing guarantees an ad's length. The real decision window is shown instead: «فرصت ادامه: N ثانیه» under the buttons (the old screen only showed it in the home link).
- **Record bar:** «تا رکوردت (۲۳) · ۶ کلمهٔ دیگر» with a coral `17 / 23` bar when the best chain is ahead; a full teal «رکورد جدید!» bar once it is equalled/beaten; hidden until the saved record is read and in duels (vs-AI keeps «رکورد تو» as a stat tile, as before). The old chain-tail chip card and «۳۰ ثانیه»/emoji are replaced by the broken-chain art.
- **✕ (top) and the home square** both decline the continue while it is open (`AcceptDefeat`, same as the old «بازگشت به خانه (N)» link — it ends in the result state, it does not navigate); with nothing to decide they go home.
- Text scale on the action buttons is clamped to 1.3× (like the dock); everything else scales and the hero artwork scales down on narrow phones.
- Win/loss logic is **unchanged**: 1v1 uses the server's `iWon`; vs-AI still decides by score (see the todo.md product decision — a vs-AI player who times out with the higher score is shown «بردی!»).

**Flagged, not fixed:**
- **Solo / vs-AI «ادامه با ۲۵ سکه» spends a local mock** (`MockMonetizationService.spendCoins`), not the server balance or `AuthCubit` — the HUD pill (the real balance) does not move after a solo continue. Multiplayer coin-continue is charged by the server.
- Guests see the continue-with-coins button like before (the mock lets them pay).
- `continue` with `method: "forfeit"` is still dropped by the server (todo.md 1.2), so «ادامه نمی‌دم» in 1v1 only ends the wait when the window times out.

**Tests:** `test/features/game/z_over_screen_test.dart` (85 tests): loss states and every reason string, empty chain, record bar variants, 1v1 loss/draw tiles, the whole continue offer (video → ad → `ContinueRequested('ad')`, no ad → toast, coins → spend 25 / earn-coins dialog, decline, share), final actions via a real `GoRouter` (play again args, 1v1 → lobby, disabled until saved, home, ✕), win chips (fee/no fee/guest/vs-AI), daily frame, reduced motion = no scheduled frames, no overflow at 320×568 / 360×640 / 393×852 / 430×932 × light/dark × 5 cases + 1.6× text, contrast table, 6 goldens in `test/features/game/goldens/z_over_*`. **Before** images of the old screen (solo continue, solo final, 1v1 win, 1v1 loss × light/dark): `/tmp/claude-1000/-home-amirabbas-Development-word-chain/c1b2357d-f9f1-4b0d-9de8-2db21c5c29de/scratchpad/goldens/before/` (not committed). `flutter analyze` clean. The 17 golden/dialog failures that exist on a clean Linux checkout (shared widgets, dock, ZSolo/ZPlay/Home goldens, the two «back button asks» tests) are unchanged — they are the same set before and after this work. New goldens were generated on Linux like the others; regenerate on macOS with `flutter test --update-goldens test/features/game/z_over_screen_test.dart`.

**Not verified:** nothing was run on a device or simulator (confetti/rays/mascot motion, the entrance stagger, haptics, the ad flow, `pushReplacement` into a fresh `GameBloc`).

---

## ZVersus — "A · mascot-led" 1v1 screen (2026-10-17) — code complete; widget tests + goldens, NOT seen on a device (no live 1v1 match was run)

**Source:** canvas `ZVersusA.dc.html` (one 396×812 frame, `premium` / `trayOpen` props; light + dark via tokens). Same approach as ZPlay: the frame's layout, the shared pieces, the head-to-head convention (me on the start side with the indigo disc, the opponent on the end side, flat bubble corner next to the disc, dashed slot on the side of whoever moves).

**Code:** `features/game/view/z_versus_screen.dart` is now layout only (~150 lines, was ~800): `ZGameScaffold` + `ZGameHeader` (back button = `ZGameBackButton` → `zShowEndGameDialog`, unchanged exit behaviour) + `ZVersusPill` + `ZTimerRing(calm)` + the entry-fee chip, `ZBubbleChain` for the chain, `ZGameFooter` for the input card and the four power-ups. The legacy header, `_BubbleChain`/`_BubbleRow`/`_PlaceholderBubble`, turn banner, `_Footer`, `ZBackButton` use and the bottom-sheet taunt picker are gone. New: `features/game/view/widgets/z_taunt_tray.dart` (`ZTauntButton`, `showZTauntTray` / `ZTauntTray`, `ZVersusChain` — the chain with the in-chain taunt, re-exported from the screen file so existing imports keep working).

**Shared pieces extended (opt-in, ZPlay/ZSolo unchanged):**
- `ZDiscAvatar.opponent` (coral + initial; the AI stays the amber `robot`) and `avatarId:` (premium avatar image over the disc, initial as placeholder/fallback — keeps the Phase 22 avatars that the old header showed).
- `ZBubbleChain(myAvatar:, opponentAvatar:)` builders; `zBubbleEntries(state, isMine:)` replaces ZPlay's private mapping (same logic, ZPlay now uses it too).
- `ZVersusPill(myPremium:, opponentPremium:)` — the premium crown before the name (counted in the width measure so the avatar step-down stays right); the pill now **caps text scale at 1.3×** (found at 1.6×: score + name overflowed the fixed 56dp pill — it also fixes ZPlay).
- `ZGameHeader.below` is optional; `ZGameFooter(powerups:, trailing:, thinkingAccessory:, inputEnabled:)`; `ZWordInput(thinkingAccessory:)`.
- `GameConstants.tauntCooldownSec = 5`, `tauntMaxPerMatch = 8` (mirror `config.TauntCooldownSec/TauntMaxPerMatch`).

**Real data used:** both scores, whose turn, ring (both turns — the clock runs on the opponent's turn too, so the ring is never dimmed, as in the canvas frame), chain + owners (mine = `wordOwners[i] == myPlayerId`), my points per word (by move count), premium crowns, premium avatar ids, entry fee (`bloc.entryFee`; chip only when > 0 — AI-fallback matches are free), the four power-ups (`hint/freeze/extra_time/shield`, same `PowerupRequested` flow), the premium taunt rules.

**Omitted — nothing backs it (not faked):** «۲ جان» lives chip; «دست ۳ از ۵» + round dots; «مریم دارد می‌نویسد» typing bubble; «کلمهٔ بلند · ۷ حرف · امتیاز دوبرابر» tag (the Go scorer has no ×2 — todo.md 1.5; the bubble points are the server's real numbers, so the tag would have been false); the «ارسال شد / طعنهٔ این دست» used-state.

**Adapted where the canvas doesn't match the product:**
- Opponent name: not in the WS `game_state` (`opponentUsername` is null) → «حریف» (initial «ح»), like ZOver. Everything reads `state.opponentUsername ?? 'حریف'`, so it lights up if the server ever sends it.
- Turn chip lives inside the pill (ZPlay layout) instead of a separate dark chip under the header; the second chip row only holds the fee chip.
- **Taunt tray:** sub-line «هر ۵ ثانیه یک طعنه · تا ۸ طعنه در هر بازی» instead of «یک طعنه در هر دست» (rounds don't exist). Free players get the explanatory line «ارسال فقط برای اشتراک ویژه فعال است؛ دریافت طعنه‌ها برای همه رایگان است.» and locked chips; the canvas's «با اشتراک ویژه طعنه بفرست» button is **not built** (no purchase flow — `MockMonetizationService.purchase` grants nothing; a dead CTA would be fake). The tray is a centred `showZDialog`/`ZDialogCard` (the canvas anchors it to the bottom; a `ZTray` doesn't exist yet). Skeleton while the first fetch runs with an empty cache (static boxes; the canvas pulses them), «طعنه‌ای در دسترس نیست» when the catalogue is empty, last good list shown at once.
- **Taunt button** (66dp, beside the input card): crown badge for premium, lock badge + muted fill for free players (the canvas always shows the crown).
- **Received/sent taunt:** (revised 2026-10-17 after two-device testing — it first floated over the top of the chain) an amber pill with the sender's disc **inside the chain**, directly under the sender's most recent word, on the sender's side (mine on the start side, theirs on the end side), 3 s, identical for sender and receiver; it collapses afterwards so words don't jump, and a new taunt scrolls the chain down like a word. `ZBubbleChain(taunt: ZChainTaunt)` draws it; `ZVersusChain` (z_taunt_tray.dart) owns the timer. **Edge case — sender has no word yet** (taunt at game start, or by the player who hasn't played): there is no word to follow, so it goes under the *newest* word of the chain, or right after the «شروع زنجیر» chip when the chain is empty (`zTauntAnchor`). The canvas keeps older taunts in the chain history; `GameActive` only keeps the latest one, so only that one is shown.
- **Opponent identity (2026-10-17):** the server's `game_start.state` already sends `premium` and `avatars` for both players (verified in `room.go` `perkState`/`gameStartState` and by a bloc test) — the pill crown, discs, in-chain bubbles and now ZOver's head-to-head use them (`GameOver.myAvatarId/opponentAvatarId`, copied from `GameActive`). It sends **no usernames** — backend change request in todo.md 1.6a; «حریف» / «ح» stays. `GameBloc` logs the parsed `premium`/`avatars` at `game_start` (debug level) to help diagnose a missing avatar on a device.
- **Rejected taunts:** the server does answer the sender with `taunt_rejected` (`premium_required` | `rate_limited`); the bloc turns it into the shared power-up toast (`ZToast`): the real rule for `rate_limited` (one signal for cooldown *and* cap), «فقط برای اشتراک ویژه» for `premium_required`. An unknown taunt id gets no reply (todo.md 1.6b).
- Thinking card keeps the real «X در حال فکر کردن…» copy (not «منتظر نوبت…») plus the canvas's thinking `ZMascot` (34dp).
- Canvas back button is a pause icon → the shared arrow `ZGameBackButton`; it opens the exit-confirm (online mode) as before, **nothing about forfeit changed** (todo.md 1.1).
- Footer (input, taunt button, power-ups) caps text scale at 1.3× like ZOver's actions.
- `game_screen.dart`: the «اتصال حریف قطع شد» banner moved from `top + 60` to `top + 120` so it sits below the new header instead of covering the score pill. Continue-window overlay untouched.
- The input stays locked while the opponent-continue overlay is up (`inputEnabled`), as the old footer did.

**Tests:** `test/features/game/z_versus_screen_test.dart` (52): empty chain / mid-game / opponent turn / named opponent / premium crowns, me-start-opponent-end sides (bubbles + dashed slot), fee chip present/absent, the omitted elements stay omitted, send → `WordSubmitted`, input locked during the continue window, freeze offered, back button opens the exit dialog without sending anything; taunts (premium tray + real rule line + `TauntSent`, free = locked and nothing sent, skeleton → list, empty catalogue, in-chain taunt under the sender's last word on each side, hides after 3 s, repeats, no-word-yet and empty-chain placement); reduced motion (no scheduled frames, no spinner); no overflow at 320×568 / 360×640 / 393×852 / 430×932 × light/dark (empty, 8-word chain with 99 999 scores + both crowns + a 31-letter name + a long taunt, opponent turn), tray at 320×568 × both themes, text ×1.3/×1.6/×2.0 with the action labels asserted capped at 1.3×, thinking card at 320 wide ×1.6, keyboard open; contrast table; 9 goldens `test/features/game/goldens/z_versus_*` (my turn ×2, opponent turn urgent ×2, received taunt in the chain, my taunt dark, tray premium ×2, tray free) — generated with `--update-goldens` for this file only. `z_versus_taunt_test.dart` now covers the `ZVersusChain` timer; `game_bloc_taunt_test.dart` the rejection toast and the avatars carried into `GameOver`; `z_over_screen_test.dart` the avatar discs. In the goldens the Material crown/lock icons render as boxes (the test environment has no icon font); on a device they are the crown/lock glyphs.

**Verification:** `flutter analyze` clean. Full suite: 374 pass / 17 fail; the **same 17** fail on a clean checkout (328 pass / 17 fail — shared widgets 2, dock 4, ZSolo/ZPlay/Home goldens 9, the two «back button asks» dialog tests; compared test by test from the logs), so none is caused by this work. Formatted only the files touched.

**NOT verified (needs two devices):** a live 1v1 match end to end — nothing here was run against the real WebSocket, a simulator or a phone. Specifically: the real `game_start` → `GameActive` mapping with the new header (fee chip value, premium crowns/avatars from the server, the «حریف» fallback), the ring on the opponent's turn, power-ups in a duel (freeze/extra time/shield via WS and the coin/ownership checks), sending a taunt as a premium player and receiving one as a free player (tray, 3 s bubble, cooldown/cap rejections → toast), the premium avatar image loading in the discs, the keyboard-open layout, dark mode on a device; **game-over** (ZOver after a 1v1, the winner/payout screen), the **opponent-deciding overlay** and the **disconnected banner** (its new offset was only reasoned about, not seen), the continue flow, the exit dialog's real effect (leaving still does not forfeit — todo.md 1.1), and reconnect.

---

## ZLobby — "A · mascot-led" 1v1 lobby (2026-10-25) — code complete; widget tests + goldens, NOT seen on a device (no simulator/phone run, no live queue)

**Source:** canvas `ZLobbyA.dc.html` (one 396×812 frame; sky scene, ribbon header, two discs + mascot, fee→prize strip, big teal button, friends list). `ZLobby.dc.html` (no `A`) is the *legacy* frame (turn-length + wager pickers, room code, win/loss records) and was not used. Motion keyframes read from `zmotion.js` (`radar` 2 s scale .6→1.5 / opacity .9→0 with a 1 s offset; `live` 700 ms; `pulse`).

**Code**
- `features/lobby/view/lobby_screen.dart` is now orchestration only (~270 lines, was 689): `HomeSceneBackground` (full scene, as the canvas has no `calm`) + `_Header` (`ZGameBackButton` 44 → `pop`, or `go('/home')` when nothing to pop; `ZRibbonTitle`; `ZHudCoinPill` read-out from `AuthCubit`) + a `CustomScrollView` (`_Top` = stage / stake card / button; `SliverFillRemaining` = the friends card, which takes the leftover height on tall phones and scrolls on short ones). Gone: `_TopBar`, `_VersusCard`/`_VersusSide`/`_SearchDots`, `_IdleBlock`, `_SearchingBlock`, `_ErrorBlock`, `_EntryFeeRow`, `_FriendsCard`, `ZBackButton`/`CoinPill`/`LetterTile`/`AccentButton`/`NeutralButton` use.
- New `features/lobby/view/widgets/`: `lobby_stage.dart` (`LobbyStage` + `LobbyStageMode idle|searching|found|error`: my `ZDiscAvatar.me` on the start side with premium avatar, a dashed «؟» disc on the end side with two teal radar rings while searching, rotated «در برابر» (`ZStrokedText`), `ZMascot` idle / thinking / happy / sad, elapsed-time chip), `lobby_stake.dart` (`LobbyStakeCard`), `lobby_cta.dart` (`LobbyCta`), `lobby_friends.dart` (`LobbyFriendsCard`).
- New shared widget **`ZRibbonTitle`** (`core/widgets/z_ribbon_title.dart`): swallow-tail plate in an accent (`ZDialogAccent`, default coral), 44 tall, 4 px edge, tails 30×34 poking 20 px past each end (mirrored for RTL/LTR), text scales down rather than wraps, label ignores text scale above 1.3. Reusable by later screens.
- New `LobbyPlayersCubit` (`cubit/lobby_players_cubit.dart`): friends (`FriendsRepository.fetchFriends`), my level (`ProfileRepository.fetchStats().level`) and premium avatar (`fetchPerks().avatarId`) — all best effort; `invite()` returns sent / needs-coins / failed. `LobbyCubit`/`LobbyState`/`LobbyRepository` are untouched.
- `GameConstants.matchmakingAiFallbackSec = 30` (mirrors `config.AIFallbackWaitSec`; the old copy hard-coded «۳۰»); `friendInviteSentMessage(name)` in `error_messages.dart`.

**Real data used:** coin balance (`AuthCubit`), my name/initial, level («سطح ۵», from `/profile/stats`), premium avatar (`/profile/perks`), entry fee 20 / pot 40 (`GameConstants`), AI-fallback 30 s (verified in `backend/internal/config/config.go` `AIFallbackWaitSec` and `MatchmakingService.Join`/`processQueue`), elapsed search time (the cubit's visual ticker), friends + count + each friend's weekly score (`/friends` + `/leaderboard?type=friends`), Classic challenge send (`POST /challenges`).

**Omitted — nothing backs it (not faked)**
- «۳٬۴۰۱ نفر آنلاین · هم‌سطح تو» chip and the «۳٬۴۰۱ آنلاین» pill (old canvas): no endpoint reports players online (todo.md 2.2). «هم‌سطح تو» is also **false**: `MatchmakingService.processQueue` pairs the first two fresh queue entries by arrival order, it never looks at level or score (`queueEntry.Difficulty` is stored but not used for pairing). The chip's slot now only holds the real elapsed-time chip while searching. The old subtitle «هم‌سطح تو» under the opponent is gone too.
- «۱٬۸۴۰ امتیاز» under my name: no lifetime score field on `GET /profile/stats` (`ProfileStats` has `bestScore`, `level`, …) → «سطح N» instead; the line is hidden until the stats call succeeds or if it fails.
- «با هم: ۲ برد · ۱ باخت» and «بهترین زنجیر ۲۹» under friends: no head-to-head or best-chain-per-friend endpoint (todo.md 2.6) → «N امتیاز این هفته» (real, as before).
- «دعوت شد» withdrawing the invite on a second tap: no cancel endpoint (todo.md 2.1) → the sent state is inert.
- Time Attack, turn-length and wager pickers, room code: removed from the product 2026-10-03 (not in canvas A either). The referral placeholder row the brief mentions **does not exist** in the lobby code or in canvas A (removed 2026-10-03), so there was nothing to keep or wire.
- Entrance staggers (`pop`/`up`/`down`, 520 ms spring) are not built; the mascot, radar rings, live dot and CTA pulse are.

**Adapted where the canvas doesn't match the product**
- The canvas frame is one state («در جست‌وجو…» with the button still «پیدا کردن حریف»). Derived from tokens: **idle** «آمادهٔ شروع؟» + idle mascot; **searching** radar rings + thinking mascot + elapsed chip, and the teal button becomes the neutral «لغو جست‌وجو» (`ZDialogButton.secondary`); **found** «حریف پیدا شد!» + happy mascot for the frame before navigation; **error** «حریف پیدا نشد» + sad mascot, the server reason replaces the footnote in the stake card next to a coral «!», button «تلاش دوباره».
- AI-fallback footnote: «…با حریف هوشمند بازی می‌کنی و ورودی نمی‌دهی» (the canvas stops at «شروع می‌شود»; free-vs-AI is the old copy and is true — matches vs the fallback are free).
- Coins in the fee/prize boxes use the app's `ZCoin` glyph, not the canvas's drawn amber disc. The «sent» invite button uses `wash` + `ink60` (the canvas's `--muted` / `--mutedInk` tokens do not exist in `ZColors`).
- The friends card lists **all** friends (the old screen showed the first two), with the canvas's «N نفر» count; its states are skeleton rows (loading), a Persian message + «تلاش دوباره» (error — it used to be silently empty), a message + «افزودن دوست» → `/friends` (empty) and, for a guest, a message + «ورود» → `/login?return=/lobby`.
- Invite is still sent **directly** (no confirm dialog — unchanged; the Friends tab confirms with `showFriendChallengeDialog`). Behaviour changes that are deliberate: the toast/errors now come from `error_messages.dart` (`FriendsException.message`) instead of two hard-coded strings; a friend invited from the screen can't be invited twice (the server has **no** duplicate guard — `ChallengeService.CreateChallenge` just inserts another pending challenge and pushes again); `insufficient_coins` still opens `showInsufficientCoinsDialog`.
- Guest: Home already redirects (`_startOnline` → `/login?return=/lobby`). Reaching `/lobby` directly as a guest used to show the screen and fail at the queue call; now the button itself pushes `/login?return=/lobby`, friends/stats are not fetched, and the coin pill is hidden.
- Short phones (< 640 high): a compact stage (216 instead of 244) keeps the button above the fold at 320×568.
- Fixed-height controls (header pill, stage labels, stake boxes, the button, invite button, ribbon) cap text scale at 1.3; the footnote, friend rows and notices scale freely. At ×2.0 on 320×568 the button is below the fold (the page scrolls).
- `_WaitingForOpponent` (the friend-challenge «منتظر حریف» screen) lives in `game_screen.dart`, not the lobby, and was **not** restyled or touched.

**Behaviour kept:** queue join/cancel (`LobbyCubit`, POST/DELETE `/match/queue`), the 402 → `reset()` + `showInsufficientCoinsDialog` listener, navigation to `/game` with `GameRouteArgs` on a match, `ChallengeWatcher` joining on accept. No backend and no forfeit code touched.

**Flagged, not fixed:** leaving the lobby with the back button *while searching* does not call `cancelQueue` (`LobbyCubit.close` only cancels its timers and the push subscription; the in-flight `joinQueue` HTTP call is not cancelled) — the player stays in the server queue until it pairs or the 35 s long-poll times out. See todo.md.

**Tests:** `test/features/lobby/lobby_screen_test.dart` (56): idle pieces with real data (ribbon, 44 px back button, read-out coin pill, level, fee/pot, 30 s note, no legacy `ZBackButton`), the omitted elements stay omitted, level hidden when stats fail, back → `/home`, reduced motion schedules no frames; search → elapsed ticks → cancel (`cancelQueue` called), radar only while searching + animating, match → `/game` with room/mode/player id, 402 → coins dialog and back to idle, other failure → reason + «تلاش دوباره» + sad mascot + retry, guest (no pill, no friends call, button and notice → login), friends (rows/count/score, skeleton, empty → `/friends`, error + retry, invite sends one Classic challenge then «دعوت شد» and is inert, failed invite toast, invite 402 → dialog); no-overflow grid 320×568 / 360×640 / 393×852 / 430×932 × light/dark × (idle with 6 friends and 31-letter names + 9-digit coins, searching, error + loading), the button above the fold at every size, text ×1.3/1.6/2.0 (fixed controls asserted capped at 1.3), contrast table; 7 goldens `test/features/lobby/goldens/z_lobby_*` (idle ×2, searching ×2 with radar, error, invited 320 dark, guest) — generated with `--update-goldens` for this file only and looked at. `test/core/widgets/z_ribbon_title_test.dart` (16, no goldens): header semantics, 44 px plate, tails outside it, RTL + LTR, scale-down at 120/160/300 wide at ×2, capped at 1.3, four accents × light/dark. Writing the tests caught a real bug in the new cubit (`copyWith` reset `error`, so the level/avatar load wiped the friends error) — fixed.

**Verification:** `flutter analyze` — the only 4 findings are unused imports in `home_view.dart` (not touched here; they are in HEAD). Full suite: **461 pass / 17 fail**; a clean checkout (`git worktree add --detach … HEAD`, `.dart_tool` + `app_database.g.dart` copied, `flutter test --no-pub`) gives **389 pass / 17 fail**, and the sorted failure lists are **identical** test by test (shared widgets ×2, dock ×4, ZPlay ×5, ZSolo ×4, Home HUD ×2 — pre-existing golden diffs and the two «back button asks» dialog tests). The +72 passes are the 56 + 16 new tests. Formatted only the files touched; generated `failures/` dirs restored/cleaned; worktree removed.

**NOT verified (needs devices):** everything against a real server and a real screen — a real queue join (the long-poll, the AI fallback after 30 s, a human pair), `game_start` after `pushReplacement`, cancel against the real `DELETE /match/queue`, the 402 path from the server, `POST /challenges` + `ChallengeWatcher` entering the room on accept, the friends list with real scores, the premium avatar image loading in the disc, the level line, dark mode on a device, haptics, the radar/mascot/pulse motion in motion (goldens are single frames), the scene at real aspect ratios, and screen readers. Keyboard-open was not tested because the screen has no input.

---

## ZFriends — "A · mascot-led" Friends tab (2026-10-25) — code complete; widget tests + goldens, NOT seen on a device (no simulator/phone run, no second account)

**Source:** canvas `ZFriendsA.dc.html` (one 396×812 frame: sky scene, ribbon «دوستان» + teal add button, search box, «درخواست‌ها» card, amber invite-code card, «دوستان من» card, dock), `ZInviteConfirm.dc.html` (already built, 2026-10-17), `zmotion.js` (`down` / `up` entrances — not built, see below). `ZFriends.dc.html` (no `A`) is the legacy frame and was not used.

**Code**
- `features/friends/view/z_friends_screen.dart` is now orchestration only (~330 lines, was 823): `_FriendsFrame` (`HomeSceneBackground` + header + body slot), `_Header` (44dp spacer · `ZRibbonTitle(expand: false)` · add button), the guest / loading / failed-load cards, and `_FriendsViewState` (cubit wiring, dialogs, the existing `BlocListener`). The `BlocBuilder` now has a `buildWhen` that ignores the one-shot states (toast, navigation, coins dialog), so a raised signal no longer blanks the list for a frame.
- New `features/friends/view/widgets/`: `friends_parts.dart` (`FriendDisc`, `FriendsCardHeader`, `FriendsGlyphButton` — the 44dp add / ✓ / ✕ squares, `isolate()`), `friends_search_field.dart`, `friends_requests_card.dart`, `friends_invite_card.dart`, `friends_list_card.dart`, `friends_dialogs.dart` (`showAddFriendDialog`, `showRemoveFriendDialog`).
- New `features/friends/cubit/invite_code_cubit.dart` (`GET /referral/me`, best effort).
- **New shared widgets** (`core/widgets/`, each with its own test file, no goldens): `ZEmptyState` (mascot + title + body + optional action), `ZLoadState` (`.loading()` thinking mascot + «کمی صبر کن…»; `.error(message, onRetry)` sad mascot + retry, built on `ZEmptyState`), `ZInviteButton` (the amber «دعوت به بازی» / inert «دعوت شد», **hoisted from the lobby's private `_InviteButton`** — the lobby now uses it; its goldens did not change). `ZRibbonTitle` gained `expand` (default true = unchanged lobby look; false = the canvas's compact ribbon). `showZDialog` now pads its page by the keyboard inset so a dialog with a text field stays above the keyboard (no effect without a keyboard).
- Removed from the screen: its own header / search / row / button / pill code, the Material add-friend bottom sheet, the spinner and `_ErrorState`, and the use of `LetterTile`, `SolidCard`, `AccentButton`, `NeutralButton`, `GestureDetector` pills.
- Data / cubit (small, behaviour-preserving apart from the fixes below): `FriendModel.avatarId`; `FriendsLoaded.invited`; `GameConstants.friendInviteSentSec`.

**Real data used (verified on the Go side, not assumed)**
- `GET /friends` (`handler/friends.go`): `user_id`, `username`, `friend_since`. `GET /friends/requests`: `requester_id`, `username`, `requested_at`. `GET /challenges/pending`: challenger id/username, mode, expiry. **No presence, no records, no avatar, no premium flag.**
- This week's score per friend and — new — each friend's **premium avatar**: the friends leaderboard row (`GetFriendsLeaderboard` → `attachAvatars`) already carries `avatar_id`, and the client already fetched that endpoint for the score. `FriendsRepository.fetchFriends` now keeps it (`avatar_id` only while premium is active, so a lapsed friend shows the initial). CLAUDE.md said «not yet in the friends list»; that is now stale and updated.
- Own referral code (`GET /referral/me`) and the share text (`ShareService.shareInvite`); «۵۰ سکه» is the inviter reward the server really grants per invited user (`config.CoinReferralInviter`, claimed from the inbox). The canvas's `ZNJR-۴۸۲` is a mock — real codes are 6 letters/digits, shown left-to-right in a bidi isolate, never digit-converted so a friend can type them.

**Omitted — nothing backs it (not faked)**
- «با هم: ۴ برد · ۲ باخت», «بهترین زنجیر ۲۹», «هنوز با هم بازی نکرده‌اید» under friends: no head-to-head / best-chain endpoint → «N امتیاز این هفته» / «بدون امتیاز این هفته» (as before). (todo.md 2.6 has the backend request.)
- «۳ دوست مشترک» and «با کد دعوت تو آمده» under requests: not in `pendingRequestResponse` → «می‌خواهد دوست تو شود» / «چالش فرستاد · کلاسیک».
- Online / offline, «در بازی», presence dots: no presence anywhere.
- The count «۱۶ نفر» is the real length of the list.
- Withdrawing an invite by tapping «دعوت شد» again: no cancel endpoint (todo.md 2.1) → the sent state is inert.
- Entrance staggers (`data-e="down|up"`, 520 ms spring) are not built; the mascot/scene motion that exists elsewhere is unchanged.

**Adapted where the canvas doesn't match the product**
- Search placeholder «جست‌وجوی نام یا شناسه» → «جست‌وجوی نام دوستان»: the box filters the loaded friends by name only (no id search, no server call). Hidden when the player has no friends (nothing to search).
- Add friend is a `showZDialog` card (title, one line, field, «بی‌خیال» / «ارسال درخواست»), not the old Material sheet. It still sends the **exact username** and still reports through the cubit toasts. Empty input keeps the dialog open and sends nothing.
- The empty state, loading, failed load and guest gate are mascot cards (`ZEmptyState` / `ZLoadState`) derived from the token system — the canvas draws only the full list. Guest: «دوستانت را پیدا کن» + «ثبت‌نام رایگان» → `/login?return=/friends` (unchanged copy of the old gate, no add button).
- «دعوت به بازی» is the canvas label (the old row said «رویارویی»); it still opens the confirm dialog first (`showFriendChallengeDialog`), then `sendChallenge(id, 'classic')`. After a send the row says «دعوت شد» for `GameConstants.friendInviteSentSec` = 5 min (a UI debounce held by `FriendsCubit`; the server has no «sent challenges» read and no duplicate guard, so the app cannot know a friend declined; it wears off so a declined friend can be invited again). `insufficient_coins` → `showInsufficientCoinsDialog` and no mark.
- The invite card shows a skeleton while the code loads, «کد دعوت بارگذاری نشد» + «تلاش دوباره» if it fails (the rest of the screen is unaffected), and the share button only when there is a code. Redeeming someone else's code (`ReferralBottomSheet`) is untouched; ZProfile's own invite card is untouched (now a duplicate of this one — todo.md).
- Fixed-height controls (search, add button, ✓/✕, invite button, share, dialog buttons, ribbon) cap text scale at 1.3×; names, sub-lines, titles and bodies scale freely and wrap/ellipsize.

**Behaviour kept:** friend request by exact username, accept / decline of requests and challenges (accepting a challenge enters the room via `ChallengAccepted` → `/game`), challenge send with confirm, `insufficient_coins` dialog (also on accepting a challenge), guest → `/login?return=/friends`, the notification-permission explainer on a Friends **tab tap** (not on first load, once), the silent tab-tap reload (no spinner, failure keeps the data), the messages badge (`MessagesCubit.setPending` after every load, `friendsChanged` → reload), the auth-keyed cubits.

**Changed on purpose (flagged)**
1. **Remove friend now has a UI.** `removeFriend` existed in the cubit and repository but no screen called it. A long press on a friend row opens `showRemoveFriendDialog` (sad mascot, «X را از دوستان حذف کنی؟», «بی‌خیال» / «حذف»), there is a «حذف از دوستان» screen-reader action, and a one-line hint under the list says so. The canvas has no remove control; this is the least intrusive entry point.
2. **A failed accept / decline / remove no longer blanks the screen.** They emitted `FriendsError` (the whole list replaced by the error card); they now keep the list and toast the Persian reason like the other actions.
3. **Actions reload silently** (no full-screen spinner flash after accepting a request, sending a challenge, …).
4. **The same failure twice now toasts twice** (the repeated state used to be equal to the previous one and was swallowed).
5. The lobby's private invite button moved to `core/widgets/z_invite_button.dart` (pure move; lobby tests and goldens unchanged).

**Flagged, not fixed**
- `ZRibbonTitle` fills its slot by default, so ZLobby's ribbon is full width while the Friends canvas ribbon hugs its text. Not verified against `ZLobbyA` (todo.md).
- ZProfile's `_InviteCard` duplicates the new card.
- `_ErrorView` (`daily_screen.dart`, `z_profile_screen.dart`), `_ErrorState` (`z_board_screen.dart`) and the bare spinners elsewhere are **not** migrated to `ZLoadState` / `ZEmptyState` (only noted — todo.md §3).
- The lobby's friend rows still show initials only (no avatar), though the data is now in `FriendModel`.
- `MessagesScreen` (`/messages`, no entry point from Home) still has its own request/challenge rows and was not touched.

**Tests**
- `test/features/friends/z_friends_screen_test.dart` (79): list with real data, omitted elements stay omitted, premium avatar id, loading → list, failed load + retry, empty (search hidden, invite card kept, add dialog from the action), guest (nothing fetched, → login); requests (count badge, accept / decline request, accept challenge → `/game` args, decline, failed response keeps lists, 402 → coins dialog); add friend (trimmed name sent, keyboard send key, empty = nothing, cancel / scrim, failure toast, same failure twice); challenge (confirm sends classic, nothing before confirm, inert «دعوت شد» that wears off, survives a tab refresh, cancel, 402, other failure); remove (confirm / cancel / scrim / failure / screen-reader action); search (filter, case-insensitive, no match, clear); invite card (real code + share, skeleton while loading, retry); tab refresh (silent, failure keeps data, other tab ignored, inbox change reloads, explainer once / agree / already authorised); reduced motion (no scheduled frames); layout grid 320×568, 360×640, 393×852, 430×932 × light/dark × (busy list; empty / failed / loading / guest), text ×1.3 / 1.6 / 2.0 (fixed controls asserted capped at 1.3, names asserted scaling), add dialog at ×2.0, **keyboard open** (search focused at 375×667 and the add dialog at 320×568, field and buttons above a 260 dp keyboard) × both themes; contrast; 7 goldens `test/features/friends/goldens/z_friends_*` (list light/dark, invited 320 dark, empty light, guest light, error dark, add dialog with keyboard 320 light, remove dark) — generated with `--update-goldens` for this file only, all opened and looked at.
- `friends_cubit_test.dart` (16), `invite_code_cubit_test.dart` (3), `friends_repository_test.dart` (3: score + avatar parsing, board failure, error mapping); `core/widgets/z_empty_state_test.dart` (12), `z_load_state_test.dart` (10), `z_invite_button_test.dart` (6), three new cases in `z_ribbon_title_test.dart`. `friend_challenge_dialog_test.dart` only changed the label it taps («دعوت به بازی»).

**Verification:** `flutter analyze` — only the 4 unused-import warnings in `home_view.dart` that are in HEAD. Full suite: **593 pass / 17 fail**; a clean checkout (`git worktree add --detach <scratchpad>/base HEAD`, `.dart_tool` + `app_database.g.dart` copied, `flutter test --no-pub`) gives **461 pass / 17 fail**, and the sorted failure lists are **identical** test by test (shared widgets ×2, dock ×4, ZPlay ×5, ZSolo ×4, Home HUD ×2 — the known golden diffs and the two «back button asks» dialog tests). The +132 passes are exactly the new tests (79 + 16 + 3 + 3 + 12 + 10 + 6 + 3). Formatted only the files touched (one accidental whole-tree `dart format` reformatted 7 untouched files; the formatting diff was saved and reverse-applied, `git status` shows none of them). Generated `failures/` dirs restored/cleaned, worktree removed. Lobby tests and goldens pass unchanged after the `ZInviteButton` hoist and the `ZRibbonTitle` change.

**NOT verified (needs devices):** everything against a real server and a real screen — the friends / requests / pending-challenge calls with real data, a real friend request in both directions on two accounts, `POST /challenges` + `ChallengeWatcher` pulling the challenger into the room, accepting a challenge from this screen and entering the room, the 402 path from the server, the premium avatar image loading in the discs, the real `GET /referral/me` code and the system share sheet, the OS notification prompt after the explainer, the long-press-to-remove gesture on a phone, the soft keyboard (only simulated with a `viewInsets` inset), the dock + scene together on a real aspect ratio, dark mode on a device, haptics, screen readers, and the tab-tap refresh through the real shell (tests use a bare `TabRefreshBus`).
