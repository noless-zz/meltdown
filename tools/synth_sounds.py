#!/usr/bin/env python3
"""Writes the placeholder sound cues into game/data/audio/ (#1290, AUD-1, NAM-3).

Every sound is synthesised here from sine, square and seeded noise, so it is
original and the same on every run: re-running the script rewrites identical
files. Standard library only. Usage: python3 tools/synth_sounds.py
"""

import math
import os
import random
import struct
import wave

RATE = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "data", "audio")


def envelope(t, length, attack=0.004, curve=4.0):
	if t < attack:
		return t / attack
	return math.exp(-curve * (t - attack) / max(length - attack, 1e-6))


def render(length, voice, seed=1):
	rng = random.Random(seed)
	samples = []
	phase = 0.0
	for i in range(int(length * RATE)):
		t = i / RATE
		value, freq = voice(t, length, rng)
		phase += 2.0 * math.pi * freq / RATE
		samples.append(value(phase) if callable(value) else value)
	peak = max(1e-6, max(abs(s) for s in samples))
	return [s / peak * 0.85 for s in samples]


def write(name, samples):
	path = os.path.join(OUT, name + ".wav")
	with wave.open(path, "wb") as out:
		out.setnchannels(1)
		out.setsampwidth(2)
		out.setframerate(RATE)
		out.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples))


def zap(f_start, f_end, length, shape="sine", noise=0.0, curve=5.0, seed=1):
	def voice(t, total, rng):
		freq = f_start * (f_end / f_start) ** (t / total)
		env = envelope(t, total, curve=curve)
		grain = rng.uniform(-1.0, 1.0) * noise

		def value(phase):
			if shape == "square":
				tone = 1.0 if math.sin(phase) >= 0.0 else -1.0
			elif shape == "saw":
				tone = (phase / math.pi) % 2.0 - 1.0
			else:
				tone = math.sin(phase)
			return env * (tone * (1.0 - noise) + grain)
		return value, freq
	return render(length, voice, seed)


def thud(f, length, noise, curve, seed):
	return zap(f, f * 0.5, length, "sine", noise, curve, seed)


def chime(notes, step, length):
	out = [0.0] * int(length * RATE)
	for index, freq in enumerate(notes):
		start = int(index * step * RATE)
		for i in range(start, len(out)):
			t = (i - start) / RATE
			out[i] += math.sin(2.0 * math.pi * freq * t) * envelope(t, length - index * step, curve=5.0)
	peak = max(abs(s) for s in out)
	return [s / peak * 0.85 for s in out]


def main():
	os.makedirs(OUT, exist_ok=True)
	sounds = {
		"shot_pulse_cannon": zap(1400, 380, 0.16),
		"shot_slug_thrower": thud(260, 0.22, 0.55, 7.0, 2),
		"shot_quill_battery": zap(2600, 1500, 0.08, "square", 0.1),
		"shot_drift_mortar": thud(140, 0.35, 0.35, 5.0, 3),
		"shot_hollow_spike": zap(900, 2200, 0.14, "saw"),
		"shot_needle_gun": zap(3200, 2400, 0.06, "sine", 0.15),
		"shot_ember_coil": zap(600, 300, 0.24, "saw", 0.4, 4.0, 4),
		"shot_arc_lance": zap(1800, 900, 0.2, "square", 0.3, 3.0, 5),
		"shot_robot": zap(700, 260, 0.18, "square", 0.2, 5.0, 6),
		"bolt_impact": thud(500, 0.12, 0.8, 9.0, 7),
		"robot_hit": zap(420, 300, 0.14, "square", 0.5, 7.0, 8),
		"robot_destroyed": thud(180, 0.7, 0.75, 3.5, 9),
		"ship_hit": thud(120, 0.3, 0.6, 6.0, 10),
		"wall_impact": thud(80, 0.25, 0.7, 8.0, 11),
		"pickup": chime([660, 880, 1320], 0.06, 0.35),
		"part_slotted": chime([440, 660], 0.05, 0.25),
		"meltdown_start": zap(110, 70, 1.4, "saw", 0.3, 1.5, 12),
		"ship_escaped": chime([523, 659, 784, 1047], 0.09, 0.8),
		"ship_destroyed": thud(90, 1.2, 0.85, 2.5, 13),
	}
	for name, samples in sounds.items():
		write(name, samples)


if __name__ == "__main__":
	main()
