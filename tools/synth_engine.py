#!/usr/bin/env python3
"""Writes the placeholder engine sounds of the pilot's own ship into game/data/audio/ (#1398, AUD-1, NAM-3).

Three sounds: a low idle hum that is always on in flight, a thrust layer the game
raises in volume and pitch as the ship pushes and speeds up, and a short burst for
the afterburner kicking in. The idle and thrust loops are kept soft and free of
sharp edges so ten minutes of them do not tire the ear. Everything is synthesised
here from sines, saws and seeded noise, so it is original and the same on every
run: re-running the script rewrites identical files. Each loop is LOOP_SECONDS long
and every tone and wobble is a whole number of cycles in it, so the loops repeat
without a click. Standard library only.
Usage: python3 tools/synth_engine.py
"""

import math
import os
import random
import struct
import wave

RATE = 22050
LOOP_SECONDS = 2.0
COUNT = int(RATE * LOOP_SECONDS)
BURST_SECONDS = 0.6
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "data", "audio")


def whole(freq):
	"""`freq` moved to the nearest whole number of cycles in the loop."""
	return max(1, round(freq * LOOP_SECONDS)) / LOOP_SECONDS


def phase(freq, i):
	return 2.0 * math.pi * whole(freq) * i / RATE


def saw(p):
	return (p / math.pi) % 2.0 - 1.0


def looped_noise(seed, smooth, count=COUNT):
	"""Seeded noise, low-passed around the loop twice so its end meets its start."""
	rng = random.Random(seed)
	raw = [rng.uniform(-1.0, 1.0) for _ in range(count)]
	out = [0.0] * count
	level = 0.0
	for _ in range(2):
		for i in range(count):
			level += smooth * (raw[i] - level)
			out[i] = level
	peak = max(abs(v) for v in out) or 1.0
	return [v / peak for v in out]


def idle():
	"""Low steady hum: a deep sine pair, a faint soft saw and slow breathing."""
	rumble = looped_noise(1398_1, 0.02)
	out = []
	for i in range(COUNT):
		breath = 0.85 + 0.15 * math.sin(phase(0.5, i))
		tone = 0.55 * math.sin(phase(48.0, i)) + 0.25 * math.sin(phase(96.0, i)) + 0.08 * saw(phase(144.0, i))
		out.append(breath * (tone + 0.2 * rumble[i]))
	return out


def thrust():
	"""Pushing roar: band-limited noise over a mid hum with a slow turbine wobble."""
	air = looped_noise(1398_2, 0.18)
	low = looped_noise(1398_3, 0.04)
	out = []
	for i in range(COUNT):
		wobble = 0.8 * math.sin(phase(3.0, i))
		hum = 0.3 * math.sin(phase(110.0, i) + wobble) + 0.15 * math.sin(phase(220.0, i) + 2.0 * wobble)
		out.append(hum + 0.35 * air[i] + 0.3 * low[i])
	return out


def burst():
	"""Afterburner kick: a quick swell of noise and a falling tone, fading out."""
	count = int(RATE * BURST_SECONDS)
	air = looped_noise(1398_4, 0.3, count)
	out = []
	tone_phase = 0.0
	for i in range(count):
		t = i / RATE
		envelope = min(1.0, t / 0.03) * math.exp(-t * 6.0)
		tone_phase += 2.0 * math.pi * (180.0 - 90.0 * t / BURST_SECONDS) / RATE
		out.append(envelope * (0.6 * air[i] + 0.4 * math.sin(tone_phase)))
	return out


SOUNDS = {
	"engine_idle": idle,
	"engine_thrust": thrust,
	"engine_burst": burst,
}


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
	for name, make in SOUNDS.items():
		print(write(name, make()))


if __name__ == "__main__":
	main()
