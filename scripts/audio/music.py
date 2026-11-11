"""Two seamless, cheerful music loops in F major, from one santur / bell / tonbak
palette and one idea (a rising pentatonic figure over the chords I, IV and V):

  menu  105 bpm 4/4  swung, light and lilting          (the four tabs)
  game  120 bpm 6/8  Bandari / folk-dance lilt, 80 dotted-beat pulses a minute (a match)

Each is rendered with a short reverb whose tail is folded back onto the start, so
the loop point is inaudible. Tempo is 210 / 240 eighth notes a minute: nothing
drags and nothing rushes. Register: melodies live between D4 and C6 (centre about
D5), basses between B-flat2 and F3, so nothing is shrill and nothing needs a
subwoofer.

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
    bpm=105, bars=16,
    wet=0.14, size=0.55,
    melody=1.0, bell=0.8, comp=1.0, pad=0.5, bass=1.0, perc=1.0,
    bright=0.68,
    swing=2 / 3,                # where the off-beat eighth falls inside the beat (0.5 = straight)
)
GAME = dict(
    bpm=120, bars=24, bpb=3,    # 6/8 = three quarter-note beats of two eighths per bar
    wet=0.11, size=0.45,
    melody=1.0, bell=0.8, stab=1.0, pad=0.5, bass=1.0, perc=1.0,
    bright=0.70,
)
# Perceived loudness (A-weighted RMS) of both loops (the very first pair was ~0.048).
LOUDNESS = 0.048

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
    def __init__(self, bpm: float, bars: int, bpb: int = 4):
        self.spb = 60.0 / bpm
        self.beats = bars * bpb
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


def triad(root: int, base: int = 0):
    return [root + base, root + base + 2, root + base + 4]


def _seed(n: int) -> None:
    synth._rng = np.random.default_rng(n)  # same output whatever was rendered before


# ============================================================ writing the loops
# Phrases are written over an F chord (degree 1); `fit` carries them to IV and V.
FIT = {1: 0, 4: -4, 5: -3}   # chord root -> diatonic shift that keeps a phrase on that chord's tones


def fit(notes, root: int):
    return [(None if d is None else d + FIT[root], b) for d, b in notes]


def bass_root(r: int) -> int:
    """Bass degree for chord root r: F3 / B-flat2 / C3 (175, 117, 131 Hz)."""
    return r - 7 if r <= 3 else r - 14


def bass_fifth(r: int) -> int:
    return bass_root(r) - 3 if r == 1 else bass_root(r) + 4   # C3 / F3 / G3


def swung(t: float, amount: float) -> float:
    """Moves an off-beat eighth (x.5) to x + amount; everything else stays."""
    frac = t % 1
    return t - frac + amount if abs(frac - 0.5) < 1e-9 else t


def lay_phrases(loop, plan, chords, phrases, cfg, bpb, echo=(), swing=None):
    for bar, name in enumerate(plan):
        if name is None:
            continue
        notes = phrases[name]
        if name not in ("run", "end", "brun", "bend"):
            notes = fit(notes, chords[bar])
        else:
            assert chords[bar] == (5 if name in ("run", "brun") else 1), (bar, name)
        assert abs(phrase_beats(notes) - bpb) < 1e-9, (name, phrase_beats(notes))
        t = bar * bpb
        last = None
        for deg, beats in notes:
            if deg is not None:
                _guard(deg)
                at = swung(t - bar * bpb, swing) + bar * bpb if swing else t
                vel = (0.95 if beats >= 1 else 0.8) * cfg["melody"]
                dur = min(1.6, beats * loop.spb * 1.5 + 0.3)
                loop.add(santur(mhz(deg), dur, vel, cfg["bright"]), at, -0.1)
                last = (deg, at)
            t += beats
        if bar in echo and last:
            loop.add(bell(mhz(last[0]), 1.6, 0.22 * cfg["bell"]), last[1], -0.3)


def lay_bass_low(loop, chords, steps, cfg, bpb, swing=None):
    """steps: (beat in the bar, 'root' | 'fifth', velocity, length in s)."""
    for bar, r in enumerate(chords):
        for beat, kind, vel, dur in steps:
            deg = bass_root(r) if kind == "root" else bass_fifth(r)
            at = bar * bpb + (swung(beat, swing) if swing else beat)
            loop.add(bass_pluck(mhz(deg), dur, vel * cfg["bass"]), at, 0.0)


def lay_perc_beats(loop, bars, bpb, hits, jingles, cfg, swing=None, fill=None):
    """hits: (beat in the bar, 'd'|'t', vel); jingles: (beat, vel). fill adds hits on every 4th bar."""
    for bar in range(bars):
        pat = list(hits) + (fill if (fill and bar % 4 == 3) else [])
        for beat, kind, v in pat:
            sig = tonbak_dum(v) if kind == "d" else tonbak_tak(v)
            at = bar * bpb + (swung(beat, swing) if swing else beat)
            loop.add(sig, at, bus="perc", gain=0.30 * cfg["perc"])
        for beat, v in jingles:
            at = bar * bpb + (swung(beat, swing) if swing else beat)
            loop.add(jingle(v), at, bus="perc", gain=0.20 * cfg["perc"])


def lay_pad(loop, chords, bpb, gain):
    for bar, r in enumerate(chords):
        for deg in triad(r):
            loop.add(pad(mhz(deg), bpb * loop.spb + 0.7, 0.30 * gain, 0.6), bar * bpb, bus="pad")


# ---------------------------------------------------------------- menu

MENU_PHRASES = {
    "k1":  [(3, .5), (5, .5), (8, 1), (6, .5), (8, .5), (10, 1)],             # A C F D F A
    "k2":  [(5, .5), (8, .5), (10, .5), (9, .5), (8, .5), (10, .5), (12, 1)], # C F A G F A C
    "end": [(3, .5), (5, .5), (8, 1), (10, 2)],                               # A C F  A (held)
    "run": [(d, .5) for d in range(1, 9)],                                    # F up the scale to F
}
MENU_CHORDS = [1, 5, 4, 1] + [1, 5, 4, 5] + [4, 1, 5, 1] + [1, 5, 4, 5]
MENU_PLAN = (["k1", "k1", "k1", "end"] + ["k1", None, "k2", "k1"]
             + ["k2", "k2", "k2", "end"] + ["k1", "k1", "k2", "run"])
MENU_ECHO = {3, 11}


def build_menu() -> Loop:
    cfg = MENU
    _seed(2703)
    sw = cfg["swing"]
    loop = Loop(cfg["bpm"], cfg["bars"])
    assert len(MENU_CHORDS) == len(MENU_PLAN) == cfg["bars"]

    lay_pad(loop, MENU_CHORDS, 4, cfg["pad"])
    # bass: root on 1, fifth on 3
    lay_bass_low(loop, MENU_CHORDS, [(0, "root", 0.9, 0.5), (2, "fifth", 0.7, 0.45)], cfg, 4)
    # chord "plinks" on the swung off-beats after 2 and 4, mid register, alternating sides
    for bar, r in enumerate(MENU_CHORDS):
        for beat, pan in ((1.5, -0.25), (3.5, 0.25)):
            at = bar * 4 + swung(beat, sw)
            for k, deg in enumerate([r - 5, r - 3, r]):
                loop.add(santur(mhz(deg), 0.24, 0.20 * 0.55 * cfg["comp"], 0.45), at + k * 0.012, pan)
    lay_phrases(loop, MENU_PLAN, MENU_CHORDS, MENU_PHRASES, cfg, 4, MENU_ECHO, sw)
    # light kit: dum on 1 and the swung "and" of 3, tak on 2 and 4, faint zils on the off-beats
    lay_perc_beats(loop, cfg["bars"], 4,
                   hits=[(0, "d", 0.6), (1, "t", 0.4), (2.5, "d", 0.45), (3, "t", 0.4)],
                   jingles=[(b + 0.5, 0.2) for b in range(4)] + [(b, 0.08) for b in range(4)],
                   cfg=cfg, swing=sw)
    return loop


def menu() -> np.ndarray:
    """105 bpm x 16 bars = 36.6 s. Swung and lilting: plinking off-beats, low-slung tune."""
    return build_menu().render(MENU["wet"], MENU["size"])


# ---------------------------------------------------------------- game

GAME_PHRASES = {   # six eighths = one 6/8 bar
    "b1":    [(3, .5), (5, .5), (8, .5), (5, .5), (8, .5), (10, .5)],   # A C F C F A
    "b2":    [(5, .5), (8, .5), (10, .5), (8, .5), (10, .5), (12, .5)], # C F A F A C
    "bend":  [(3, .5), (5, .5), (8, .5), (10, 1.5)],                    # A C F  A (held)
    "brun":  [(d, .5) for d in range(3, 9)],                            # A up the scale to F
}
GAME_CHORDS = ([1, 4, 1, 5] + [1, 4, 5, 1] + [1, 1, 4, 5]
                  + [1, 4, 1, 5] + [1, 4, 5, 1] + [1, 4, 5, 5])
GAME_PLAN = (["b1", "b1", "b2", "b1"] + ["b1", None, "b1", "bend"] + [None] * 4
                + ["b2", "b2", "b1", "b1"] + ["b1", "b2", "b2", "bend"] + ["b1", "b1", "b2", "brun"])
GAME_ECHO = {15, 19, 20, 21}


def build_game() -> Loop:
    cfg = GAME
    _seed(2704)
    bpb = cfg["bpb"]
    loop = Loop(cfg["bpm"], cfg["bars"], bpb)
    assert len(GAME_CHORDS) == len(GAME_PLAN) == cfg["bars"]

    lay_pad(loop, GAME_CHORDS, bpb, cfg["pad"])
    # bass on the dotted beats: root on 1, fifth on 4 (eighth steps 0 and 3)
    lay_bass_low(loop, GAME_CHORDS, [(0, "root", 1.0, 0.45), (1.5, "fifth", 0.75, 0.4)], cfg, bpb)
    # stabs on the other eighths of each dotted beat (steps 2 and 5)
    for bar, r in enumerate(GAME_CHORDS):
        for beat, vel, pan in ((1.0, 0.55, -0.25), (2.5, 0.45, 0.25)):
            for k, deg in enumerate([r - 5, r - 3, r]):
                loop.add(santur(mhz(deg), 0.22, 0.20 * vel * cfg["stab"], 0.45), bar * bpb + beat + k * 0.015, pan)
    # breather: a bell ping on each downbeat
    for bar in range(8, 12):
        loop.add(bell(mhz(GAME_CHORDS[bar] + 4), 1.6, 0.20 * cfg["bell"]), bar * bpb, 0.2)
    lay_phrases(loop, GAME_PLAN, GAME_CHORDS, GAME_PHRASES, cfg, bpb, GAME_ECHO)
    # tonbak + zils:  dum . tak | dum . tak   with ghost taks, bandari-style
    lay_perc_beats(loop, cfg["bars"], bpb,
                   hits=[(0, "d", 0.9), (1, "t", 0.6), (1.5, "d", 0.75), (2, "t", 0.3), (2.5, "t", 0.6)],
                   jingles=[(0.5, 0.3), (1, 0.2), (2, 0.3), (2.5, 0.45)], cfg=cfg,
                   fill=[(2.75, "t", 0.5)])
    return loop


def game() -> np.ndarray:
    """120 bpm 6/8 x 24 bars = 36 s. Dotted-beat bass, offbeat stabs, a sparse hook."""
    return build_game().render(GAME["wet"], GAME["size"])


# name (= file name in client/assets/audio/music) -> renderer
TRACKS = {"menu": menu, "game": game}
