"""Two seamless, cheerful music loops in F major: a relaxed, sunny `menu` loop and
a bouncy `game` loop built from the same hook and the same timbres. Both are
rendered with a short reverb whose tail is folded back onto the start, so the
loop point is inaudible.

Everything you are likely to want to tweak is in the KNOBS block below.

Why F major (and not the Shur on D of the sound effects)
--------------------------------------------------------
The 31 effects are written in Shur on D (D E-koron F G A Bb C). Without the
koron, those seven notes are exactly the notes of F major (D natural minor is
F major's relative minor). So the music is in F major, with F as home:
- every pitched effect note (accepted G+D, streak D-F-A-D, key_send A+D, the
  clink of tile_land at ~D7/Bb7/F8) is a note of the music's scale, so nothing
  clashes, while the *feel* of the music is major (F is the tonic, only the
  major chords I, IV and V are used, the hook is pentatonic: no minor third);
- the only effect notes outside F major are E-koron (a quarter-tone flat E, in
  `long_word` as a 45 ms passing note and in `lose`, which plays with the music
  already stopped) and the 1320 Hz `tick` (E6, a leading tone). The melody and
  bells therefore never use the 1250-1450 Hz band (E6/F6), see `_guard`.
`synth.SCALE_CENTS` and `synth.TONIC` are untouched; the music has its own
scale below. Same tuning reference (A = 440, equal temperament).
"""
from __future__ import annotations

import numpy as np

import synth
from synth import (
    SR, bandpass, bell, exp_env, fade, n_samples, noise, pad, place, reverb,
    santur, tonbak_dum, tonbak_tak,
)

# ============================================================== KNOBS
TONIC_HZ = 349.228  # F4. Do not move it without re-reading the clash note above.
MODES = {
    "major": [0, 200, 400, 500, 700, 900, 1100],       # the default, clash-free
    "mixolydian": [0, 200, 400, 500, 700, 900, 1000],  # flat 7: Eb sits a quarter tone from E-koron
    "lydian": [0, 200, 400, 600, 700, 900, 1100],      # B natural clashes with the effects' Bb
}
MODE = "major"

# Per-track settings. gains are linear multipliers on each layer.
MENU = dict(
    bpm=96, bars=12,
    wet=0.16, size=0.60,        # reverb amount / room size (old loops: 0.35 / 1.2)
    melody=1.0, bell=0.8, arp=0.9, pad=0.8, bass=1.0, perc=1.0,
    bright=0.78,                # santur brightness for the melody (0..1)
)
GAME = dict(
    bpm=128, bars=20,
    wet=0.10, size=0.45,
    melody=1.0, bell=0.8, stab=1.0, pad=0.5, bass=1.0, perc=1.0,
    bright=0.74,
)
# Perceived loudness (A-weighted RMS) of both loops; the old loops were ~0.048.
LOUDNESS = 0.048

# The hook: scale degrees (1 = F4, 8 = F5, 12 = C6) and beats. It always rises or
# leaps up, then ends on a high note. A phrase fits one bar of 4 beats.
PHRASES = {
    "hook": [(5, .5), (8, .5), (10, 1), (9, .5), (10, .5), (12, 1)],    # C F A G A C  (over F)
    "ans":  [(8, .5), (10, .5), (12, 1), (10, .5), (12, .5), (13, 1)],  # F A C A C D  (over F)
    "iv":   [(8, .5), (11, .5), (13, 1), (11, .5), (12, .5), (13, 1)],  # F Bb D Bb C D (over Bb)
    "v":    [(5, .5), (9, .5), (12, 1), (9, .5), (11, .5), (12, 1)],    # C G C G Bb C (over C)
    "run":  [(5, .5), (6, .5), (7, .5), (8, .5), (9, .5), (10, .5), (11, .5), (12, .5)],  # rising scale
}

# Chords per bar as scale degrees of the root (1 = F, 4 = Bb, 5 = C).
MENU_CHORDS = [1, 1, 4, 5] + [1, 4, 1, 5] + [1, 1, 4, 5]
MENU_MELODY = ["hook", "ans", "iv", "v"] + ["hook", None, "ans", "v"] + ["hook", "ans", "iv", "v"]

