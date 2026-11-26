#!/usr/bin/env python3
"""Writes the placeholder launch sound into game/data/audio/launch.wav (#1396, AUD-1, NAM-3).

The pilot's ship leaving the home base: the engine spools up over the glow and the
fade out (about 1.1 s in the game), a low hum and a breathy roar rising in pitch and
loudness together, then a short tail that dies away behind the fade. Everything is
synthesised here from sines, a saw and seeded noise, so it is original and the same on
every run: re-running the script rewrites an identical file. This is a script of its own,
not part of tools/synth_sounds.py, so the lanes do not edit the same file.
Standard library only.
Usage: python3 tools/synth_launch.py
"""

import math
import os
import random
import struct
import wave

RATE = 22050
RISE_SECONDS = 1.1
TAIL_SECONDS = 0.4
COUNT = int(RATE * (RISE_SECONDS + TAIL_SECONDS))
SEED = 1396
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "data", "audio")


def saw(p):
	return (p / math.pi) % 2.0 - 1.0


def smoothed_noise(seed, count):
	"""Seeded noise through a low-pass whose cutoff opens as the engine spools up."""
	rng = random.Random(seed)
	out = []
	level = 0.0
	for i in range(count):
		rise = min(1.0, i / (RATE * RISE_SECONDS))
		level += (0.03 + 0.25 * rise) * (rng.uniform(-1.0, 1.0) - level)
		out.append(level)
	peak = max(abs(v) for v in out) or 1.0
	return [v / peak for v in out]


def envelope(t):
	"""Soft start, a swell that keeps rising through the launch, then a smooth tail."""
	attack = min(1.0, t / 0.08)
	if t <= RISE_SECONDS:
		return attack * (0.35 + 0.65 * (t / RISE_SECONDS) ** 1.5)
	fall = (t - RISE_SECONDS) / TAIL_SECONDS
	return 0.5 * (1.0 + math.cos(math.pi * min(1.0, fall)))


def launch():
	air = smoothed_noise(SEED, COUNT)
	out = []
	hum_phase = 0.0
	whine_phase = 0.0
	for i in range(COUNT):
		t = i / RATE
		rise = min(1.0, t / RISE_SECONDS)
		hum_freq = 70.0 + 150.0 * rise * rise
		whine_freq = 260.0 + 520.0 * rise * rise
		hum_phase += 2.0 * math.pi * hum_freq / RATE
		whine_phase += 2.0 * math.pi * whine_freq / RATE
		hum = 0.45 * math.sin(hum_phase) + 0.12 * saw(2.0 * hum_phase)
		whine = 0.12 * rise * math.sin(whine_phase)
		out.append(envelope(t) * (hum + whine + 0.4 * air[i]))
	return out


def write(name, samples):
	peak = max(abs(v) for v in samples) or 1.0
	frames = b"".join(struct.pack("<h", int(round(0.8 * v / peak * 32767))) for v in samples)
	path = os.path.join(OUT, name + ".wav")
	with wave.open(path, "wb") as out:
		out.setnchannels(1)
		out.setsampwidth(2)
		out.setframerate(RATE)
		out.writeframes(frames)
	return path


def main():
	print(write("launch", launch()))


if __name__ == "__main__":
	main()
