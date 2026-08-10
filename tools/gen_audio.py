#!/usr/bin/env python3
"""Generate the game's sound effects and music as 16-bit mono WAVs.

Run from the project root:  python3 tools/gen_audio.py

Everything is synthesised from scratch (square/triangle/noise voices through
simple envelopes), so the audio is original and the repo carries no third-party
sound licences.
"""

import os
import struct
import sys
import wave

import numpy as np

RATE = 22050
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "audio")

NOTES = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6,
         "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}


def freq(name):
    """'A4' -> 440.0"""
    if name in ("-", ""):
        return 0.0
    octave = int(name[-1])
    semitone = NOTES[name[:-1]]
    return 440.0 * 2.0 ** ((semitone - 9) / 12.0 + (octave - 4))


def t(duration):
    return np.arange(int(RATE * duration)) / RATE


# --------------------------------------------------------------------------- #
# voices
# --------------------------------------------------------------------------- #
def square(f, duration, duty=0.5, sweep=0.0):
    time = t(duration)
    phase = np.cumsum((f + sweep * time) / RATE)
    return np.where((phase % 1.0) < duty, 1.0, -1.0)


def triangle(f, duration, sweep=0.0):
    time = t(duration)
    phase = np.cumsum((f + sweep * time) / RATE) % 1.0
    return 4.0 * np.abs(phase - 0.5) - 1.0


def sine(f, duration, sweep=0.0):
    time = t(duration)
    phase = np.cumsum((f + sweep * time) / RATE)
    return np.sin(phase * 2.0 * np.pi)


def noise(duration, rng=None):
    rng = rng or np.random.default_rng(7)
    return rng.uniform(-1.0, 1.0, int(RATE * duration))


def env(signal, attack=0.005, decay=0.0, sustain=1.0, release=0.05):
    n = len(signal)
    a = max(1, int(attack * RATE))
    d = int(decay * RATE)
    r = max(1, int(release * RATE))
    s = max(0, n - a - d - r)
    curve = np.concatenate([
        np.linspace(0.0, 1.0, a),
        np.linspace(1.0, sustain, d) if d else np.empty(0),
        np.full(s, sustain),
        np.linspace(sustain, 0.0, r),
    ])
    curve = np.resize(curve, n)
    return signal * curve


def mixdown(*parts):
    length = max(len(p) for p in parts)
    out = np.zeros(length)
    for p in parts:
        out[: len(p)] += p
    peak = np.max(np.abs(out))
    return out / peak * 0.92 if peak > 0 else out


def at(target, signal, start):
    """Add `signal` into `target` at a sample offset, growing as needed."""
    end = start + len(signal)
    if end > len(target):
        target = np.concatenate([target, np.zeros(end - len(target))])
    target[start:end] += signal
    return target


def write_wav(name, samples, volume=0.85):
    samples = np.clip(samples * volume, -1.0, 1.0)
    data = (samples * 32767).astype("<i2").tobytes()
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(data)
    print(f"  wrote {os.path.relpath(path, ROOT)} ({len(samples) / RATE:.2f}s)")


# --------------------------------------------------------------------------- #
# sound effects
# --------------------------------------------------------------------------- #
def sfx_jump():
    return env(square(330, 0.16, 0.35, sweep=1500), attack=0.002, release=0.09) * 0.55


def sfx_ring():
    a = env(sine(freq("E6"), 0.09), attack=0.001, release=0.05)
    b = env(sine(freq("B6"), 0.22), attack=0.001, release=0.18)
    out = np.zeros(int(RATE * 0.3))
    out = at(out, a, 0)
    out = at(out, b, int(RATE * 0.06))
    return out * 0.4


def sfx_spindash_charge():
    return env(square(180, 0.30, 0.25, sweep=2600), attack=0.004, release=0.06) * 0.45


def sfx_spindash_release():
    body = env(noise(0.34) * 0.5 + square(120, 0.34, 0.5, sweep=900) * 0.5,
               attack=0.004, decay=0.10, sustain=0.5, release=0.2)
    return body * 0.5


def sfx_spring():
    return env(triangle(400, 0.26, sweep=2400), attack=0.002, release=0.12) * 0.5


def sfx_hurt():
    return env(square(600, 0.35, 0.5, sweep=-1400), attack=0.002, release=0.2) * 0.5


def sfx_break():
    crunch = env(noise(0.26), attack=0.001, decay=0.06, sustain=0.4, release=0.18)
    thud = env(sine(140, 0.26, sweep=-260), attack=0.002, release=0.16)
    return (crunch * 0.55 + thud * 0.6) * 0.55


def sfx_pop():
    return mixdown(
        env(noise(0.18), attack=0.001, release=0.14) * 0.7,
        env(square(700, 0.16, 0.5, sweep=-2200), attack=0.001, release=0.12) * 0.5,
    ) * 0.45


def sfx_checkpoint():
    out = np.zeros(int(RATE * 0.55))
    for i, note in enumerate(["C5", "E5", "G5", "C6"]):
        out = at(out, env(square(freq(note), 0.16, 0.5), attack=0.003, release=0.11) * 0.32,
                 int(RATE * 0.09 * i))
    return out


