class_name SoundCueHit
extends RefCounted

## A cue due to play (#1290): its name in the cue table and where, in the
## simulation's space. `SoundCueEvents` makes these; `SoundCues` plays them.

var cue: String = ""
var position: Vector3 = Vector3.ZERO
## The event's `magnitude`, 0 for cues read from the bolts.
var magnitude: float = 0.0


func _init(p_cue: String = "", p_position: Vector3 = Vector3.ZERO, p_magnitude: float = 0.0) -> void:
	cue = p_cue
	position = p_position
	magnitude = p_magnitude


func _to_string() -> String:
	return "%s@%s" % [cue, position]
