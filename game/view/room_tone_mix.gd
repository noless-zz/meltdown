class_name RoomToneMix
extends RefCounted

## The room tones' mix (#1399, AUD-1): how loud each layer of a
## `RoomToneTable` is. One bed plays at a time, the space the ship is in, the
## meltdown rumble once the reactor is gone, or the hangar at the base, and
## a change of bed crossfades over the table's `fade_seconds`, the old one
## going out as the new one comes in, so none jumps. Near the reactor, before
## the meltdown, a low pulse is added over the bed by the ship's distance.
##
## Pure arithmetic on what it is handed: it reads no session and no clock of
## its own, so the same moods, places and seconds give the same mix (tests,
## the acceptance check), and the simulation never hears it (ARC-1, MP-2).

var table: RoomToneTable = null
## Gain of each layer, 0..1, by layer id.
var gains: Dictionary[String, float] = {}
## The bed heading for full; empty while everything fades out.
var bed: String = ""


func _init(tone_table: RoomToneTable) -> void:
	table = tone_table
	for id: String in table.layer_ids():
		gains[id] = 0.0


## Moves the mix `seconds` on for the ship at `position` in `walls`, in
## `mood`, with `reactor` a session copy or null (a level without one). Where
## no box holds the ship the bed it had is kept. Returns the layers sounding.
func follow(mood: MusicMix.Mood, walls: BoxUnion, position: Vector3, reactor: ReactorState,
		seconds: float) -> Array[String]:
	var pulse: float = 0.0
	match mood:
		MusicMix.Mood.HUB:
			bed = RoomToneTable.HANGAR
		MusicMix.Mood.MELTDOWN:
			bed = RoomToneTable.MELTDOWN
		MusicMix.Mood.RUN:
			var space: String = table.space_at(walls, position)
			if space != "":
				bed = space
			elif not table.space_ids.has(bed):
				bed = ""
			if reactor != null and not reactor.destroyed:
				pulse = table.reactor_share(position.distance_to(reactor.position()))
		_:
			bed = ""
	advance(bed, pulse, seconds)
	return sounding()


## Moves every layer `seconds` towards its target: the `target_bed` to full,
## the other beds to silence, the reactor pulse to `pulse` (0..1).
func advance(target_bed: String, pulse: float, seconds: float) -> void:
	var step: float = maxf(0.0, seconds) / table.fade_seconds
	for id: String in gains:
		var want: float = pulse if id == RoomToneTable.REACTOR else (1.0 if id == target_bed else 0.0)
		gains[id] = move_toward(gains[id], clampf(want, 0.0, 1.0), step)


## The level of layer `id` now, dB; -INF while it is silent.
func db(id: String) -> float:
	var gain: float = gains.get(id, 0.0)
	if gain <= 0.0:
		return -INF
	return table.volumes[id] + linear_to_db(gain)


## The layers with any gain, in the table's order.
func sounding() -> Array[String]:
	var heard: Array[String] = []
	for id: String in gains:
		if gains[id] > 0.0:
			heard.append(id)
	return heard


## Silences every layer at once, for a new level: its first space fades in.
func reset() -> void:
	bed = ""
	for id: String in gains:
		gains[id] = 0.0
