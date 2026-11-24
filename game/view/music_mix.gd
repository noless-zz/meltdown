class_name MusicMix
extends RefCounted

## The music's mix (#1303, AUD-3): how loud each layer of a `MusicTable` is,
## from the mood of the moment and the alarm level. Every change is a fade
## over the table's time, never a cut: layers join and leave over
## `crossfade_seconds`, the meltdown track takes over within
## `meltdown_seconds`, and an end screen fades everything out over
## `end_fade_seconds` (CMF-8).
##
## Pure arithmetic on what it is handed: it reads no session and no clock of
## its own, so the same moods and seconds give the same mix (tests, the
## acceptance check), and the simulation never hears it (ARC-1, MP-2).

enum Mood {
	## Nothing plays: before the first frame, or with no table.
	SILENT,
	## A level is flown: the calm layer, and the tension layers by the alarm.
	RUN,
	## The reactor is gone and the countdown runs (RUN-2).
	MELTDOWN,
	## The escape or destroyed screen is up: everything fades out.
	ENDED,
	## The home base between runs.
	HUB,
}

var table: MusicTable = null
## Gain of each layer, 0..1, by layer id.
var gains: Dictionary[String, float] = {}
var mood: Mood = Mood.SILENT


func _init(music_table: MusicTable) -> void:
	table = music_table
	for layer: MusicLayer in table.layers:
		gains[layer.id] = 0.0


## The gain, 0 or 1, each layer is headed for in `p_mood` at `alarm` (0..1).
func targets(p_mood: Mood, alarm: float) -> Dictionary[String, float]:
	var wanted: Dictionary[String, float] = {}
	for layer: MusicLayer in table.layers:
		var on: bool = false
		match p_mood:
			Mood.RUN:
				on = layer.plays == MusicLayer.RUN and alarm >= layer.from_alarm
			Mood.MELTDOWN:
				on = layer.plays == MusicLayer.MELTDOWN
			Mood.HUB:
				on = layer.plays == MusicLayer.HUB
		wanted[layer.id] = 1.0 if on else 0.0
	return wanted


## The seconds a full fade takes in `p_mood`.
func fade_seconds(p_mood: Mood) -> float:
	match p_mood:
		Mood.MELTDOWN:
			return table.meltdown_seconds
		Mood.ENDED:
			return table.end_fade_seconds
	return table.crossfade_seconds


## Moves every layer `seconds` on towards its target in `p_mood` at `alarm`,
## at the mood's fade rate, and returns the gains.
func advance(p_mood: Mood, alarm: float, seconds: float) -> Dictionary[String, float]:
	mood = p_mood
	var wanted: Dictionary[String, float] = targets(p_mood, alarm)
	var step: float = maxf(0.0, seconds) / fade_seconds(p_mood)
	for id: String in gains:
		gains[id] = move_toward(gains[id], wanted[id], step)
	return gains


## The ids of the layers sounding now (gain above 0), in table order.
func sounding() -> Array[String]:
	var ids: Array[String] = []
	for layer: MusicLayer in table.layers:
		if gains[layer.id] > 0.0:
			ids.append(layer.id)
	return ids


## The volume a layer at `gain` plays at: the music's volume, the layer's,
## and the gain in decibels; -80 (silent) at gain 0.
func volume_db(layer: MusicLayer, gain: float) -> float:
	if gain <= 0.0:
		return -80.0
	return maxf(-80.0, table.volume_db + layer.volume_db + linear_to_db(gain))


## Forgets the mix: every layer silent, as before the first frame.
func reset() -> void:
	mood = Mood.SILENT
	for id: String in gains:
		gains[id] = 0.0
