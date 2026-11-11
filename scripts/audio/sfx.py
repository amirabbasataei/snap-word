"""The sound-effect set. Each function returns a mono float signal; the build
script normalises it to the peak given in PEAKS and writes a 16-bit WAV."""
from __future__ import annotations

import numpy as np

from synth import (
    SR, bell, bandpass, exp_env, fade, glide, hz, n_samples, noise, osc, place,
    reverb, santur, silence, tonbak_dum, tonbak_tak,
)


def _buf(dur: float) -> np.ndarray:
    return silence(dur)


def _tick(freq: float, dur: float = 0.04, shape: str = "tri", decay: float = 0.012) -> np.ndarray:
    n = n_samples(dur)
    return fade(osc(freq, dur, shape) * exp_env(n, 0.0004, decay), 0.0, 0.004)


# ------------------------------------------------------------------ UI


def tap() -> np.ndarray:
    n = n_samples(0.07)
    body = osc(glide(760, 420, 0.07, 10), 0.07) * exp_env(n, 0.0005, 0.018)
    click = bandpass(noise(0.07), 2000, 6000) * exp_env(n, 0.0002, 0.004) * 0.25
    return fade(body + click, 0.0, 0.01)


def toggle() -> np.ndarray:
    b = _buf(0.16)
    place(b, _tick(520, 0.05), 0.0)
    place(b, _tick(780, 0.06), 0.07, 0.9)
    return b


def dialog_open() -> np.ndarray:
    b = _buf(0.5)
    place(b, santur(hz(5), 0.45, 0.5, 0.7), 0.0)
    place(b, santur(hz(8), 0.4, 0.45, 0.7), 0.07)
    return reverb(b, 0.18, 0.6)


def dialog_close() -> np.ndarray:
    b = _buf(0.4)
    place(b, santur(hz(8), 0.3, 0.4, 0.6), 0.0)
    place(b, santur(hz(5), 0.35, 0.4, 0.6), 0.06)
    return b


def toast() -> np.ndarray:
    return reverb(np.pad(bell(hz(12), 0.7, 0.8), (0, n_samples(0.2))), 0.2, 0.5)


def tab() -> np.ndarray:
    return _tick(560, 0.045, "tri", 0.014)


# ------------------------------------------------------------ keyboard


def key() -> np.ndarray:
    n = n_samples(0.05)
    body = osc(glide(980, 640, 0.05, 8), 0.05, "tri") * exp_env(n, 0.0003, 0.011)
    click = bandpass(noise(0.05), 2500, 7000) * exp_env(n, 0.0002, 0.003) * 0.18
    return fade(body + click, 0.0, 0.006)


def key_back() -> np.ndarray:
    n = n_samples(0.06)
    return fade(osc(glide(520, 330, 0.06, 8), 0.06, "tri") * exp_env(n, 0.0003, 0.014), 0.0, 0.006)


def key_send() -> np.ndarray:
    b = _buf(0.2)
    place(b, _tick(hz(5), 0.07, "tri", 0.03), 0.0)
    place(b, _tick(hz(8), 0.1, "tri", 0.045), 0.065)
    return b


# ------------------------------------------------------------ gameplay


def accepted() -> np.ndarray:
    b = _buf(0.8)
    place(b, santur(hz(4), 0.5, 0.9), 0.0)
    place(b, santur(hz(8), 0.7, 1.0), 0.09)
    place(b, bell(hz(15), 0.6, 0.18), 0.09)
    return reverb(b, 0.2, 0.6)


def streak() -> np.ndarray:
    b = _buf(1.1)
    for i, d in enumerate([8, 10, 12, 15]):
        place(b, santur(hz(d), 0.6, 0.85), 0.075 * i)
        place(b, bell(hz(d + 7), 0.7, 0.2), 0.075 * i)
    return reverb(b, 0.22, 0.7)


def rejected() -> np.ndarray:
    dur = 0.28
    n = n_samples(dur)
    f = glide(210, 120, dur, 4) * (1 + 0.012 * np.sin(2 * np.pi * 28 * np.arange(n) / SR))
    buzz = osc(f, dur, "square") * 0.35 + osc(f * 0.5, dur, "sine") * 0.6
    return fade(buzz * exp_env(n, 0.003, 0.11), 0.002, 0.02)


def tile_land() -> np.ndarray:
    b = _buf(0.32)
    n = n_samples(0.3)
    t = np.arange(n) / SR
    clink = sum(a * np.sin(2 * np.pi * f * t) * np.exp(-t / tau)
                for f, a, tau in ((2350, 1.0, 0.05), (3720, 0.6, 0.035), (5610, 0.35, 0.025)))
    place(b, clink * 0.4, 0.0)
    place(b, osc(glide(220, 140, 0.05, 8), 0.05) * exp_env(n_samples(0.05), 0.0005, 0.02), 0.0, 0.5)
    return fade(b, 0.0, 0.02)


