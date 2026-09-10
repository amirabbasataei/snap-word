# REDESIGN_PLAN.md — زنجیر Visual Redesign

Screen-by-screen plan for implementing the Claude Design canvas in Flutter.

**Design source:** `https://claude.ai/design/p/4a90de7c-3340-476f-922d-213a9dcd6307` (`Zanjir.dc.html`)
**Access note:** WebFetch/browser access to `claude.ai/design/...` URLs returns 403 (needs claude.ai login not available to those tools). The reliable path is the `DesignSync` tool: `method: "get_file"` with `projectId: "4a90de7c-3340-476f-922d-213a9dcd6307"` and `path: "<File>.dc.html"` — this works even though `list_projects` doesn't surface this project (it's a canvas, not a design-system project). Per-screen files confirmed present via `list_files`: `ZHome`, `ZSolo`, `ZPlay`, `ZOver`, `ZLobby`, `ZVersus`, `ZDailyBefore`, `ZDailyAfter`, `ZBoard`, `ZProfile`, `ZFriends` (each `<Name>.dc.html`), plus `Zanjir.dc.html` (token sheet + screen imports) and `Vajechin Word Chain.dc.html`.
**Status:** Decisions made (see §1). Stage 1 (Foundation) in progress.
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
| 2 | **Wager + turn-length picker** — 10/15/20s, بدون شرط / ۲۰ سکه / ۱۰۰ سکه | Turn timer fixed per variant (15s / 8s); no wagering in the coin economy | ZLobby |
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
2. **Wager + turn-length picker (ZLobby)** — Build exactly as designed, no placeholder gating.
3. **Best-of-5 rounds (ZVersus)** — Build the visual UI as designed (round indicator, "دست ۳ از ۵"), wired to a placeholder. Round count is a **fixed constant (best of 5)**, not lobby-configurable — confirmed by the user; not a canvas-driven decision (canvas access wasn't needed for this one in the end). Real round-tracking logic (WS protocol + Go backend: round wins, round transitions, match-level winner) is separate follow-up backend work, not part of this visual redesign.
4. **Long-word bonus** — Adopted as designed.
5. **Levels & badges (ZProfile)** — Rendered as designed, wired to placeholders. Backend work (schema + fields) is follow-up.
6. **Referral codes** — Rendered as designed, wired to placeholders. Backend work is follow-up.

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

**ZSolo** ← new `features/game/view/z_solo_screen.dart`. Vertical spine chain renderer: each row is a `LetterTile` (accent cycling indigo→teal→amber→coral by index) + word + `"index · +score"` meta, opacity/size ramped by distance from the most recent word (`_rampSizes`/`_rampFonts`/`_rampOpacity`, floor at the oldest step for long chains) with the spine line rendered as small per-gap segments (not one absolutely-positioned line — the canvas's continuous line is always occluded by the tiles anyway, so per-gap segments reproduce it exactly without fighting `ListView`'s scroll extent). The most recent word gets the raised/embossed tile + a `"+score · تازه"` tint chip. Stat strip: طول زنجیر (`wordChain.length`), رکورد تو (`StatsDao.bestMatchStreak`, fetched once in `initState`), and either lives pips (classic) or remaining match time (time_attack, third tile swaps since lives don't deplete outside classic — see Lives below).

**ZPlay** ← new `features/game/view/z_play_screen.dart`. Chat-bubble renderer: opponent bubbles (`surface` + border, aligned to the RTL start/right side) always show the difficulty label; "you" bubbles (`inkSurface` fill, aligned end/left) only show a "تو · +score" label on the most recent one, matching the canvas exactly. A real bug caught before it shipped: `wordScores` only ever accumulates the player's *own* words (see `GameBloc._onWordSubmitted`), so it isn't parallel to `wordChain` once the AI's interspersed words are counted — a bubble's score has to be looked up by a separate "my move" counter, not by chain index (`z_play_screen.dart`'s `_BubbleChain.build` tracks `myMoveIndex` for this). Footer has 4 power-up slots (hint/freeze/extra-time/shield) vs. ZSolo's 3 — freeze only applies with an opponent.

**ZOver** ← new `features/game/view/z_over_screen.dart`. Merges what used to be two separate screens (the `ContinuePrompt` overlay and `_GameOverScreen`) into the canvas's single design: `inkSurface` hero band (inverts to cream in dark mode, by design — see the token sheet's note on `inkSurface`) with 3 decorative tumbling tiles, a score card, a near-miss bar ("N کلمهٔ دیگر تا شکستن رکوردت مانده بود") or a new-record banner (mutually exclusive, both driven by `StatsDao.bestMatchStreak` vs. `chainLength`), chain-tail chips, then either the continue actions (ad/coins/share, only while `canContinue && !isSaved && continueTimeRemaining > 0`) or just share+home. Reused for both solo and vs-AI game-overs; **routes only when `state.opponentType != null`** — true multiplayer's WS-driven `GameOver` never sets that field (see `_handleWsLossEvent`/`_handleWsGameOver` in `game_bloc.dart`), so it's the correct discriminator (the existing `GameOver.isMultiplayer` getter was the wrong one to reuse here — despite its name it's also `true` for vs-AI once `opponentScore > 0`). Multiplayer keeps the legacy `ContinuePrompt`/`_GameOverScreen` pair untouched (Stage 4). Daily-mode `GameOver`s are intercepted first and just show the existing saving-spinner, since ZDailyAfter (Stage 3) owns the real result screen. Continue price fixed at `GameConstants.continueCostCoins` (25), not the canvas's 50, per the decision already recorded above. `ShareService` gained a small `shareMatch({score, chainLength})` (the canvas's "هم‌رسانی نتیجه" button) alongside the existing daily-only `shareDaily`.

**Lives (adopted per decision 1, scoped down from the plan):** implemented in `GameBloc` for **solo + classic mode only** (`GameConstants.soloLives = 2`) — not vs-AI (ZPlay's canvas has no lives strip at all, unlike ZSolo/ZVersus/ZDailyBefore) and not time_attack (existing early-finalize-on-any-mistake behavior for time_attack was left untouched rather than silently extended by the lives change — flagged as a pre-existing spec/code mismatch below, not fixed here). A mistake in solo/classic with lives remaining decrements `GameActive.livesRemaining` and keeps the match going (`GameState.lastMistakeReason` surfaces a transient "you lost a life" banner); the match only actually ends via the existing `_handleGameOver` path once lives hit 0. True multiplayer/AI lives (decision 1's full scope) are deferred to Stage 4.

**Long-word bonus (decision 4):** added to `GameBloc._calculateScore` only (words ≥ `GameConstants.longWordBonusMinLength` (7) double their score) — Flutter-side only, since solo/AI never touch the Go backend's scorer (per CLAUDE.md, solo/AI run entirely on-device). The Go backend scorer is unchanged; that's a separate, not-yet-scoped follow-up for when multiplayer picks up this bonus too.

**Small pre-existing gap fixed in passing:** `StatsDao.recordGameResult` never actually updated `bestMatchStreak` (it just carried the existing value forward unchanged) — meaning "your record" had no real data source. Added a `chainLength` parameter, now `max(existing, chainLength)`; `GameBloc._saveAndEmitFinal` passes `over.chainLength`.

**Flagged, not fixed (out of this stage's scope):**
- `GameBloc._onWordSubmitted`'s validation regex (`^[a-z]+$`) only accepts Latin lowercase letters, meaning as written it would reject every real Persian word before ever reaching `DictionaryService.isValid` — yet `DictionaryService` itself (and its test suite) is fully Persian/ZWNJ-aware. This looks like a leftover from an earlier English prototype of the bloc that was never updated when the dictionary went Persian; it's a Phase 5 (engine)/Phase 2 (game feature) concern, not a Phase 17 visual one, so it was left untouched and is called out here rather than silently patched.
- Time Attack currently ends the match on the player's very first mistake (`_onWordSubmitted`/`_onTimerTicked` call `_handleGameOver`/`_finalizeGame` unconditionally outside the classic-lives branch), which doesn't match CLAUDE.md's "Time Attack ends only when the 90s total runs out" — pre-existing, not introduced or fixed here.
- ZPlay's ادامه‌"انجماد حریف" (freeze) power-up, like Extra Time and Shield, is rendered per the canvas but left as a disabled/inert placeholder (`enabled: false`), matching the current app's existing behavior for those three — the power-up inventory/spend system is Phase 16 territory and wasn't touched.

**Verification:** `flutter analyze` and `flutter test` clean throughout. Actually launched on the same iOS 26 simulator used for ZHome (`flutter run`), both themes, all three screens, via a temporary preview-harness route (`/_preview/:screen?theme=`) that rendered each screen directly off a hand-built `GameActive`/`GameOver` fixture through the real DI container — reverted before commit, `git diff` on `app_router.dart` confirmed clean. Caught and fixed two real bugs this way: the hint power-up's "؟" glyph had no indigo badge behind it (invisible white-on-cream) — now `ZHintIcon`; and `ZWordInput`'s `TextField` was silently inheriting the legacy dark theme's navy `filled` decoration through the ambient `InputDecorationTheme` — fixed with an explicit `filled: false`. A few things that looked like bugs at a glance turned out not to be on closer inspection (worth recording so they aren't re-litigated): the "‎+score · index" meta text's bidi ordering renders correctly once actually zoomed in; Vazirmatn's isolated-form "ه" glyph looks like a teardrop/almost-"۵" shape at small sizes but is byte-verified correct in every case checked.

---

## 4. Stage 3 — Daily Challenge

`ZDailyBefore` / `ZDailyAfter` ← `features/daily/view/daily_screen.dart` (786 ln).

Cubit and repository untouched. New: 96px seed-letter hero on indigo, three-row rules list, teal result band with percentile, chain chips with «+۱۱ دیگر» overflow, live countdown to the next challenge.

---

## 5. Stage 4 — Multiplayer

- **ZLobby** ← `features/lobby/view/lobby_screen.dart` (462 ln) — versus card on `inkSurface`, matchmaking progress dots, room-code invite row, recent-opponents list. Wager / turn-length pickers gated on conflict #2.
- **ZVersus** ← `game_screen.dart` `_MultiplayerHeader` — dual score header, turn banner with inline timer, typing indicator (**new WS event — not in the protocol**), locked input state («منتظر نوبت…»).

---

## 6. Stage 5 — Secondary screens

- **ZBoard** ← `features/leaderboard/view/leaderboard_screen.dart` (693 ln) — three staggered podium pedestals, rank rows, sticky self-row on `inkSurface`. 4 tabs vs. spec's 2 → see conflict table.
- **ZProfile** ← `features/profile/view/profile_screen.dart` (789 ln) — 2×2 stat grid, level progress bar, badge row, settings list with the dark-mode toggle.
- **ZFriends** ← `features/friends/view/friends_screen.dart` (664 ln) — requests / online / offline sections, which map cleanly onto the existing cubit.

---

## 7. Stage 6 — Undesigned screens

`login_screen.dart`, `register_screen.dart`, `tutorial_screen.dart` (437 ln), and `continue_prompt.dart` have **no reference images** in the canvas.

Per `CLAUDE.md` ("if a detail is ambiguous, match the overall visual style and spacing of the nearest reference image"), derive these from the token system rather than inventing layouts.

---

## 8. Stage 7 — Tests

- Existing golden tests for `WordChainList` and `TimerBar` will break **by design** — re-baseline them.
- Add light + dark goldens for each shared widget in `core/widgets/`.
- Add a token-coverage check that fails on hardcoded `Color(0x…)` literals inside `features/`.

---

## 9. Open decisions — resolved

Both prior open items are settled (see §1 Decisions and the header note above): the six conflicts are decided, and Phase 17 is recorded in CLAUDE.md and PLAN.md.
