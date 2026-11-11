# Sound & music (Phase 27)

Built 2026-11-11. **Not auditioned by the author and not verified on a device** — the files were synthesised and checked by numbers only (pitch, peak, loop seam, no clipping). Listen to them, and play a match on a phone, before calling it done.

## Where it lives

| Piece | Path |
|---|---|
| Generator (numpy + ffmpeg) | `scripts/audio/` — `synth.py` (instruments, reverb), `sfx.py` (31 effects), `music.py` (2 loops), `build.py` |
| Output | `client/assets/audio/sfx/*.wav` (16-bit mono 44.1 kHz, ~2 MB) · `client/assets/audio/music/{menu,game}.ogg` (stereo Vorbis q3, ~590 KB) |
| Client service | `core/services/audio_service.dart` — `Sound`, `MusicTrack`, `AudioService`, the `Sfx` facade, `AudioPlayersOutput` |
| Match sounds | `features/game/audio/game_sounds.dart` (pure `soundsForTransition(prev, curr)`) + `game_sound_listener.dart` |
| Settings | ZProfile «صدا» / «موسیقی» (`ProfileSoundSwitches`), guests too |
| Tests | `test/features/game/game_sounds_test.dart`, `test/core/services/audio_service_test.dart` |

Regenerate: `python3 scripts/audio/build.py` (all), `… tap win` (some SFX), `… --music`. Needs numpy and ffmpeg with libvorbis. Output is deterministic (fixed seed).

## Sound language

Everything is original synthesis, so there is no third-party licence to track and no credits screen. The palette is a plucked santur-like string (additive inharmonic partials, a detuned string pair, a felt-hammer transient), glassy bells and tonbak-style drum hits, all in **Shur on D** (D, E-koron, F, G, A, B♭, C; koron = a quarter-tone flat, `synth.SCALE_CENTS`). Effects use scale degrees from the same mode so they sit in tune with the music. The chain-link «clink» (`tile_land`) is the signature sound.

Music: `menu` 76 bpm × 8 bars (25 s), `game` 108 bpm × 16 bars (36 s, tonbak groove + two sparse melodies). Reverb tails are folded back onto the start, so the loops are seamless.

## Rules

- Audio is decoration: `AudioService` never throws, never gates the first frame (`init()` is unawaited after `runApp`), and `Sfx.play` / `Sfx.music` are no-ops when the service is not registered (widget tests need no setup; a screen that *reads* the service, like the profile, registers one with `test/helpers/silent_audio.dart`).
- Two independent switches (`sound_sfx_on`, `sound_music_on` in `SharedPreferences`, default on). Music pauses in the background and resumes by itself; effects are silent while backgrounded.
- Android audio focus is *not* requested and iOS uses the `ambient` category: the game never stops a podcast and respects the silent switch.
- Music scenes: `_MainShell` asks for `menu`; `GameSoundListener` asks for `game` while a match is active, silence on `GameOver` (the win / lose sting stands alone) and `menu` again on dispose.
- Package: `audioplayers` (`PlayerMode.lowLatency` per effect, a looping player for music). pub.dev is unreachable from some networks and `flutter_soloud` was not in the cache, hence this choice; `AudioOutput` is the seam if it is ever swapped.

## Playback reliability (fix of 2026-11-11, after the first device run)

First device run: effects sometimes played, sometimes not, sometimes late. Cause found in the vendored Android plugin (`third_party/audioplayers_android/.../SoundPoolPlayer.kt`, `WrappedPlayer.kt`): a low-latency (SoundPool) player never reports completion, so the native `playing` flag stays `true` after the clip ends and every later `play()`/`resume()` on that player is a silent no-op unless `stop()` ran first. `AudioPlayer.play()` does not call `stop()`. On top of that every `play()` re-ran `setVolume` and `setSource` (platform round trips), and an awaited `setPlaybackRate` preceded each key press.

`AudioPlayersOutput` now:
- **Loads every effect at init**, in the background (`_preloadAll`; keyboard / tap / match sounds first). A play that arrives before its sound is loaded waits for that load (the pool is a shared future) and is dropped only if it waited > 300 ms. A failed load is forgotten and retried on the next play.
- **Sets volume, playback rate and source once per voice**; each play is only `stop()` (skipped on a voice's first play) then `resume()`.
- **One voice per keyboard pitch**: `Sound.key` has `KeyPitch.steps` (7) voices, each with a fixed rate (0.94 … 1.06); the letter picks its voice (`pickVoice`), so the per-press rate call is gone and a letter keeps its pitch. Other sounds rotate through their voices (`tap` now has 2).
- **Serialises plays per voice** so two quick presses never interleave `stop`/`resume`.
- Logs failures at `warning`.

`AudioService`: the 25 ms same-sound guard is off for `key`, `key_back`, `key_send` (`Sound.debounce`); a sound requested before `init()` finished is queued and played when it did (if < 400 ms old, else logged and dropped); a failed init is logged once at warning.

**Timing aid (debug builds only, `kDebugMode`):** each play prints
`[sfx] key v3 call 12:00:01.234 → started +4 ms (pool wait 0 ms)` — the time of the `Sfx.play` call, the milliseconds until the platform accepted the start (the `resume()` future), the voice used; `SLOW` is appended above 80 ms. A `[sfx] preloaded 31 sounds in N ms` line shows the load time. Filter with `flutter run … | grep '\[sfx\]'`. The audible start is a few ms after the logged one.

**If it still lags or drops:** swap to `flutter_soloud ^4.1.7` behind `AudioOutput` (5.x needs `meta ^1.19`, which this Flutter SDK cannot resolve; check its Android Gradle build on the user's network first, as `audioplayers_android` needed vendoring).

## What plays when

| Where | Sounds |
|---|---|
| Every `ChunkyPressable` tap | `tap` |
| In-game Persian keyboard (on pointer-down, never debounced) | `key` (each letter has its own slight pitch), `key_back`, `key_send` |
| Own word accepted | `accepted`, or `streak` (3rd in a row on), or `long_word` (≥ 7 letters), + `tile_land` |
| Opponent's / AI's word | `opp_word` + `tile_land` |
| Last 5 s of my turn | `tick` |
| Life lost / shield armed or spent / hint / extra time / opponent taunt | `life_lost` / `shield` / `hint` / `extra_time` / `taunt` |
| Online match found | `match_found` |
| Game over | `win` / `lose` (1v1), `timeout` / `rejected` (solo, vs-AI), nothing when the player ended it |
| «جام» arrives after a 1v1 | `rating_up` / `rating_down` |
| Dialog opens / closes (`showZDialog`) | `dialog_open` / `dialog_close` |
| `ZToast` | `coin` (coin kind), `toast` (success kind); info and error are silent |
| Bottom-nav tap | `tab` |
| Prize claimed | `claim` |
| Continue with coins | `coin_spend` |

Built but **not wired**: `level_up` (no level-up event exists on the client yet), `coin` on a rewarded-ad payout. Haptics are separate and unchanged (always on, no setting).

## To do

- Listen to everything; tune `PEAKS` in `sfx.py` / `rms` in `music.py` and the `Sound.volume` / `MusicTrack.volume` mix levels.
- Device check (after the 2026-11-11 reliability fix, still **unverified**): latency of the keyboard sound on a low-end Android, overlapping effects, music pause/resume across a call or app switch, iOS silent switch.
- Goldens of ZProfile change (a new row of switches) — regenerate with `--update-goldens` on a machine where the goldens pass.
