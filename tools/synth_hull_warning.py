#!/usr/bin/env python3
"""Writes the placeholder low-hull warning tone into game/data/audio/hull_warning.wav (#1456, AUD-1, NAM-3).

A short two-note chirp from the cockpit dash, high then a little lower, with soft edges so it
does not click when it repeats every half second or so. A faint square overtone gives it an
instrument-panel edge that cuts through gunfire without being shrill. Everything is
synthesised here from sines and a band-limited square, so it is original and the same on every
run: re-running the script rewrites an identical file. This is a script of its own, not part of
tools/synth_sounds.py, so the lanes do not edit the same file.
Standard library only.
Usage: python3 tools/synth_hull_warning.py
"""

import math
import os
import struct
import wave

RATE = 22050
NOTES = [(988.0, 0.11), (784.0, 0.13)]  # (Hz, seconds): B5 then G5.
GAP_SECONDS = 0.02
EDGE_SECONDS = 0.012
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "data", "audio")


def soft_square(phase):
	"""The first three odd harmonics of a square: an edge without aliasing."""
	return math.sin(phase) + math.sin(3.0 * phase) / 3.0 + math.sin(5.0 * phase) / 5.0


def note(freq, seconds):
	count = int(RATE * seconds)
	edge = int(RATE * EDGE_SECONDS)
	out = []
	for i in range(count):
		phase = 2.0 * math.pi * freq * i / RATE
		gain = min(1.0, i / edge, (count - 1 - i) / edge)
		decay = 1.0 - 0.35 * i / count
		out.append(gain * decay * (0.75 * math.sin(phase) + 0.25 * soft_square(phase)))
	return out


def warning():
	out = []
	for index, (freq, seconds) in enumerate(NOTES):
		if index > 0:
			out.extend([0.0] * int(RATE * GAP_SECONDS))
		out.extend(note(freq, seconds))
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
	print(write("hull_warning", warning()))


if __name__ == "__main__":
	main()
