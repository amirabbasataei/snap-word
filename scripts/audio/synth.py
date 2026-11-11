"""Tiny numpy synthesis kit for the Zanjir sound set.

Everything is generated from maths, so the output is original and carries no
licence. The palette is a plucked, santur-like string (additive partials with a
detuned string pair) plus bells and tonbak-style drum hits, all in the Persian
mode Shur on D (D, E-koron, F, G, A, Bb, C).
"""
from __future__ import annotations

import wave

import numpy as np

SR = 44100
TONIC = 293.665  # D4
# Dastgah-e Shur on D, cents above the tonic. E is koron (a quarter-tone flat).
SCALE_CENTS = [0, 150, 300, 500, 700, 800, 1000]
_rng = np.random.default_rng(1403)


def hz(deg: int, shift_cents: float = 0.0) -> float:
    """1-based scale degree (any octave: 8 = D5, 0 = C4, -6 = D3) -> Hz."""
    octave, idx = divmod(deg - 1, 7)
    return TONIC * 2 ** ((SCALE_CENTS[idx] + 1200 * octave + shift_cents) / 1200)


def n_samples(dur: float) -> int:
    return int(round(dur * SR))


def tt(dur: float) -> np.ndarray:
    return np.arange(n_samples(dur)) / SR


def silence(dur: float) -> np.ndarray:
    return np.zeros(n_samples(dur))


def place(buf: np.ndarray, sig: np.ndarray, at: float, gain: float = 1.0) -> None:
    i = n_samples(at)
    if i >= len(buf):
        return
    j = min(len(buf), i + len(sig))
    buf[i:j] += sig[: j - i] * gain


def exp_env(n: int, attack: float, decay: float) -> np.ndarray:
    """Linear attack then exponential decay (decay = time constant in s)."""
    t = np.arange(n) / SR
    env = np.exp(-t / max(decay, 1e-4))
    a = max(1, int(attack * SR))
    env[:a] *= np.linspace(0, 1, a)
    return env


def osc(freq: np.ndarray | float, dur: float, shape: str = "sine") -> np.ndarray:
    n = n_samples(dur)
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
    phase = np.cumsum(f) / SR
    if shape == "sine":
        return np.sin(2 * np.pi * phase)
    if shape == "tri":
        return 2 * np.abs(2 * (phase % 1) - 1) - 1
    if shape == "square":
        return np.sign(np.sin(2 * np.pi * phase))
    raise ValueError(shape)


def glide(f0: float, f1: float, dur: float, curve: float = 3.0) -> np.ndarray:
    """Exponential-ish frequency sweep array."""
    x = np.linspace(0, 1, n_samples(dur))
    return f1 + (f0 - f1) * np.exp(-curve * x)


def noise(dur: float) -> np.ndarray:
    return _rng.standard_normal(n_samples(dur))


def bandpass(sig: np.ndarray, lo: float, hi: float) -> np.ndarray:
    spec = np.fft.rfft(sig)
    f = np.fft.rfftfreq(len(sig), 1 / SR)
    mask = ((f >= lo) & (f <= hi)).astype(float)
    # soften the edges so it doesn't ring
    k = max(3, int(len(mask) / 400))
    mask = np.convolve(mask, np.ones(k) / k, mode="same")
    return np.fft.irfft(spec * mask, n=len(sig))


def fade(sig: np.ndarray, fin: float = 0.002, fout: float = 0.01) -> np.ndarray:
    sig = sig.copy()
    a, b = n_samples(fin), n_samples(fout)
    if a:
        sig[:a] *= np.linspace(0, 1, a)
    if b:
        sig[-b:] *= np.linspace(1, 0, b)
    return sig


# ---------------------------------------------------------------- instruments


def santur(freq: float, dur: float = 1.2, vel: float = 1.0, bright: float = 1.0) -> np.ndarray:
    """Hammered/plucked string: inharmonic partials, a detuned string pair and a
    short felt-hammer transient."""
    n = n_samples(dur)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for detune, w in ((0.0, 1.0), (3.2, 0.7), (-2.6, 0.6)):
        f0 = freq * 2 ** (detune / 1200)
        for k in range(1, 9):
            fk = f0 * k * (1 + 0.0006 * k * k)
            if fk > 9000:
                break
            amp = (1.0 / k ** 1.15) * (bright ** (k - 1))
            tau = 0.55 / (1 + 0.55 * (k - 1)) * (0.6 + 0.4 * min(1.0, 600 / freq))
            out += w * amp * np.sin(2 * np.pi * fk * t) * np.exp(-t / (tau * dur / 1.2 + 0.05))
    hammer = bandpass(_rng.standard_normal(n_samples(0.02)), 1500, 6000)
    hammer = hammer * np.exp(-np.arange(len(hammer)) / SR / 0.004) * 0.25
    out[: len(hammer)] += hammer * (freq ** 0.3) / 6
    out *= np.minimum(1, t / 0.002 + 0.0)
    return fade(out / 3.0 * vel, 0.0, 0.03)