GAME_CHORDS = [1, 1, 4, 5] + [1, 4, 1, 5] + [1, 1, 4, 5] + [4, 5, 1, 1] + [1, 4, 5, 5]
GAME_MELODY = (
    ["hook", "ans", "iv", "v"]
    + ["hook", None, "ans", None]
    + ["hook", "ans", "iv", "v"]
    + [None, None, None, None]            # breather: bass, drums and bell pings only
    + ["hook", "iv", "v", "run"]
)
GAME_BELL_ECHO = {8, 9, 10, 11, 16, 17, 18, 19}  # bars where a bell doubles the last note

TAIL = 4.0  # seconds of reverb tail folded onto the start

_MODE_CENTS = MODES[MODE]


def mhz(deg: int) -> float:
    """1-based scale degree of the music's own mode (any octave: 8 = F5) -> Hz."""
    octave, idx = divmod(deg - 1, 7)
    return TONIC_HZ * 2 ** ((_MODE_CENTS[idx] + 1200 * octave) / 1200)


def _guard(deg: int) -> int:
    """The `tick` effect is a 1320 Hz sine (E6): keep melodic notes away from it."""
    f = mhz(deg)
    assert not (1250 <= f <= 1450), f"degree {deg} = {f:.0f} Hz collides with the tick effect"
    return deg


# ============================================================ instruments


def bass_pluck(freq: float, dur: float = 0.45, vel: float = 1.0) -> np.ndarray:
    """Round plucked bass: a sine with a quick pitch settle and strong 2nd/3rd
    harmonics, so it still reads on a phone speaker."""
    n = n_samples(dur)
    t = np.arange(n) / SR
    f = freq * (1 + 0.03 * np.exp(-t / 0.015))
    ph = 2 * np.pi * np.cumsum(f) / SR
    out = np.sin(ph) + 0.55 * np.sin(2 * ph) * np.exp(-t / 0.14) + 0.30 * np.sin(3 * ph) * np.exp(-t / 0.08)
    return fade(out * exp_env(n, 0.004, 0.20) * vel * 0.55, 0.0, 0.03)


def jingle(vel: float = 1.0, dur: float = 0.09) -> np.ndarray:
    """The zils of a daf: a short burst of high filtered noise."""
    n = n_samples(dur)
    return fade(bandpass(noise(dur), 5500, 11000) * exp_env(n, 0.0004, 0.022) * vel * 0.6, 0.0, 0.01)


# ================================================================== Loop


class Loop:
    def __init__(self, bpm: float, bars: int):
        self.spb = 60.0 / bpm
        self.beats = bars * 4
        self.length = self.beats * self.spb
        n = n_samples(self.length + TAIL)
        self.dry_l, self.dry_r = np.zeros(n), np.zeros(n)
        self.pad = np.zeros(n)
        self.perc = np.zeros(n)

    def add(self, sig, beat, pan=0.0, gain=1.0, bus="notes"):
        at = beat * self.spb
        l, r = gain * (1 - max(0, pan)), gain * (1 + min(0, pan))
        if bus == "pad":
            place(self.pad, sig, at, gain)
        elif bus == "perc":
            place(self.perc, sig, at, gain)
        else:
            place(self.dry_l, sig, at, l)
            place(self.dry_r, sig, at, r)

    def render(self, wet: float, size: float) -> np.ndarray:
        wet_l = reverb(self.dry_l + self.pad, wet, size, 0)
        wet_r = reverb(self.dry_r + self.pad, wet, size, 1)
        l = wet_l + self.perc * 0.9
        r = wet_r + self.perc * 0.9
        out = np.stack([l, r], axis=1)
        n = n_samples(self.length)
        tail = out[n:]
        out = out[:n].copy()
        out[: len(tail)] += tail  # fold the tail: seamless loop
        out *= LOUDNESS / max(1e-9, _a_rms(out))
        return np.tanh(out * 1.1) / 1.1