def opp_word() -> np.ndarray:
    b = _buf(0.6)
    place(b, santur(hz(5), 0.5, 0.55, 0.55), 0.0)
    place(b, _tick(hz(12), 0.03, "sine", 0.01), 0.0, 0.3)
    return reverb(b, 0.18, 0.6)


def tick() -> np.ndarray:
    n = n_samples(0.035)
    t = np.arange(n) / SR
    return fade(np.sin(2 * np.pi * 1320 * t) * exp_env(n, 0.0003, 0.009), 0.0, 0.005)


def timeout() -> np.ndarray:
    b = _buf(1.3)
    for i, (d, g) in enumerate([(5, 0.8), (3, 0.85), (1, 0.95)]):
        place(b, santur(hz(d), 0.8, 0.95), 0.24 * i, g)
    place(b, tonbak_dum(1.0), 0.72)
    return reverb(b, 0.22, 0.8)


def life_lost() -> np.ndarray:
    dur = 0.55
    n = n_samples(dur)
    t = np.arange(n) / SR
    f = glide(520, 170, dur, 3.2)
    s = osc(f * (1 + 0.02 * np.sin(2 * np.pi * 7 * t)), dur, "sine") * exp_env(n, 0.003, 0.22)
    b = _buf(dur)
    place(b, s, 0.0, 0.8)
    place(b, tonbak_dum(0.9), 0.0, 0.6)
    return fade(b, 0.001, 0.04)


def shield() -> np.ndarray:
    dur = 0.8
    n = n_samples(dur)
    t = np.arange(n) / SR
    sweep = osc(np.linspace(380, 1500, n), dur, "tri")
    shimmer = sweep * (0.6 + 0.4 * np.sin(2 * np.pi * 18 * t)) * np.minimum(1, t / 0.08) * np.exp(-t / 0.5)
    b = shimmer * 0.5
    place(b, bell(hz(12), 0.7, 0.8), 0.2)
    place(b, bell(hz(15), 0.6, 0.6), 0.32)
    return reverb(fade(b, 0.003, 0.05), 0.25, 0.7)


def hint() -> np.ndarray:
    b = _buf(0.75)
    place(b, bell(hz(12), 0.6, 0.9), 0.0)
    place(b, bell(hz(15), 0.7, 0.9), 0.11)
    place(b, santur(hz(8), 0.5, 0.35), 0.0)
    return reverb(b, 0.2, 0.6)


def extra_time() -> np.ndarray:
    b = _buf(0.8)
    for i in range(3):
        place(b, _tick(900 + 160 * i, 0.04, "sine", 0.01), 0.07 * i)
    place(b, bell(hz(12), 0.6, 0.9), 0.24)
    return reverb(b, 0.18, 0.5)


def long_word() -> np.ndarray:
    b = _buf(1.1)
    for i, d in enumerate([5, 6, 7, 8, 9, 10, 12]):
        place(b, santur(hz(d), 0.45, 0.7 + 0.04 * i), 0.045 * i)
    place(b, bell(hz(15), 0.9, 0.7), 0.32)
    place(b, bell(hz(19), 0.9, 0.4), 0.34)
    return reverb(b, 0.25, 0.8)


def match_found() -> np.ndarray:
    b = _buf(1.4)
    place(b, tonbak_dum(1.0), 0.0)
    place(b, tonbak_tak(0.9), 0.16)
    for i, d in enumerate([1, 5, 8]):
        place(b, santur(hz(d), 0.9, 0.95), 0.2 + 0.13 * i)
    place(b, bell(hz(12), 0.9, 0.55), 0.6)
    place(b, tonbak_dum(0.9), 0.6)
    return reverb(b, 0.22, 0.8)


def taunt() -> np.ndarray:
    dur = 0.34
    n = n_samples(dur)
    t = np.arange(n) / SR
    f = 330 + 260 * np.sin(np.pi * np.minimum(1, t / dur))
    f = f * (1 + 0.03 * np.sin(2 * np.pi * 14 * t))
    return fade(osc(f, dur, "tri") * np.minimum(1, t / 0.01) * np.exp(-t / 0.25), 0.002, 0.03)


# -------------------------------------------------------------- results


