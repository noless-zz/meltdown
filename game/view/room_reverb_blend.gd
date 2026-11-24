class_name RoomReverbBlend
extends RefCounted

## Blends the reverb from the room it was in to the room it is in (#1291,
## AUD-1) over `blend_seconds`, so passing a connector opens the echo up
## rather than switching it. Time is the simulation's, counted in ticks, so a
## paused game holds the blend and the same flight blends the same way.

var blend_seconds: float = 0.8
## What is heard now; null before the first `advance`.
var current: ReverbSetting = null
var _from: ReverbSetting = null
var _to: ReverbSetting = null
var _progress: float = 1.0


func _init(p_blend_seconds: float = 0.8) -> void:
	blend_seconds = p_blend_seconds


## Moves `seconds` on towards `target` and returns what is heard. The first
## target, or the first after `reset`, is heard at once: a level starts in its
## room. A null target (no box holds the ship) keeps the blend going as it was.
func advance(target: ReverbSetting, seconds: float) -> ReverbSetting:
	if current == null:
		if target == null:
			return null
		current = target
		_from = target
		_to = target
		_progress = 1.0
		return current
	if target != null and not target.same_as(_to):
		_from = current
		_to = target
		_progress = 0.0
	if _progress < 1.0:
		_progress = 1.0 if blend_seconds <= 0.0 else minf(1.0, _progress + seconds / blend_seconds)
		current = _from.lerp_to(_to, _progress)
	return current


## Forgets what was heard, for a new level.
func reset() -> void:
	current = null
	_from = null
	_to = null
	_progress = 1.0