def sfx_extra_life():
    out = np.zeros(int(RATE * 1.0))
    melody = ["G5", "C6", "E6", "G6", "E6", "G6"]
    for i, note in enumerate(melody):
        out = at(out, env(square(freq(note), 0.2, 0.5), attack=0.004, release=0.14) * 0.3,
                 int(RATE * 0.11 * i))
    return out


def sfx_death():
    out = np.zeros(int(RATE * 1.1))
    for i, note in enumerate(["A4", "G4", "F4", "E4", "D4"]):
        out = at(out, env(triangle(freq(note), 0.3), attack=0.005, release=0.2) * 0.34,
                 int(RATE * 0.16 * i))
    return out


def sfx_skid():
    return env(noise(0.20) * 0.35, attack=0.01, decay=0.05, sustain=0.6, release=0.12) * 0.3


def sfx_goal():
    """Short act-clear fanfare."""
    out = np.zeros(int(RATE * 2.4))
    lead = [("C5", 0.0), ("E5", 0.18), ("G5", 0.36), ("C6", 0.54),
            ("B5", 0.86), ("C6", 1.04), ("E6", 1.28), ("C6", 1.6)]
    for note, when in lead:
        out = at(out, env(square(freq(note), 0.32, 0.4), attack=0.004, release=0.22) * 0.3,
                 int(RATE * when))
    for note, when in [("C3", 0.0), ("G3", 0.54), ("C3", 1.04), ("G3", 1.6)]:
        out = at(out, env(triangle(freq(note), 0.5), attack=0.006, release=0.3) * 0.34,
                 int(RATE * when))
    return out


# --------------------------------------------------------------------------- #
# music: original 16-bar loop, ~152 BPM
# --------------------------------------------------------------------------- #
def music_zone():
    bpm = 152.0
    beat = 60.0 / bpm
    step = beat / 4.0  # sixteenth notes

    # bar-length chord roots (I - vi - IV - V in C, twice with a lift)
    bass_pattern = [
        "C2 - C3 - G2 - C3 - A1 - A2 - E2 - A2 -",
        "F2 - F3 - C3 - F3 - G2 - G3 - D3 - G3 -",
        "C2 - C3 - G2 - C3 - A1 - A2 - E2 - A2 -",
        "F2 - F3 - G2 - G3 - C3 - C3 - G2 - G2 -",
        # B section: same groove, brighter changes
        "A1 - A2 - E2 - A2 - F2 - F3 - C3 - F3 -",
        "G2 - G3 - D3 - G3 - C2 - C3 - G2 - C3 -",
        "A1 - A2 - E2 - A2 - D2 - D3 - A2 - D3 -",
        "G2 - G3 - G2 - G3 - C3 - G2 - C3 - G2 -",
    ]
    lead_pattern = [
        "G4 - A4 - C5 - - B4 A4 - G4 - E4 - G4 - -",
        "A4 - C5 - E5 - - D5 C5 - A4 - G4 - - - -",
        "G4 - A4 - C5 - - E5 D5 - C5 - A4 - G4 - -",
        "F4 - G4 - A4 - B4 - C5 - - - - - - -",
        "E5 - - D5 C5 - A4 - C5 - - B4 A4 - G4 -",
        "D5 - - C5 B4 - G4 - E5 - - D5 C5 - - -",
        "E5 - F5 - G5 - - F5 E5 - D5 - C5 - A4 -",
        "B4 - D5 - G5 - - - E5 - C5 - G4 - - -",
    ]
    harmony_pattern = [
        "E4 - - - E4 - - - C4 - - - C4 - - -",
        "A3 - - - A3 - - - B3 - - - B3 - - -",
        "E4 - - - E4 - - - C4 - - - C4 - - -",
        "A3 - - - B3 - - - E4 - - - D4 - - -",
        "C4 - - - C4 - - - A3 - - - A3 - - -",
        "B3 - - - B3 - - - E4 - - - E4 - - -",
        "C4 - - - C4 - - - F#3 - - - F#3 - - -",
        "D4 - - - B3 - - - G3 - - - B3 - - -",
    ]

    total = int(RATE * step * 16 * len(bass_pattern)) + int(RATE * 0.4)
    track = np.zeros(total)
    rng = np.random.default_rng(11)

    def lay(pattern, voice, gain, duty=0.5, length=1.0):
        for bar, line in enumerate(pattern):
            tokens = line.split()
            for i, token in enumerate(tokens[:16]):
                if token == "-":
                    continue
                start = int(RATE * step * (bar * 16 + i))
                dur = step * length
                f = freq(token)
                if voice == "square":
                    wave_data = env(square(f, dur, duty), attack=0.004,
                                    decay=dur * 0.2, sustain=0.75, release=dur * 0.35)
                else:
                    wave_data = env(triangle(f, dur), attack=0.006,
                                    decay=dur * 0.2, sustain=0.7, release=dur * 0.4)
                nonlocal track
                track = at(track, wave_data * gain, start)

    lay(bass_pattern, "triangle", 0.34, length=1.6)
    lay(lead_pattern, "square", 0.26, duty=0.4, length=1.7)
    lay(harmony_pattern, "square", 0.13, duty=0.25, length=3.4)

    # drums: kick on beats, hat on eighths, snare on 2 and 4
    bars = len(bass_pattern)
    for bar in range(bars):
        for b in range(4):
            base = int(RATE * step * (bar * 16 + b * 4))
            kick = env(sine(96, 0.13, sweep=-340), attack=0.002, release=0.1) * 0.5
            track = at(track, kick, base)
            if b in (1, 3):
                snare = env(noise(0.11, rng), attack=0.001, release=0.09) * 0.22
                track = at(track, snare, base)
            for eighth in range(2):
                hat = env(noise(0.035, rng), attack=0.001, release=0.03) * 0.075
                track = at(track, hat, base + int(RATE * step * (eighth * 2 + 1)))

    peak = np.max(np.abs(track))
    return track / peak * 0.8 if peak else track


