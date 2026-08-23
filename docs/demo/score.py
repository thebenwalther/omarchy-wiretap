#!/usr/bin/env python3
"""Original 14s Wiretap promo score. Writes a 48 kHz stereo WAV to argv[1].

The cue is intentionally electronic rather than an imitation of acoustic
instruments: two glassy "wire" voices, a centered tap, packet-like clicks,
warm pads, and a restrained low pulse. Its two arrivals line up with the
title-to-panel and panel-to-end-card transitions in ``record``.
"""

from __future__ import annotations

import array
import math
import random
import struct
import sys
import wave

SR = 48_000
DURATION = 14.2
N = int(DURATION * SR)
BPM = 96.0
BEAT = 60.0 / BPM
TAU = 2.0 * math.pi


def midi_hz(note: float) -> float:
    return 440.0 * 2.0 ** ((note - 69.0) / 12.0)


def pan_gains(pan: float) -> tuple[float, float]:
    position = (max(-1.0, min(1.0, pan)) + 1.0) * math.pi / 4.0
    return math.cos(position), math.sin(position)


def smoothstep(value: float) -> float:
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


class Mix:
    def __init__(self) -> None:
        self.left = array.array("d", [0.0]) * N
        self.right = array.array("d", [0.0]) * N
        self.aux_left = array.array("d", [0.0]) * N
        self.aux_right = array.array("d", [0.0]) * N

    def add(
        self,
        index: int,
        sample: float,
        left: float,
        right: float,
        send: float = 0.0,
    ) -> None:
        if 0 <= index < N:
            l_sample = sample * left
            r_sample = sample * right
            self.left[index] += l_sample
            self.right[index] += r_sample
            self.aux_left[index] += l_sample * send
            self.aux_right[index] += r_sample * send

    def pad(
        self,
        start: float,
        duration: float,
        note: float,
        velocity: float,
        pan: float,
    ) -> None:
        """A wide, slowly opening additive pad with no aliased saw waves."""
        first = int(start * SR)
        count = min(int(duration * SR), N - first)
        if count <= 0:
            return
        frequency = midi_hz(note)
        left_gain, right_gain = pan_gains(pan)
        phase_l = 0.0
        phase_r = 0.7
        partials = ((1, 1.0), (2, 0.24), (3, 0.12), (5, 0.045))
        for offset in range(count):
            time = offset / SR
            attack = smoothstep(time / 0.42)
            release = smoothstep((duration - time) / 0.9)
            envelope = attack * release
            # Tiny independent drift supplies width without moving the bass.
            drift = 1.0 + 0.0009 * math.sin(TAU * 0.17 * time + note)
            phase_l += TAU * frequency * drift / SR
            phase_r += TAU * frequency * (2.0 - drift) / SR
            sample_l = 0.0
            sample_r = 0.0
            for harmonic, amount in partials:
                sample_l += math.sin(phase_l * harmonic) * amount
                sample_r += math.sin(phase_r * harmonic) * amount
            index = first + offset
            level = velocity * envelope
            self.left[index] += sample_l * level * left_gain
            self.right[index] += sample_r * level * right_gain
            self.aux_left[index] += sample_l * level * left_gain * 0.26
            self.aux_right[index] += sample_r * level * right_gain * 0.26

    def glass(
        self,
        start: float,
        note: float,
        velocity: float,
        pan: float,
        duration: float = 0.9,
    ) -> None:
        """A short glass/fiber pluck used as the Wiretap melodic identity."""
        first = int(start * SR)
        count = min(int(duration * SR), N - first)
        if count <= 0:
            return
        frequency = midi_hz(note)
        left, right = pan_gains(pan)
        # Slightly inharmonic modes keep this from sounding like a toy piano.
        modes = ((1.0, 1.0, 4.6), (2.01, 0.45, 6.8), (3.96, 0.22, 8.5), (7.08, 0.08, 12.0))
        phases = [0.0, 0.4, 1.1, 2.0]
        for offset in range(count):
            time = offset / SR
            attack = min(1.0, time / 0.004)
            sample = 0.0
            for mode, amount, decay in modes:
                sample += math.sin(TAU * frequency * mode * time + phases[int(mode) % 4]) * amount * math.exp(-time * decay)
            sample *= attack * velocity
            self.add(first + offset, sample, left, right, send=0.48)

    def bass(
        self,
        start: float,
        note: float,
        velocity: float,
        duration: float = 0.5,
    ) -> None:
        first = int(start * SR)
        count = min(int(duration * SR), N - first)
        if count <= 0:
            return
        frequency = midi_hz(note)
        phase = 0.0
        for offset in range(count):
            time = offset / SR
            glide = 1.0 + 0.012 * math.exp(-time * 18.0)
            phase += TAU * frequency * glide / SR
            envelope = min(1.0, time / 0.012) * math.exp(-time * 2.25)
            body = math.sin(phase) + 0.18 * math.sin(phase * 2.0)
            sample = math.tanh(body * 1.25) * envelope * velocity
            self.add(first + offset, sample, 0.71, 0.71)

    def kick(self, start: float, velocity: float = 1.0) -> None:
        first = int(start * SR)
        count = min(int(0.34 * SR), N - first)
        phase = 0.0
        for offset in range(max(0, count)):
            time = offset / SR
            frequency = 44.0 + 105.0 * math.exp(-time * 26.0)
            phase += TAU * frequency / SR
            body = math.sin(phase) * math.exp(-time * 10.5)
            knock = math.sin(TAU * 930.0 * time) * math.exp(-time * 72.0) * 0.10
            self.add(first + offset, (body + knock) * velocity, 0.71, 0.71)

    def packet(
        self,
        start: float,
        velocity: float,
        pan: float,
        rng: random.Random,
        open_tick: bool = False,
    ) -> None:
        duration = 0.12 if open_tick else 0.032
        first = int(start * SR)
        count = min(int(duration * SR), N - first)
        left, right = pan_gains(pan)
        lowpass = 0.0
        highpass = 0.0
        hp_amount = 1.0 - math.exp(-TAU * (5_400.0 if open_tick else 7_200.0) / SR)
        lp_amount = 1.0 - math.exp(-TAU * 13_500.0 / SR)
        decay = 28.0 if open_tick else 105.0
        for offset in range(max(0, count)):
            time = offset / SR
            noise = rng.uniform(-1.0, 1.0)
            highpass += hp_amount * (noise - highpass)
            high = noise - highpass
            lowpass += lp_amount * (high - lowpass)
            sample = lowpass * math.exp(-time * decay) * velocity
            self.add(first + offset, sample, left, right, send=0.12)

    def tap(self, start: float, velocity: float, rng: random.Random) -> None:
        """A centered, soft transient—the vertical tap between two wires."""
        first = int(start * SR)
        count = min(int(0.14 * SR), N - first)
        lowpass = 0.0
        for offset in range(max(0, count)):
            time = offset / SR
            noise = rng.uniform(-1.0, 1.0)
            amount = 1.0 - math.exp(-TAU * 2_600.0 / SR)
            lowpass += amount * (noise - lowpass)
            tone = math.sin(TAU * 310.0 * time) * 0.18
            sample = (lowpass * 0.42 + tone) * math.exp(-time * 31.0) * velocity
            self.add(first + offset, sample, 0.71, 0.71, send=0.18)

    def sweep(self, start: float, duration: float, velocity: float, rng: random.Random) -> None:
        """A band-limited lift into a visual transition."""
        first = int(start * SR)
        count = min(int(duration * SR), N - first)
        low = 0.0
        high = 0.0
        for offset in range(max(0, count)):
            time = offset / SR
            progress = time / duration
            noise = rng.uniform(-1.0, 1.0)
            cutoff = 700.0 + 7_500.0 * progress * progress
            low_amount = 1.0 - math.exp(-TAU * cutoff / SR)
            high_amount = 1.0 - math.exp(-TAU * max(160.0, cutoff * 0.18) / SR)
            low += low_amount * (noise - low)
            high += high_amount * (low - high)
            band = low - high
            envelope = smoothstep(progress) * smoothstep((duration - time) / 0.09)
            pan = -0.58 + 1.16 * progress
            left, right = pan_gains(pan)
            self.add(first + offset, band * envelope * velocity, left, right, send=0.28)

    def sub_drop(self, start: float, velocity: float) -> None:
        first = int(start * SR)
        count = min(int(1.15 * SR), N - first)
        phase = 0.0
        for offset in range(max(0, count)):
            time = offset / SR
            frequency = 59.0 - 16.0 * smoothstep(time / 1.15)
            phase += TAU * frequency / SR
            envelope = min(1.0, time / 0.012) * math.exp(-time * 3.0)
            self.add(first + offset, math.sin(phase) * envelope * velocity, 0.71, 0.71)

    def add_room(self) -> None:
        """Sparse stereo reflections: depth without washing out the transients."""
        taps = (
            (0.071, 0.24, False),
            (0.113, 0.18, True),
            (0.181, 0.14, False),
            (0.293, 0.105, True),
            (0.419, 0.075, False),
            (0.631, 0.045, True),
        )
        for delay, gain, crossed in taps:
            shift = int(delay * SR)
            for index in range(shift, N):
                source = index - shift
                if crossed:
                    self.left[index] += self.aux_right[source] * gain
                    self.right[index] += self.aux_left[source] * gain
                else:
                    self.left[index] += self.aux_left[source] * gain
                    self.right[index] += self.aux_right[source] * gain


