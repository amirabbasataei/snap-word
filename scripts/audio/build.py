#!/usr/bin/env python3
"""Generate every sound of the app into client/assets/audio.

    python3 scripts/audio/build.py            # all
    python3 scripts/audio/build.py tap win    # only these SFX
    python3 scripts/audio/build.py --music    # only the two music loops

SFX are 16-bit mono WAV (no decode latency), music is stereo Ogg Vorbis.
Needs numpy and ffmpeg (with libvorbis). The output is original synthesis: no
samples, no third-party licence.
"""
from __future__ import annotations

import os
import subprocess
import sys
import tempfile

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import music  # noqa: E402
import sfx  # noqa: E402
from synth import SR, fade, save_wav  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "client", "assets", "audio"))


def build_sfx(names):
    os.makedirs(f"{ROOT}/sfx", exist_ok=True)
    for name, (fn, peak) in sfx.SFX.items():
        if names and name not in names:
            continue
        sig = fn()
        sig = fade(sig, 0.001, 0.02)
        m = float(np.max(np.abs(sig)))
        sig = sig * (peak / m)
        # trim trailing near-silence
        keep = np.nonzero(np.abs(sig) > 0.002)[0]
        sig = sig[: keep[-1] + int(0.02 * SR)] if len(keep) else sig
        path = f"{ROOT}/sfx/{name}.wav"
        save_wav(path, sig)
        print(f"sfx/{name}.wav  {len(sig) / SR:5.2f}s  {os.path.getsize(path) // 1024:4d} KB")


def build_music():
    os.makedirs(f"{ROOT}/music", exist_ok=True)
    for name, fn in (("menu", music.menu), ("game", music.game)):
        sig = fn()
        with tempfile.TemporaryDirectory() as d:
            wav = f"{d}/{name}.wav"
            save_wav(wav, sig)
            out = f"{ROOT}/music/{name}.ogg"
            subprocess.run(
                ["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "3", out],
                check=True,
            )
        seam = float(np.abs(sig[0] - sig[-1]).max())
        print(f"music/{name}.ogg  {len(sig) / SR:5.1f}s  {os.path.getsize(out) // 1024:4d} KB  seam={seam:.4f}")


if __name__ == "__main__":
    args = sys.argv[1:]
    only_music = "--music" in args
    names = {a for a in args if not a.startswith("--")}
    if not only_music:
        build_sfx(names)
    if only_music or not names:
        build_music()
