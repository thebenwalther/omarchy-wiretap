#!/usr/bin/env python3
"""Original 14s Wiretap promo score. Writes a 48 kHz stereo WAV to argv[1]."""

from __future__ import annotations

import array
import math
import random
import struct
import sys
import wave

SR = 48000
DURATION = 14.2
BPM = 100.0
BEAT = 60.0 / BPM
N = int(DURATION * SR)


def midi_hz(n: float) -> float:
    return 440.0 * (2.0 ** ((n - 69.0) / 12.0))


def equal_pan(pan: float) -> tuple[float, float]:
    # pan -1 left … +1 right
    a = (pan + 1.0) * 0.5
    return math.sqrt(1.0 - a), math.sqrt(a)


class Mix:
    def __init__(self) -> None:
        self.l = array.array("d", [0.0]) * N
        self.r = array.array("d", [0.0]) * N

    def add(self, i: int, sample: float, left: float, right: float) -> None:
        if 0 <= i < N:
            self.l[i] += sample * left
            self.r[i] += sample * right

    def tone(
        self,
        start: float,
        dur: float,
        freq: float,
        vel: float,
        pan: float,
        harmonics: tuple[tuple[float, float], ...],
        attack: float,
        decay: float,
        sustain: float,
        release: float,
    ) -> None:
        i0 = int(start * SR)
        n = min(int(dur * SR), N - i0)
        if n <= 0:
            return
        left, right = equal_pan(pan)
        hold = max(0.0, dur - attack - decay - release)
        two_pi = 2.0 * math.pi
        for i in range(n):
            t = i / SR
            if t < attack:
                env = t / attack if attack > 0 else 1.0
            elif t < attack + decay:
                env = 1.0 + (sustain - 1.0) * ((t - attack) / decay)
            elif t < attack + decay + hold:
                env = sustain
            else:
                rt = dur - t
                env = sustain * (rt / release) if release > 0 else 0.0
            if env <= 0:
                continue
            phase = two_pi * freq * t
            s = 0.0
            for h, amp in harmonics:
                s += amp * math.sin(phase * h)
            self.add(i0 + i, s * env * vel, left, right)

    def kick(self, start: float, vel: float = 1.0) -> None:
        i0 = int(start * SR)
        n = min(int(0.28 * SR), N - i0)
        phase = 0.0
        click_phase = 0.0
        for i in range(max(0, n)):
            t = i / SR
            f = 46.0 + 130.0 * math.exp(-t * 22.0)
            phase += 2.0 * math.pi * f / SR
            body = math.sin(phase) * math.exp(-t * 9.5)
            click_phase += 2.0 * math.pi * 1800.0 / SR
            click = math.sin(click_phase) * math.exp(-t * 70.0) * 0.22
            self.add(i0 + i, (body + click) * vel * 1.35, 0.72, 0.72)

    def clap(self, start: float, vel: float = 0.7, rng: random.Random | None = None) -> None:
        rng = rng or random.Random(7)
        bursts = (0.0, 0.012, 0.024, 0.041)
        left, right = equal_pan(0.12)
        lp_a = 1.0 - math.exp(-2.0 * math.pi * 4200.0 / SR)
        hp_a = 1.0 - math.exp(-2.0 * math.pi * 900.0 / SR)
        for delay in bursts:
            i0 = int((start + delay) * SR)
            n = min(int(0.12 * SR), N - i0)
            hp = 0.0
            lp = 0.0
            for i in range(max(0, n)):
                t = i / SR
                white = rng.uniform(-1.0, 1.0)
                hp += hp_a * (white - hp)
                band = white - hp
                lp += lp_a * (band - lp)
                env = math.exp(-t * 38.0)
                self.add(i0 + i, lp * env * vel * 0.7, left, right)

    def hat(self, start: float, vel: float, open_hat: bool, rng: random.Random) -> None:
        dur = 0.16 if open_hat else 0.038
        i0 = int(start * SR)
        n = min(int(dur * SR), N - i0)
        left, right = equal_pan(0.35 if open_hat else -0.25)
        hp_a = 1.0 - math.exp(-2.0 * math.pi * 6000.0 / SR)
        lp_a = 1.0 - math.exp(-2.0 * math.pi * 11000.0 / SR)
        hp = 0.0
        lp = 0.0
        for i in range(max(0, n)):
            t = i / SR
            white = rng.uniform(-1.0, 1.0)
            hp += hp_a * (white - hp)
            high = white - hp
            lp += lp_a * (high - lp)
            env = math.exp(-t * (22.0 if open_hat else 85.0))
            self.add(i0 + i, lp * env * vel * 0.7, left, right)


PIANO = ((1.0, 1.0), (2.0, 0.28), (3.0, 0.10), (4.0, 0.04))
BASS = ((1.0, 1.0), (2.0, 0.42), (3.0, 0.08))
LEAD = ((1.0, 1.0), (2.0, 0.22), (3.0, 0.08), (5.0, 0.03))


