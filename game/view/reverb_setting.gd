class_name ReverbSetting
extends RefCounted

## One reverb setting for the effects bus (#1291, AUD-1): the three values of
## `AudioEffectReverb` the room changes. Each is 0..1, as the effect takes them.

var room_size: float = 0.0
var damping: float = 0.0
var wet: float = 0.0


func _init(p_room_size: float = 0.0, p_damping: float = 0.0, p_wet: float = 0.0) -> void:
	room_size = p_room_size
	damping = p_damping
	wet = p_wet


## The setting `weight` of the way from this one to `other` (0 is this, 1 is `other`).
func lerp_to(other: ReverbSetting, weight: float) -> ReverbSetting:
	return ReverbSetting.new(lerpf(room_size, other.room_size, weight),
		lerpf(damping, other.damping, weight), lerpf(wet, other.wet, weight))


## Whether `other` holds the same three values, to float precision.
func same_as(other: ReverbSetting) -> bool:
	return other != null and is_equal_approx(room_size, other.room_size) \
		and is_equal_approx(damping, other.damping) and is_equal_approx(wet, other.wet)


## The largest difference between this and `other` over the three values.
func distance_to(other: ReverbSetting) -> float:
	return maxf(absf(room_size - other.room_size),
		maxf(absf(damping - other.damping), absf(wet - other.wet)))


## Puts the three values on `effect`.
func apply_to(effect: AudioEffectReverb) -> void:
	effect.room_size = room_size
	effect.damping = damping
	effect.wet = wet


func _to_string() -> String:
	return "(room_size %.3f, damping %.3f, wet %.3f)" % [room_size, damping, wet]
