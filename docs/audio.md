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

## What plays when

| Where | Sounds |
|---|---|
| Every `ChunkyPressable` tap | `tap` |
| In-game Persian keyboard (on pointer-down) | `key` (each letter has its own slight pitch), `key_back`, `key_send` |
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
- Device check: latency of the keyboard sound on a low-end Android, overlapping effects, music pause/resume across a call or app switch, iOS silent switch.
- Goldens of ZProfile change (a new row of switches) — regenerate with `--update-goldens` on a machine where the goldens pass.
