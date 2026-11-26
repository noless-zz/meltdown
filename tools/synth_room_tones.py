#!/usr/bin/env python3
"""Writes the placeholder room tones of the mine and the base into game/data/audio/ (#1399, AUD-1, NAM-3).

Six quiet beds: a tight tunnel (moving air and faint drips), a medium room
(machinery hum), a large chamber (deep rumble and distant clanks), the reactor's
low pulse that is added near it, the urgent rumble after the meltdown, and the
hangar at the home base. They play far under everything else, so they are kept
soft, with no sharp edges and nothing that stands out as the loop comes round.
Everything is synthesised here from sines and seeded noise, so it is original and
the same on every run: re-running the script rewrites identical files. Each loop
is LOOP_SECONDS long, every tone and wobble is a whole number of cycles in it, and
drips and clanks wrap round its end, so the loops repeat without a click.
Standard library only.
Usage: python3 tools/synth_room_tones.py
"""

import math
import os
import random
import struct
import wave

RATE = 22050
LOOP_SECONDS = 4.0
COUNT = int(RATE * LOOP_SECONDS)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "data", "audio")


def whole(freq):
	"""`freq` moved to the nearest whole number of cycles in the loop."""
	return max(1, round(freq * LOOP_SECONDS)) / LOOP_SECONDS


def phase(freq, i):
	return 2.0 * math.pi * whole(freq) * i / RATE


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


def strikes(seed, count, freq_low, freq_high, decay, level):
	"""`count` short decaying tones at seeded places, wrapping round the loop's end."""
	rng = random.Random(seed)
	out = [0.0] * COUNT
	length = int(RATE * 5.0 / decay)
	for _ in range(count):
		start = rng.randrange(COUNT)
		freq = rng.uniform(freq_low, freq_high)
		gain = level * rng.uniform(0.5, 1.0)
		for k in range(length):
			t = k / RATE
			envelope = min(1.0, t / 0.004) * math.exp(-t * decay)
			out[(start + k) % COUNT] += gain * envelope * math.sin(2.0 * math.pi * freq * t)
	return out


def tunnel():
	"""Tight tunnel: air moving past, slowly swelling, with a few faint drips."""
	air = looped_noise(1399_1, 0.08)
	hiss = looped_noise(1399_2, 0.35)
	drips = strikes(1399_3, 3, 900.0, 1500.0, 40.0, 0.25)
	out = []
	for i in range(COUNT):
		swell = 0.75 + 0.25 * math.sin(phase(0.25, i))
		out.append(swell * (0.7 * air[i] + 0.15 * hiss[i]) + drips[i])
	return out


def room():
	"""Medium room: a mains-like machinery hum with a slow beat, over soft air."""
	air = looped_noise(1399_4, 0.05)
	out = []
	for i in range(COUNT):
		beat = 0.85 + 0.15 * math.sin(phase(0.5, i))
		hum = 0.5 * math.sin(phase(60.0, i)) + 0.25 * math.sin(phase(120.0, i)) + 0.1 * math.sin(phase(180.5, i))
		out.append(beat * hum + 0.3 * air[i])
	return out


def chamber():
	"""Large chamber: a deep rumble with distant, dull clanks."""
	rumble = looped_noise(1399_5, 0.01)
	clanks = strikes(1399_6, 2, 140.0, 260.0, 9.0, 0.35)
	out = []
	for i in range(COUNT):
		low = 0.35 * math.sin(phase(31.0, i)) + 0.15 * math.sin(phase(46.5, i))
		out.append(0.6 * rumble[i] + low + clanks[i])
	return out


def reactor():
	"""Reactor pulse: a low throb, two beats a second, that is added over the room."""
	out = []
	for i in range(COUNT):
		beat = 0.5 + 0.5 * math.sin(phase(2.0, i))
		out.append(beat * beat * (0.7 * math.sin(phase(42.0, i)) + 0.3 * math.sin(phase(84.0, i))))
	return out


def meltdown():
	"""After the meltdown: a hard, fast-throbbing rumble with a rising groan."""
	rumble = looped_noise(1399_7, 0.03)
	grind = looped_noise(1399_8, 0.2)
	out = []
	for i in range(COUNT):
		throb = 0.6 + 0.4 * math.sin(phase(4.0, i))
		groan = 0.3 * math.sin(phase(55.0, i) + 3.0 * math.sin(phase(0.25, i)))
		out.append(throb * (0.6 * rumble[i] + 0.2 * grind[i]) + groan)
	return out


def hangar():
	"""Home base hangar: a calm ventilation hush and a faint far hum."""
	air = looped_noise(1399_9, 0.06)
	out = []
	for i in range(COUNT):
		out.append(0.6 * air[i] + 0.2 * math.sin(phase(50.0, i)) + 0.08 * math.sin(phase(100.0, i)))
	return out


SOUNDS = {
	"tone_tunnel": tunnel,
	"tone_room": room,
	"tone_chamber": chamber,
	"tone_reactor": reactor,
	"tone_meltdown": meltdown,
	"tone_hangar": hangar,
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
