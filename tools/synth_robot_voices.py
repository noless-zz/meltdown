#!/usr/bin/env python3
"""Writes the placeholder robot voice loops into game/data/audio/ (#1363, AUD-2, NAM-3).

One looping voice per robot type, each built from a different recipe so a pilot can
tell them apart with eyes closed: a light hovering hum, an airy glide, a heavy
grinding engine, a thin fast whine with chatter, a warbling skim and a deep slow
throb. Everything is synthesised here from sines, squares, saws and seeded noise,
so it is original and the same on every run: re-running the script rewrites
identical files. Each loop is LOOP_SECONDS long and every tone and pulse is a whole
number of cycles in it, so the loops repeat without a click. Standard library only.
Usage: python3 tools/synth_robot_voices.py
"""

import math
import os
import random
import struct
import wave

RATE = 22050
LOOP_SECONDS = 2.0
COUNT = int(RATE * LOOP_SECONDS)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "data", "audio")


def whole(freq):
	"""`freq` moved to the nearest whole number of cycles in the loop."""
	return max(1, round(freq * LOOP_SECONDS)) / LOOP_SECONDS


def phase(freq, i):
	return 2.0 * math.pi * whole(freq) * i / RATE


def square(p):
	return 1.0 if math.sin(p) >= 0.0 else -1.0


def saw(p):
	return (p / math.pi) % 2.0 - 1.0


def looped_noise(seed, smooth):
	"""Seeded noise, low-passed around the loop twice so its end meets its start."""
	rng = random.Random(seed)
	raw = [rng.uniform(-1.0, 1.0) for _ in range(COUNT)]
	out = [0.0] * COUNT
	level = 0.0
	for _ in range(2):
		for i in range(COUNT):
			level += smooth * (raw[i] - level)
			out[i] = level
	peak = max(abs(v) for v in out) or 1.0
	return [v / peak for v in out]


def drone():
	"""Light hovering hum: a mid sine pair with a quick flutter."""
	out = []
	for i in range(COUNT):
		flutter = 0.75 + 0.25 * math.sin(phase(12.0, i))
		out.append(flutter * (0.6 * math.sin(phase(220.0, i)) + 0.3 * math.sin(phase(330.0, i))))
	return out


def glider():
	"""Airy glide: breathy noise with a soft high whistle that swells twice a loop."""
	air = looped_noise(1363_2, 0.25)
	out = []
	for i in range(COUNT):
		swell = 0.6 + 0.4 * math.sin(phase(1.0, i))
		out.append(swell * (0.55 * air[i] + 0.3 * math.sin(phase(880.0, i))))
	return out


def hauler():
	"""Heavy grinding engine: a low square and saw, with a clank four times a loop."""
	out = []
	for i in range(COUNT):
		t = (i / RATE) % 0.5
		clank = math.exp(-t * 30.0) * math.sin(phase(410.0, i))
		out.append(0.35 * square(phase(55.0, i)) + 0.3 * saw(phase(82.5, i)) + 0.35 * clank)
	return out


def needler():
	"""Thin fast whine with a chattering on-off pulse."""
	out = []
	for i in range(COUNT):
		chatter = 1.0 if math.sin(phase(18.0, i)) > -0.2 else 0.15
		whine = math.sin(phase(1320.0, i) + 0.8 * math.sin(phase(66.0, i)))
		out.append(chatter * (0.5 * whine + 0.2 * square(phase(660.0, i))))
	return out


def skimmer():
	"""Warbling skim: a mid saw whose pitch wobbles, over a low hum."""
	out = []
	for i in range(COUNT):
		wobble = 6.0 * math.sin(phase(4.0, i))
		out.append(0.35 * saw(phase(440.0, i) + wobble) + 0.35 * math.sin(phase(110.0, i)))
	return out


def warden():
	"""Deep slow throb: a very low sine and square, pulsing once a second."""
	out = []
	for i in range(COUNT):
		throb = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(phase(1.0, i))) ** 2
		out.append(throb * (0.6 * math.sin(phase(40.0, i)) + 0.25 * square(phase(80.0, i))))
	return out


VOICES = {
	"voice_drone": drone,
	"voice_glider": glider,
	"voice_hauler": hauler,
	"voice_needler": needler,
	"voice_skimmer": skimmer,
	"voice_warden": warden,
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
	for name, make in VOICES.items():
		print(write(name, make()))


if __name__ == "__main__":
	main()