def bell(freq: float, dur: float = 1.0, vel: float = 1.0) -> np.ndarray:
    """Glassy bell: inharmonic partials, fast attack, long shimmer."""
    n = n_samples(dur)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for ratio, amp, tau in ((1, 1.0, 0.45), (2.76, 0.55, 0.28), (5.40, 0.30, 0.17), (8.93, 0.16, 0.10)):
        out += amp * np.sin(2 * np.pi * freq * ratio * t) * np.exp(-t / (tau * dur + 0.03))
    return fade(out * vel * 0.45, 0.0005, 0.03)


def tonbak_dum(vel: float = 1.0, dur: float = 0.32) -> np.ndarray:
    f = glide(165, 78, dur, curve=9)
    body = osc(f, dur) * exp_env(n_samples(dur), 0.001, 0.09)
    click = bandpass(noise(0.01), 800, 3000) * np.exp(-np.arange(n_samples(0.01)) / SR / 0.002)
    body[: len(click)] += click * 0.25
    return fade(body * vel * 0.9, 0.0, 0.02)


def tonbak_tak(vel: float = 1.0, dur: float = 0.12) -> np.ndarray:
    n = n_samples(dur)
    nz = bandpass(noise(dur), 2200, 7000) * exp_env(n, 0.0005, 0.022)
    ring = osc(glide(520, 400, dur, 12), dur) * exp_env(n, 0.0005, 0.03) * 0.35
    return fade((nz * 0.9 + ring) * vel * 0.6, 0.0, 0.01)


def pad(freq: float, dur: float, vel: float = 1.0, swell: float = 0.6) -> np.ndarray:
    """Soft organ-like drone with a slow swell and slight detuned beating."""
    n = n_samples(dur)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for detune in (-5, 0, 6):
        f = freq * 2 ** (detune / 1200)
        for k, a in ((1, 1.0), (2, 0.35), (3, 0.18), (4, 0.07)):
            out += a * np.sin(2 * np.pi * f * k * t + detune)
    env = np.minimum(1, t / swell) * np.minimum(1, (dur - t) / swell)
    return out * env * vel / 6


# -------------------------------------------------------------------- reverb


def _comb(x: np.ndarray, d: int, g: float) -> np.ndarray:
    y = x.copy()
    for s in range(d, len(x), d):
        e = min(s + d, len(x))
        y[s:e] += g * y[s - d : e - d]
    return y


def _allpass(x: np.ndarray, d: int, g: float) -> np.ndarray:
    y = -g * x
    for s in range(d, len(x), d):
        e = min(s + d, len(x))
        y[s:e] = -g * x[s:e] + x[s - d : e - d] + g * y[s - d : e - d]
    return y


def reverb(x: np.ndarray, wet: float = 0.25, size: float = 1.0, side: int = 0) -> np.ndarray:
    """Schroeder reverb. `side` shifts the delay set so two channels decorrelate."""
    base = [1557, 1617, 1491, 1422, 1277, 1356]
    gains = [0.80, 0.78, 0.82, 0.79, 0.77, 0.76]
    acc = np.zeros(len(x))
    for d, g in zip(base, gains):
        acc += _comb(x, int(d * size) + side * 37, g)
    acc /= len(base)
    for d, g in ((225, 0.5), (556, 0.5), (441, 0.5)):
        acc = _allpass(acc, d + side * 11, g)
    return x * (1 - wet) + acc * wet * 2.2


# ------------------------------------------------------------------------ io


def to_pcm(sig: np.ndarray) -> np.ndarray:
    return (np.clip(sig, -1, 1) * 32767).astype("<i2")


def save_wav(path: str, sig: np.ndarray) -> None:
    pcm = to_pcm(sig)
    ch = 1 if sig.ndim == 1 else sig.shape[1]
    with wave.open(path, "wb") as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def normalise(sig: np.ndarray, peak: float = 0.7) -> np.ndarray:
    m = np.max(np.abs(sig))
    return sig * (peak / m) if m > 0 else sig