def _a_weight(f: np.ndarray) -> np.ndarray:
    f2 = f ** 2
    num = 12194 ** 2 * f2 ** 2
    den = (f2 + 20.6 ** 2) * np.sqrt((f2 + 107.7 ** 2) * (f2 + 737.9 ** 2)) * (f2 + 12194 ** 2)
    return num / np.maximum(den, 1e-12)


def _a_rms(x: np.ndarray) -> float:
    """A-weighted RMS of a stereo signal (about how loud it sounds)."""
    m = x.mean(axis=1)
    f = np.fft.rfftfreq(len(m), 1 / SR)
    s = np.fft.rfft(m) * _a_weight(f) / _a_weight(np.array([1000.0]))[0]
    return float(np.sqrt(np.sum(np.abs(s) ** 2) * 2) / len(m))


# ================================================================ writing


def phrase_beats(notes) -> float:
    return sum(b for _, b in notes)


def syncopate(notes):
    """Lilt: the first one-beat note becomes an eighth plus an eighth rest."""
    out, done = [], False
    for deg, b in notes:
        if not done and b == 1:
            out += [(deg, .5), (None, .5)]
            done = True
        else:
            out.append((deg, b))
    return out


def melody(loop: Loop, notes, start_beat, bright, gain=1.0, pan=0.0, bell_last=0.0):
    """Plays a phrase with plucked santur; optionally doubles its last note with a bell."""
    t = start_beat
    last = None
    for deg, beats in notes:
        if deg is not None:
            _guard(deg)
            vel = (0.95 if beats >= 1 else 0.8) * gain
            dur = min(1.6, beats * loop.spb * 1.5 + 0.3)
            loop.add(santur(mhz(deg), dur, vel, bright), t, pan)
            last = (deg, t)
        t += beats
    if bell_last and last:
        loop.add(bell(mhz(last[0]), 1.6, bell_last), last[1], -0.3)
    return t


def lay_melody(loop, plan, cfg, sync, echo=()):
    for bar, name in enumerate(plan):
        if name is None:
            continue
        notes = PHRASES[name]
        if sync and name != "run":
            notes = syncopate(notes)
        assert abs(phrase_beats(notes) - 4) < 1e-9, name
        melody(loop, notes, bar * 4, cfg["bright"], cfg["melody"], -0.1,
               bell_last=0.22 * cfg["bell"] if bar in echo else 0.0)


def triad(root: int, base: int = 0):
    return [root + base, root + base + 2, root + base + 4]


def lay_bass(loop, chords, steps, cfg):
    """steps: (eighth-note step in the bar, octave offset in degrees, velocity)."""
    for bar, r in enumerate(chords):
        for step, up, vel in steps:
            loop.add(bass_pluck(mhz(r - 14 + up), 0.42, vel * cfg["bass"]), bar * 4 + step * 0.5, 0.0)


def lay_perc(loop, bars, hits, jingles, cfg, fill=None):
    """hits: (eighth step, 'd'|'t', vel). jingles: (step, vel). fill: extra hits on every 4th bar."""
    for bar in range(bars):
        base = bar * 4
        pat = list(hits) + (fill if (fill and bar % 4 == 3) else [])
        for step, kind, v in pat:
            sig = tonbak_dum(v) if kind == "d" else tonbak_tak(v)
            loop.add(sig, base + step * 0.5, bus="perc", gain=0.30 * cfg["perc"])
        for step, v in jingles:
            loop.add(jingle(v), base + step * 0.5, bus="perc", gain=0.20 * cfg["perc"])


def _seed(n: int) -> None:
    synth._rng = np.random.default_rng(n)  # same output whatever was rendered before


# ================================================================= menu


