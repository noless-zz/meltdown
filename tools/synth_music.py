#!/usr/bin/env python3
"""Writes the placeholder music loops into game/data/audio/ (#1303, AUD-3, NAM-3).

Every loop is synthesised here from sines, squares, saws and seeded noise, so it
is original and the same on every run: re-running the script rewrites identical
files. Each loop is LOOP_SECONDS long at one tempo, every tone a whole number of
cycles in the loop and every note ending inside it, so the loops repeat without a
click and the layers stay on the beat when they play together. Standard library
only. Usage: python3 tools/synth_music.py
"""

import math
import os
import random
import struct
import wave

RATE = 22050
LOOP_SECONDS = 8.0
BEAT = 0.5  # 120 beats a minute: 16 beats in a loop.
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "data", "audio")


def loop_freq(freq):
	"""`freq` moved to the nearest whole number of cycles in the loop."""
	return round(freq * LOOP_SECONDS) / LOOP_SECONDS


def note(midi):
	return loop_freq(440.0 * 2.0 ** ((midi - 69) / 12.0))


def tone(shape, phase):
	if shape == "square":
		return 1.0 if math.sin(phase) >= 0.0 else -1.0
	if shape == "saw":
		return (phase / math.pi) % 2.0 - 1.0
	if shape == "soft_square":
		return math.sin(phase) + math.sin(3.0 * phase) / 3.0 + math.sin(5.0 * phase) / 5.0
	return math.sin(phase)


def add_note(out, start, length, freq, shape="sine", gain=1.0, attack=0.01, release=0.08):
	"""Adds one note from `start` seconds for `length` seconds, faded in and out."""
	first = int(start * RATE)
	count = int(length * RATE)
	for i in range(count):
		t = i / RATE
		env = min(1.0, t / attack) if attack > 0.0 else 1.0
		left = length - t
		if left < release:
			env *= max(0.0, left / release)
		out[(first + i) % len(out)] += gain * env * tone(shape, 2.0 * math.pi * freq * t)


def add_noise_tick(out, start, length, gain, rng):
	first = int(start * RATE)
	for i in range(int(length * RATE)):
		t = i / RATE
		out[(first + i) % len(out)] += gain * math.exp(-t * 60.0) * rng.uniform(-1.0, 1.0)


def add_drone(out, freqs, gain, swell=0.0):
	"""A held chord across the whole loop; `swell` rises and falls once a loop."""
	for i in range(len(out)):
		t = i / RATE
		level = gain * (1.0 - swell * 0.5 * (1.0 + math.cos(2.0 * math.pi * t / LOOP_SECONDS)))
		out[i] += level * sum(math.sin(2.0 * math.pi * f * t) for f in freqs) / len(freqs)


def blank():
	return [0.0] * int(LOOP_SECONDS * RATE)


def calm():
	out = blank()
	add_drone(out, [note(45), note(52), note(57)], 0.5, 0.4)
	pattern = [69, 72, 76, 72, 69, 71, 74, 71]
	for index, midi in enumerate(pattern):
		add_note(out, index * 2 * BEAT, 2 * BEAT, note(midi), "sine", 0.22, 0.05, 0.6)
	return out


def tension_low():
	out = blank()
	bass = [33, 33, 45, 33, 33, 33, 45, 34] * 4
	for index, midi in enumerate(bass):
		add_note(out, index * BEAT / 2, BEAT / 2 * 0.8, note(midi), "soft_square", 0.5, 0.005, 0.05)
	return out


def tension_high(rng):
	out = blank()
	for step in range(int(LOOP_SECONDS / (BEAT / 4))):
		accent = 1.0 if step % 4 == 0 else 0.45
		add_noise_tick(out, step * BEAT / 4, 0.08, 0.35 * accent, rng)
	for bar in range(4):
		add_note(out, bar * 4 * BEAT + 3 * BEAT, BEAT * 0.9, note(70), "saw", 0.18, 0.01, 0.2)
		add_note(out, bar * 4 * BEAT + 3 * BEAT, BEAT * 0.9, note(75), "saw", 0.12, 0.01, 0.2)
	return out


def meltdown(rng):
	out = blank()
	bass = [33, 33, 36, 33, 34, 33, 36, 39]
	for step in range(int(LOOP_SECONDS / (BEAT / 4))):
		midi = bass[(step // 4) % len(bass)]
		add_note(out, step * BEAT / 4, BEAT / 4 * 0.85, note(midi), "saw", 0.4, 0.003, 0.03)
		if step % 2 == 0:
			add_noise_tick(out, step * BEAT / 4, 0.05, 0.25, rng)
	# A two-tone siren over the bass, one call a bar.
	for bar in range(4):
		add_note(out, bar * 4 * BEAT, 2 * BEAT, note(81), "soft_square", 0.16, 0.05, 0.1)
		add_note(out, bar * 4 * BEAT + 2 * BEAT, 2 * BEAT, note(76), "soft_square", 0.16, 0.05, 0.1)
	return out


def hub():
	out = blank()
	add_drone(out, [note(48), note(55)], 0.35, 0.3)
	pattern = [72, 76, 79, 84, 79, 76, 74, 77, 81, 77, 74, 72, 76, 79, 76, 72]
	for index, midi in enumerate(pattern):
		add_note(out, index * BEAT, BEAT * 1.6, note(midi), "sine", 0.2, 0.01, 0.7)
	return out


def write(name, samples):
	peak = max(1e-6, max(abs(s) for s in samples))
	path = os.path.join(OUT, name + ".wav")
	with wave.open(path, "wb") as out:
		out.setnchannels(1)
		out.setsampwidth(2)
		out.setframerate(RATE)
		out.writeframes(b"".join(struct.pack("<h", int(s / peak * 0.8 * 32767)) for s in samples))


def main():
	os.makedirs(OUT, exist_ok=True)
	write("music_calm", calm())
	write("music_tension_low", tension_low())
	write("music_tension_high", tension_high(random.Random(21)))
	write("music_meltdown", meltdown(random.Random(22)))
	write("music_hub", hub())


if __name__ == "__main__":
	main()