def write_wav(path: str, mix: Mix) -> None:
    peak = 1e-9
    for i in range(N):
        peak = max(peak, abs(mix.l[i]), abs(mix.r[i]))
    gain = 0.78 / peak
    fade_in = int(0.06 * SR)
    fade_out_start = int(12.1 * SR)
    fade_out_len = N - fade_out_start
    with wave.open(path, "w") as wf:
        wf.setnchannels(2)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        frames = bytearray()
        for i in range(N):
            env = 1.0
            if i < fade_in:
                env = i / fade_in
            elif i >= fade_out_start:
                env = max(0.0, 1.0 - (i - fade_out_start) / fade_out_len)
            l = math.tanh(mix.l[i] * gain * env)
            r = math.tanh(mix.r[i] * gain * env)
            frames += struct.pack("<hh", int(l * 32000), int(r * 32000))
        wf.writeframes(frames)


def compose(path: str) -> None:
    mix = Mix()
    rng = random.Random(11)

    # Six bars at 100 BPM = 14.4s; last chord rings through the fade.
    # Am | F | C | G | Am | Am
    bass_roots = (45, 41, 36, 43, 45, 45)  # A2 F2 C2 G2 A2 A2
    voicings = (
        (57, 60, 64),  # A3 C4 E4
        (53, 57, 60),  # F3 A3 C4
        (55, 60, 64),  # G3 C4 E4
        (55, 59, 62),  # G3 B3 D4
        (57, 60, 64),
        (57, 64, 69),  # A3 E4 A4
    )

    bars = 6
    for bar in range(bars):
        t0 = bar * 4 * BEAT
        # drums: boom-bap, hats on 8ths
        for b in range(4):
            bt = t0 + b * BEAT
            if bar < 5 or b < 2:
                mix.kick(bt, 1.0 if b % 2 == 0 else 0.82)
            if b % 2 == 1 and bar >= 1 and (bar < 5 or b == 1):
                mix.clap(bt, 0.62, rng)
            if bar < 5:
                mix.hat(bt, 0.28 if b % 2 == 0 else 0.22, False, rng)
                mix.hat(bt + BEAT * 0.5, 0.18, b == 3, rng)
        # extra kick on the and of 4 in the middle
        if 1 <= bar <= 4:
            mix.kick(t0 + 3.5 * BEAT, 0.55)

        # bass: root, fifth, octave, walking 8ths
        root = bass_roots[bar]
        fifth = root + 7
        pattern = (
            (0.0, root, 0.9),
            (1.0, root, 0.7),
            (1.5, fifth, 0.55),
            (2.0, root, 0.85),
            (3.0, root + 12, 0.5),
            (3.5, fifth, 0.45),
        )
        if bar == 5:
            pattern = ((0.0, root, 0.9), (2.0, root, 0.5))
        for off, note, vel in pattern:
            mix.tone(
                t0 + off * BEAT,
                0.42 if bar < 5 else 1.6,
                midi_hz(note),
                vel * 0.7,
                0.0,
                BASS,
                attack=0.008,
                decay=0.18,
                sustain=0.35,
                release=0.16,
            )

        # piano chord on beat 1, echo on beat 3
        chord_dur = 2.15 if bar < 5 else 3.4
        for idx, note in enumerate(voicings[bar]):
            pan = -0.35 + 0.35 * idx
            mix.tone(
                t0,
                chord_dur,
                midi_hz(note),
                0.34,
                pan,
                PIANO,
                attack=0.012,
                decay=0.55,
                sustain=0.42,
                release=0.7,
            )
            mix.tone(
                t0 + 0.09,
                chord_dur,
                midi_hz(note),
                0.12,
                -pan,
                PIANO,
                attack=0.02,
                decay=0.5,
                sustain=0.3,
                release=0.7,
            )

    # Melody from bar 2, A-minor pentatonic hook.
    # 8ths: A4 C5 E5 D5 | C5 A4 G4 E4 | A4 C5 D5 E5 | G5 E5 D5 C5 | A4 (hold)
    hook = [
        (8, 69, 0.5),
        (8.5, 72, 0.5),
        (9, 76, 0.5),
        (9.5, 74, 0.5),
        (10, 72, 0.5),
        (10.5, 69, 0.5),
        (11, 67, 0.5),
        (11.5, 64, 0.5),
        (12, 69, 0.5),
        (12.5, 72, 0.5),
        (13, 74, 0.5),
        (13.5, 76, 0.5),
        (14, 79, 0.5),
        (14.5, 76, 0.5),
        (15, 74, 0.5),
        (15.5, 72, 0.5),
        (16, 69, 2.4),
    ]
    for beat, note, dur_beats in hook:
        start = beat * BEAT
        mix.tone(
            start,
            dur_beats * BEAT * 0.92,
            midi_hz(note),
            0.46,
            0.22,
            LEAD,
            attack=0.01,
            decay=0.14,
            sustain=0.55,
            release=0.22,
        )
        # quiet octave echo
        mix.tone(
            start + 0.14,
            dur_beats * BEAT * 0.7,
            midi_hz(note),
            0.12,
            -0.4,
            LEAD,
            attack=0.02,
            decay=0.2,
            sustain=0.3,
            release=0.3,
        )

    write_wav(path, mix)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: score.py OUT.wav", file=sys.stderr)
        sys.exit(2)
    compose(sys.argv[1])