# --------------------------------------------------------------------------- #
# boss music: shorter, faster, minor key
# --------------------------------------------------------------------------- #
def music_boss():
    bpm = 176.0
    beat = 60.0 / bpm
    step = beat / 4.0

    bass_pattern = [
        "A1 - A2 - A1 - A2 - F1 - F2 - F1 - F2 -",
        "G1 - G2 - G1 - G2 - E1 - E2 - E1 - E2 -",
        "A1 - A2 - A1 - A2 - C2 - C3 - C2 - C3 -",
        "D2 - D3 - A1 - A2 - E2 - E3 - E2 - E3 -",
    ]
    lead_pattern = [
        "A4 - C5 - E5 - C5 - A4 - - - F4 - A4 - C5 - - -",
        "G4 - B4 - D5 - B4 - G4 - - - E4 - G4 - B4 - - -",
        "A4 - C5 - E5 - A5 - G5 - E5 - C5 - A4 - - - - -",
        "D5 - - C5 B4 - A4 - E5 - - D5 C5 - - -",
    ]
    stab_pattern = [
        "A3 - - - A3 - - - F3 - - - F3 - - -",
        "G3 - - - G3 - - - E3 - - - E3 - - -",
        "A3 - - - A3 - - - C4 - - - C4 - - -",
        "D4 - - - A3 - - - E4 - - - E4 - - -",
    ]

    total = int(RATE * step * 16 * len(bass_pattern)) + int(RATE * 0.4)
    track = np.zeros(total)
    rng = np.random.default_rng(23)

    def lay(pattern, voice, gain, duty=0.5, length=1.0):
        for bar, line in enumerate(pattern):
            for i, token in enumerate(line.split()[:16]):
                if token == "-":
                    continue
                start = int(RATE * step * (bar * 16 + i))
                dur = step * length
                f = freq(token)
                if voice == "square":
                    data = env(square(f, dur, duty), attack=0.003,
                               decay=dur * 0.2, sustain=0.7, release=dur * 0.3)
                else:
                    data = env(triangle(f, dur), attack=0.004,
                               decay=dur * 0.2, sustain=0.7, release=dur * 0.35)
                nonlocal track
                track = at(track, data * gain, start)

    lay(bass_pattern, "triangle", 0.36, length=1.5)
    lay(lead_pattern, "square", 0.24, duty=0.5, length=1.5)
    lay(stab_pattern, "square", 0.12, duty=0.12, length=2.6)

    for bar in range(len(bass_pattern)):
        for b in range(4):
            base = int(RATE * step * (bar * 16 + b * 4))
            track = at(track, env(sine(104, 0.12, sweep=-360), attack=0.002,
                                  release=0.09) * 0.5, base)
            track = at(track, env(noise(0.10, rng), attack=0.001, release=0.08) * 0.25,
                       base + int(RATE * step * 2))
            for eighth in range(4):
                track = at(track, env(noise(0.03, rng), attack=0.001, release=0.026) * 0.07,
                           base + int(RATE * step * eighth))

    peak = np.max(np.abs(track))
    return track / peak * 0.82 if peak else track


def main():
    os.makedirs(OUT, exist_ok=True)
    effects = {
        "jump.wav": sfx_jump(),
        "ring.wav": sfx_ring(),
        "spindash_charge.wav": sfx_spindash_charge(),
        "spindash_release.wav": sfx_spindash_release(),
        "spring.wav": sfx_spring(),
        "hurt.wav": sfx_hurt(),
        "break.wav": sfx_break(),
        "pop.wav": sfx_pop(),
        "checkpoint.wav": sfx_checkpoint(),
        "extra_life.wav": sfx_extra_life(),
        "death.wav": sfx_death(),
        "skid.wav": sfx_skid(),
        "goal.wav": sfx_goal(),
        "music_zone.wav": music_zone(),
        "music_boss.wav": music_boss(),
    }
    for name, samples in effects.items():
        write_wav(name, samples)


if __name__ == "__main__":
    main()