def build_menu() -> Loop:
    cfg = MENU
    _seed(2701)
    loop = Loop(cfg["bpm"], cfg["bars"])
    assert len(MENU_CHORDS) == len(MENU_MELODY) == cfg["bars"]

    # soft pad: one chord per bar, swelling over a bar and a half
    for bar, r in enumerate(MENU_CHORDS):
        for k, deg in enumerate(triad(r)):
            loop.add(pad(mhz(deg), 4 * loop.spb + 0.8, 0.30 * cfg["pad"], 0.7), bar * 4, bus="pad")

    # gentle rising arpeggio in the warm register under the tune
    pattern = (0, 1, 2, 3, 1, 2, 3, 2)
    for bar, r in enumerate(MENU_CHORDS):
        tones = [r - 7, r - 5, r - 3, r]
        for i, p in enumerate(pattern):
            loop.add(santur(mhz(tones[p]), 0.7, 0.20 * cfg["arp"], 0.5), bar * 4 + i * 0.5, 0.3 * (1 if i % 2 else -1))

    # bass on the downbeat and the "and" of 3
    lay_bass(loop, MENU_CHORDS, [(0, 0, 0.9), (5, 0, 0.6)], cfg)

    lay_melody(loop, MENU_MELODY, cfg, sync=False, echo={8, 9, 10, 11})

    # light daf / tonbak: dum . tak . | . dum tak .  and a faint zil on every eighth
    lay_perc(loop, cfg["bars"],
             hits=[(0, "d", 0.6), (3, "t", 0.35), (5, "d", 0.45), (6, "t", 0.4)],
             jingles=[(i, 0.18 if i % 2 else 0.10) for i in range(8)], cfg=cfg)
    return loop


def menu() -> np.ndarray:
    """96 bpm x 12 bars = 30 s. Relaxed, sunny: hook on santur over a soft pad and arpeggio."""
    return build_menu().render(MENU["wet"], MENU["size"])


# ================================================================= game


def build_game() -> Loop:
    cfg = GAME
    _seed(2702)
    loop = Loop(cfg["bpm"], cfg["bars"])
    assert len(GAME_CHORDS) == len(GAME_MELODY) == cfg["bars"]

    # very light pad: keeps the harmony alive between drum hits, esp. in the sparse bars
    for bar, r in enumerate(GAME_CHORDS):
        for deg in triad(r):
            loop.add(pad(mhz(deg), 4 * loop.spb + 0.6, 0.30 * cfg["pad"], 0.5), bar * 4, bus="pad")

    # bass 3 + 3 + 2 (steps 0, 3, 6 of the bar's eighth-note grid)
    lay_bass(loop, GAME_CHORDS, [(0, 0, 1.0), (3, 0, 0.8), (6, 7, 0.65)], cfg)

    # chord stabs between the bass hits (steps 2 and 5), mid register, alternating sides
    for bar, r in enumerate(GAME_CHORDS):
        voicing = [r - 5, r - 3, r]
        for step, vel, pan in ((2, 0.55, -0.25), (5, 0.45, 0.25)):
            for k, deg in enumerate(voicing):
                loop.add(santur(mhz(deg), 0.22, 0.20 * vel * cfg["stab"], 0.45), bar * 4 + step * 0.5 + k * 0.015, pan)

    # breather: a bell ping on each downbeat (the fifth of the chord)
    for bar in range(12, 16):
        loop.add(bell(mhz(GAME_CHORDS[bar] + 4), 1.8, 0.20 * cfg["bell"]), bar * 4, 0.2)

    lay_melody(loop, GAME_MELODY, cfg, sync=True, echo=GAME_BELL_ECHO)

    # tonbak + daf, syncopated 3+3+2:  dum . tak dum tak . dum tak, zils on the offbeats
    lay_perc(loop, cfg["bars"],
             hits=[(0, "d", 0.9), (2, "t", 0.6), (3, "d", 0.7), (4, "t", 0.55), (6, "d", 0.8), (7, "t", 0.35)],
             jingles=[(1, 0.35), (3, 0.5), (5, 0.35), (7, 0.55)], cfg=cfg,
             fill=[(7.5, "t", 0.5)])
    return loop


def game() -> np.ndarray:
    """128 bpm x 20 bars = 37.5 s. Bouncy: 3+3+2 bass and tonbak, offbeat stabs, a sparse hook."""
    return build_game().render(GAME["wet"], GAME["size"])