def win() -> np.ndarray:
    b = _buf(2.4)
    motif = [(1, 0.0), (3, 0.17), (5, 0.34), (8, 0.51), (10, 0.80), (12, 1.05)]
    for d, at in motif:
        place(b, santur(hz(d), 1.1, 0.95), at)
    place(b, bell(hz(15), 1.4, 0.6), 1.05)
    place(b, bell(hz(12), 1.4, 0.4), 1.07)
    for at, kind in ((0.0, "d"), (0.34, "t"), (0.51, "d"), (1.05, "d"), (1.22, "t")):
        place(b, tonbak_dum(0.85) if kind == "d" else tonbak_tak(0.8), at)
    place(b, santur(hz(-6), 1.8, 0.8), 1.05)
    return reverb(b, 0.28, 1.0)


def lose() -> np.ndarray:
    b = _buf(2.2)
    for i, d in enumerate([5, 4, 3, 2, 1]):
        place(b, santur(hz(d), 1.1 if d != 1 else 1.6, 0.8, 0.8), 0.28 * i, 1.0 - 0.04 * i)
    place(b, santur(hz(-6), 1.7, 0.7), 1.1)
    return reverb(b, 0.3, 1.0)


def rating_up() -> np.ndarray:
    b = _buf(0.9)
    for i, d in enumerate([8, 10, 12]):
        place(b, bell(hz(d), 0.7, 0.85), 0.1 * i)
        place(b, santur(hz(d), 0.5, 0.5), 0.1 * i)
    return reverb(b, 0.2, 0.6)


def rating_down() -> np.ndarray:
    b = _buf(0.8)
    place(b, santur(hz(5), 0.5, 0.7, 0.7), 0.0)
    place(b, santur(hz(3), 0.6, 0.7, 0.7), 0.16)
    return reverb(b, 0.2, 0.6)


# -------------------------------------------------------------- economy


def coin() -> np.ndarray:
    b = _buf(0.6)
    place(b, bell(hz(12), 0.5, 0.9), 0.0)
    place(b, bell(hz(15), 0.55, 1.0), 0.07)
    place(b, _tick(3100, 0.02, "sine", 0.006), 0.0, 0.3)
    return b


def coin_spend() -> np.ndarray:
    b = _buf(0.5)
    place(b, bell(hz(15), 0.35, 0.8), 0.0)
    place(b, bell(hz(12), 0.4, 0.8), 0.07)
    place(b, bell(hz(8), 0.35, 0.5), 0.14)
    return b


def claim() -> np.ndarray:
    b = _buf(1.2)
    rng = np.random.default_rng(5)
    for i in range(7):
        d = 10 + (i % 4) * 2
        place(b, bell(hz(d), 0.4, 0.55), 0.05 * i + float(rng.uniform(0, 0.015)))
    place(b, santur(hz(8), 0.8, 0.6), 0.0)
    place(b, bell(hz(15), 0.9, 0.8), 0.4)
    return reverb(b, 0.22, 0.7)


def level_up() -> np.ndarray:
    b = _buf(2.2)
    for i, d in enumerate([1, 3, 5, 8, 10, 12, 15]):
        place(b, santur(hz(d), 1.0, 0.85), 0.09 * i)
    for i in range(6):
        place(b, tonbak_tak(0.5 + 0.08 * i), 0.09 * i + 0.045)
    place(b, bell(hz(15), 1.3, 0.8), 0.7)
    place(b, bell(hz(12), 1.3, 0.5), 0.72)
    place(b, tonbak_dum(0.9), 0.7)
    place(b, santur(hz(-6), 1.5, 0.7), 0.7)
    return reverb(b, 0.28, 1.0)


# name -> (builder, target peak)
SFX = {
    "tap": (tap, 0.50),
    "toggle": (toggle, 0.45),
    "dialog_open": (dialog_open, 0.50),
    "dialog_close": (dialog_close, 0.45),
    "toast": (toast, 0.50),
    "tab": (tab, 0.40),
    "key": (key, 0.45),
    "key_back": (key_back, 0.45),
    "key_send": (key_send, 0.55),
    "accepted": (accepted, 0.70),
    "streak": (streak, 0.75),
    "rejected": (rejected, 0.60),
    "tile_land": (tile_land, 0.45),
    "opp_word": (opp_word, 0.50),
    "tick": (tick, 0.40),
    "timeout": (timeout, 0.70),
    "life_lost": (life_lost, 0.70),
    "shield": (shield, 0.60),
    "hint": (hint, 0.60),
    "extra_time": (extra_time, 0.60),
    "long_word": (long_word, 0.75),
    "match_found": (match_found, 0.75),
    "taunt": (taunt, 0.55),
    "win": (win, 0.80),
    "lose": (lose, 0.70),
    "rating_up": (rating_up, 0.65),
    "rating_down": (rating_down, 0.55),
    "coin": (coin, 0.65),
    "coin_spend": (coin_spend, 0.55),
    "claim": (claim, 0.70),
    "level_up": (level_up, 0.80),
}
