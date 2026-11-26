#!/usr/bin/env python3
"""Writes the home base station sounds into game/data/audio/hub_*.wav (#1401, AUD-1, CRW-2, NAM-3).

Short, soft sounds for the station screens: pointing onto an item, select, back, a refused
press, a crafted upgrade, an unmounted part and the launch row chosen. Mounting reuses
part_slotted.wav. Every sound is synthesised here from sines, a triangle and seeded noise,
so it is original and the same on every run: re-running the script rewrites identical files.
A script of its own, not part of tools/synth_sounds.py (lane-b's), so the lanes do not edit
the same file. Levels are kept low and attacks rounded so nothing clicks or shrills; the
game sets the final level per sound in game/data/audio/hub_sounds.json.
Standard library only.
Usage: python3 tools/synth_hub_sounds.py
"""

import math
import os
import random
import struct
import wave

RATE = 22050
SEED = 1401
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "data", "audio")


def tri(p):
	"""A triangle wave: softer than a square or saw, brighter than a sine."""
	x = (p / (2.0 * math.pi)) % 1.0
	return 4.0 * abs(x - 0.5) - 1.0


def shape(t, length, attack=0.006, release=0.5):
	"""A rounded attack, then an exponential fall that reaches silence at `length`."""
	if t >= length:
		return 0.0
	rise = min(1.0, t / attack) if attack > 0.0 else 1.0
	rise = 0.5 - 0.5 * math.cos(math.pi * rise)
	fall = math.exp(-t / (length * release))
	end = min(1.0, (length - t) / 0.01)  # The last 10 ms fade to zero, so no tail click.
	return rise * fall * end


def tone(samples, start, length, freq_from, freq_to, level, wave_fn=math.sin, release=0.5):
	"""Adds a gliding tone from `start` seconds, its pitch sliding `freq_from` to `freq_to`."""
	phase = 0.0
	first = int(start * RATE)
	for i in range(int(length * RATE)):
		t = i / RATE
		freq = freq_from + (freq_to - freq_from) * (t / length)
		phase += 2.0 * math.pi * freq / RATE
		if first + i < len(samples):
			samples[first + i] += level * shape(t, length, release=release) * wave_fn(phase)


def noise(samples, start, length, level, smooth, seed):
	"""Adds seeded, low-passed noise: a soft breath or a mechanical rub."""
	rng = random.Random(seed)
	state = 0.0
	first = int(start * RATE)
	for i in range(int(length * RATE)):
		state += smooth * (rng.uniform(-1.0, 1.0) - state)
		if first + i < len(samples):
			samples[first + i] += level * shape(i / RATE, length, attack=0.004, release=0.35) * state


def point():
	s = [0.0] * int(0.05 * RATE)
	tone(s, 0.0, 0.05, 1320.0, 1250.0, 0.35, release=0.25)
	return s


def select():
	s = [0.0] * int(0.14 * RATE)
	tone(s, 0.0, 0.06, 660.0, 660.0, 0.4, tri, release=0.4)
	tone(s, 0.045, 0.09, 880.0, 880.0, 0.4, tri, release=0.4)
	return s


def back():
	s = [0.0] * int(0.14 * RATE)
	tone(s, 0.0, 0.06, 880.0, 880.0, 0.35, tri, release=0.4)
	tone(s, 0.045, 0.09, 587.0, 560.0, 0.35, tri, release=0.4)
	return s


def refused():
	"""Two low, dull pulses: plainly 'no', without a harsh buzz."""
	s = [0.0] * int(0.26 * RATE)
	for start in (0.0, 0.12):
		tone(s, start, 0.11, 196.0, 185.0, 0.45, tri, release=0.5)
		tone(s, start, 0.11, 294.0, 277.0, 0.18, math.sin, release=0.5)
	return s


def crafted():
	"""A rising three-note figure over a soft breath: something has been made."""
	s = [0.0] * int(0.7 * RATE)
	noise(s, 0.0, 0.35, 0.25, 0.08, SEED)
	for start, freq in ((0.0, 523.0), (0.08, 659.0), (0.16, 784.0)):
		tone(s, start, 0.5, freq, freq, 0.28, math.sin, release=0.35)
		tone(s, start, 0.5, freq * 2.0, freq * 2.0, 0.06, math.sin, release=0.2)
	return s


def unmounted():
	"""A short mechanical release: a rub of noise and a falling tone."""
	s = [0.0] * int(0.28 * RATE)
	noise(s, 0.0, 0.08, 0.5, 0.35, SEED + 1)
	tone(s, 0.02, 0.24, 520.0, 300.0, 0.35, tri, release=0.4)
	return s


def launch():
	"""A warm open chord swelling briefly; the engine sound (launch.wav) takes over after it."""
	s = [0.0] * int(0.5 * RATE)
	for freq in (392.0, 587.0, 784.0):
		tone(s, 0.0, 0.5, freq, freq * 1.02, 0.2, math.sin, release=0.45)
	return s


SOUNDS = {
	"hub_point.wav": point,
	"hub_select.wav": select,
	"hub_back.wav": back,
	"hub_refused.wav": refused,
	"hub_crafted.wav": crafted,
	"hub_unmounted.wav": unmounted,
	"hub_launch.wav": launch,
}


def write(name, samples):
	peak = max(abs(v) for v in samples) or 1.0
	gain = 0.7 / peak  # Every file peaks at the same level; the game sets each one's loudness.
	frames = b"".join(struct.pack("<h", int(round(max(-1.0, min(1.0, v * gain)) * 32767))) for v in samples)
	with wave.open(os.path.join(OUT, name), "wb") as out:
		out.setnchannels(1)
		out.setsampwidth(2)
		out.setframerate(RATE)
		out.writeframes(frames)


def main():
	for name, make in SOUNDS.items():
		write(name, make())
		print("wrote", name)


if __name__ == "__main__":
	main()
