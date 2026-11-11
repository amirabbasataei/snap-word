"""Two seamless music loops in Shur (D): a calm menu loop and a pulsing in-game
loop. Both are rendered with a reverb tail that is folded back onto the start,
so the loop point is inaudible."""
from __future__ import annotations

import numpy as np

from synth import (
    SR, hz, n_samples, pad, place, reverb, santur, silence, tonbak_dum,
    tonbak_tak, bell,
)

TAIL = 4.0  # seconds of reverb tail folded onto the start


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

    def render(self, rms: float = 0.13) -> np.ndarray:
        wet_l = reverb(self.dry_l + self.pad, 0.35, 1.2, 0)
        wet_r = reverb(self.dry_r + self.pad, 0.35, 1.2, 1)
        l = wet_l + self.perc * 0.9
        r = wet_r + self.perc * 0.9
        out = np.stack([l, r], axis=1)
        n = n_samples(self.length)
        tail = out[n:]
        out = out[:n].copy()
        out[: len(tail)] += tail  # fold the tail: seamless loop
        out *= rms / max(1e-9, float(np.sqrt(np.mean(out ** 2))))
        return np.tanh(out * 1.1) / 1.1


def melody(loop: Loop, notes, start_beat=0.0, pan=0.0, vel=0.9, octave=0, bright=0.8):
    t = start_beat
    for deg, beats in notes:
        if deg is not None:
            loop.add(santur(hz(deg + 7 * octave), min(2.4, beats * loop.spb * 1.8 + 0.5), vel, bright), t, pan)
        t += beats
    return t


def arp(loop: Loop, bar_roots, start_bar=0, vel=0.32, pan_swing=0.3, pattern=(0, 4, 7, 4, 0, 4, 7, 4)):
    for b, root in enumerate(bar_roots):
        for i, off in enumerate(pattern):
            beat = (start_bar + b) * 4 + i * 0.5
            loop.add(santur(hz(root + off), 0.9, vel, 0.55), beat, pan_swing * (1 if i % 2 else -1))


def drone(loop: Loop, bar_roots, vel=0.5):
    # Two-bar swells so the harmony breathes.
    i = 0
    while i < len(bar_roots):
        root = bar_roots[i]
        span = 2 if i + 1 < len(bar_roots) else 1
        dur = span * 4 * loop.spb
        loop.add(pad(hz(root - 7), dur + 0.6, vel, 0.8), i * 4, bus="pad")
        loop.add(pad(hz(root - 3), dur + 0.6, vel * 0.55, 0.9), i * 4, bus="pad")
        i += span


def check(notes, bars):
    total = sum(b for _, b in notes)
    assert abs(total - bars * 4) < 1e-6, (total, bars * 4)


def menu() -> np.ndarray:
    """76 bpm, 8 bars (~25 s): a slow descending santur melody over an arpeggio."""
    loop = Loop(76, 8)
    m = [
        (5, 1.5), (6, 0.5), (5, 1), (4, 1),
        (3, 1), (4, 1), (2, 2),
        (1, 1), (2, 1), (3, 1.5), (2, 0.5),
        (1, 3), (None, 1),
        (5, 1), (8, 1), (7, 1), (6, 1),
        (5, 1.5), (4, 0.5), (3, 1), (4, 1),
        (3, 1), (2, 1), (3, 1), (2, 1),
        (1, 3), (None, 1),
    ]
    check(m, 8)
    roots = [-6, -6, -3, -6, -1, -3, -6, -6]
    drone(loop, roots, 0.45)
    arp(loop, roots, 0, 0.30)
    melody(loop, m, 0.0, 0.0, 0.95, 0, 0.8)
    # a soft echo of the first phrase an octave up, bell-like
    loop.add(bell(hz(12), 2.0, 0.22), 0.0, 0.25)
    loop.add(bell(hz(8), 2.4, 0.2), 16.0, -0.25)
    return loop.render(0.115)


def game() -> np.ndarray:
    """108 bpm, 16 bars (~36 s): tonbak groove, santur ostinato, two sparse melodies."""
    loop = Loop(108, 16)
    roots = [-6, -6, -6, -6, -3, -3, -6, -6, -1, -1, -3, -3, -6, -6, -6, -6]
    drone(loop, roots, 0.35)
    arp(loop, roots, 0, 0.22, 0.35, (0, 4, 7, 4, 0, 4, 7, 9))

    # tonbak: dum . tak . | dum dum tak .   (8th-note grid), with a fill every 4th bar
    for bar in range(16):
        base = bar * 4
        for step, kind, v in [
            (0, "d", 0.9), (2, "t", 0.7), (3, "t", 0.3),
            (4, "d", 0.8), (5, "d", 0.45), (6, "t", 0.7),
        ]:
            sig = tonbak_dum(v) if kind == "d" else tonbak_tak(v)
            loop.add(sig, base + step * 0.5, bus="perc", gain=0.33)
        if bar % 4 == 3:
            for k, st in enumerate([7, 7.5, 7.75]):
                loop.add(tonbak_tak(0.5 + 0.15 * k), base + st * 0.5 + 0.0, bus="perc", gain=0.28)

    a = [
        (8, 1), (7, 0.5), (8, 0.5), (5, 2),
        (6, 1), (5, 0.5), (4, 0.5), (3, 2),
        (4, 1), (5, 1), (4, 1), (3, 1),
        (2, 2), (1, 2),
    ]
    check(a, 4)
    melody(loop, a, 16.0, -0.15, 0.8, 0, 0.7)
    b = [
        (5, 1), (8, 1), (10, 1), (8, 1),
        (7, 1), (6, 1), (5, 2),
        (6, 1), (7, 1), (8, 1), (7, 1),
        (5, 2), (4, 1), (3, 1),
    ]
    check(b, 4)
    melody(loop, b, 48.0, 0.15, 0.8, 0, 0.7)
    return loop.render(0.105)
