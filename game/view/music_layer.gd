class_name MusicLayer
extends RefCounted

## One row of the music table (#1303, AUD-3): a looping sound and when it
## plays. A `run` layer plays during a level once the alarm reaches its
## `from_alarm` (the calm layer from 0); a `meltdown` layer takes over while
## the reactor is gone; a `hub` layer plays at the home base.

const RUN: String = "run"
const MELTDOWN: String = "meltdown"
const HUB: String = "hub"
const PLAYS: Array[String] = [RUN, MELTDOWN, HUB]

var id: String = ""
var plays: String = RUN
## Alarm level, 0..1, from which a `run` layer joins; unused by the others.
var from_alarm: float = 0.0
var sound: String = ""
## The layer's own level, added to the table's music volume.
var volume_db: float = 0.0


func _init(p_id: String = "", p_plays: String = RUN, p_from_alarm: float = 0.0,
		p_sound: String = "", p_volume_db: float = 0.0) -> void:
	id = p_id
	plays = p_plays
	from_alarm = p_from_alarm
	sound = p_sound
	volume_db = p_volume_db


## The layer in `row`, or null when a field is missing or out of range.
static func parse(row: Variant) -> MusicLayer:
	if not row is Dictionary:
		return null
	var data: Dictionary = row
	if not data.get("id") is String or str(data["id"]).is_empty():
		return null
	if not PLAYS.has(str(data.get("plays", ""))):
		return null
	if not data.get("sound") is String or not str(data["sound"]).begins_with("res://"):
		return null
	var from_alarm: Variant = data.get("from_alarm", 0.0)
	if not (from_alarm is float or from_alarm is int) or float(from_alarm) < 0.0 or float(from_alarm) > 1.0:
		return null
	var volume: Variant = data.get("volume_db", 0.0)
	if not (volume is float or volume is int):
		return null
	return MusicLayer.new(str(data["id"]), str(data["plays"]), float(from_alarm), str(data["sound"]),
		float(volume))