CHORDS = (
    (47, 54, 59, 61, 62),  # Bm(add9)
    (43, 50, 54, 59, 62),  # Gmaj7
    (50, 57, 61, 64, 66),  # Dmaj9
    (45, 52, 59, 61, 64),  # A(add9)
    (47, 54, 57, 61, 62),  # Bm9
    (47, 54, 59, 61, 66),  # Bm(add9), open resolve
)
ROOTS = (35, 31, 38, 33, 35, 35)


def compose(path: str) -> None:
    mix = Mix()
    rng = random.Random(0x57495245)

    # The harmony breathes in 2.5-second bars. The first is deliberately bare;
    # the rhythm arrives with the panel and leaves again for the end card.
    for bar, chord in enumerate(CHORDS):
        start = bar * 4.0 * BEAT
        duration = 3.15 if bar < 5 else 1.7
        base_level = 0.035 if bar == 0 else (0.043 if bar < 4 else 0.052)
        for voice, note in enumerate(chord):
            if bar == 0 and voice < 2:
                continue
            pan = (-0.46, 0.34, -0.18, 0.48, 0.08)[voice]
            mix.pad(start, duration, note, base_level * (0.86 if voice == 0 else 1.0), pan)

    # The opening mark: two bright wires answering each other, then a center tap.
    for start, note, pan, level in (
        (0.28, 71, -0.52, 0.115),
        (0.61, 78, 0.52, 0.09),
        (1.22, 73, -0.42, 0.072),
        (1.55, 78, 0.42, 0.058),
        (2.18, 74, -0.32, 0.052),
        (2.49, 78, 0.32, 0.045),
    ):
        mix.glass(start, note, level, pan, duration=1.05)
    mix.tap(0.93, 0.22, rng)
    mix.tap(1.87, 0.15, rng)

    # Lift and land exactly on the title -> live panel transition.
    mix.sweep(2.62, 0.63, 0.16, rng)
    mix.sub_drop(3.25, 0.32)
    mix.kick(3.25, 0.72)
    mix.glass(3.25, 78, 0.12, -0.48)
    mix.glass(3.41, 83, 0.09, 0.48)

    # A quiet, syncopated packet stream under the live panel. It moves across
    # the stereo field while the centered tap and low pulse hold the UI steady.
    rhythmic_start = 3.25
    step = BEAT / 2.0
    arp_patterns = (
        (59, 61, 66, 62, 71, 66, 61, 62),
        (59, 62, 66, 69, 73, 69, 66, 62),
        (57, 61, 64, 69, 71, 69, 64, 61),
    )
    for index in range(22):
        start = rhythmic_start + index * step
        pattern = arp_patterns[min(2, index // 8)]
        note = pattern[index % 8]
        pan = -0.62 if index % 2 == 0 else 0.62
        level = 0.046 if index % 4 else 0.061
        mix.glass(start, note, level, pan, duration=0.48)
        mix.packet(start + step * 0.5, 0.105 if index % 4 else 0.15, -pan * 0.75, rng, index % 7 == 6)

    for pulse in range(11):
        start = rhythmic_start + pulse * BEAT
        absolute = start
        bar = min(3, max(1, int(absolute / (4.0 * BEAT))))
        root = ROOTS[bar]
        mix.bass(start, root, 0.17 if pulse % 4 else 0.22, duration=0.54)
        if pulse % 2 == 0:
            mix.kick(start, 0.54 if pulse else 0.68)
        else:
            mix.tap(start, 0.16, rng)

    # A second lift resolves into the repository/end card. Percussion stops;
    # the logo motif returns higher and leaves a clean tail.
    mix.sweep(9.42, 0.63, 0.19, rng)
    mix.sub_drop(10.05, 0.36)
    mix.kick(10.05, 0.62)
    for start, note, pan, level, duration in (
        (10.05, 71, -0.55, 0.12, 1.15),
        (10.38, 78, 0.55, 0.105, 1.2),
        (10.78, 83, 0.08, 0.078, 1.35),
        (11.72, 73, -0.42, 0.066, 1.25),
        (12.05, 78, 0.42, 0.058, 1.3),
        (12.53, 83, 0.0, 0.052, 1.45),
    ):
        mix.glass(start, note, level, pan, duration)
    mix.tap(10.69, 0.2, rng)

    mix.add_room()
    write_wav(path, mix)


def write_wav(path: str, mix: Mix) -> None:
    # Gentle bus compression and saturation before the exact loudness pass in
    # record. A linked detector keeps the stereo image from wandering.
    envelope = 0.0
    release = math.exp(-1.0 / (0.16 * SR))
    processed_left = array.array("d", [0.0]) * N
    processed_right = array.array("d", [0.0]) * N
    peak = 1e-9
    for index in range(N):
        detector = max(abs(mix.left[index]), abs(mix.right[index]))
        envelope = max(detector, envelope * release)
        gain = 1.0
        if envelope > 0.34:
            gain = (0.34 + (envelope - 0.34) * 0.34) / envelope
        left = math.tanh(mix.left[index] * gain * 1.38)
        right = math.tanh(mix.right[index] * gain * 1.38)
        processed_left[index] = left
        processed_right[index] = right
        peak = max(peak, abs(left), abs(right))

    gain = 0.88 / peak
    fade_in = int(0.065 * SR)
    fade_out_start = int(13.15 * SR)
    fade_out_length = N - fade_out_start
    with wave.open(path, "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(SR)
        frames = bytearray()
        for index in range(N):
            fade = 1.0
            if index < fade_in:
                fade = smoothstep(index / fade_in)
            elif index >= fade_out_start:
                fade = smoothstep((N - index) / fade_out_length)
            left = max(-1.0, min(1.0, processed_left[index] * gain * fade))
            right = max(-1.0, min(1.0, processed_right[index] * gain * fade))
            frames += struct.pack("<hh", int(left * 32_767), int(right * 32_767))
        output.writeframes(frames)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: score.py OUT.wav", file=sys.stderr)
        raise SystemExit(2)
    compose(sys.argv[1])
