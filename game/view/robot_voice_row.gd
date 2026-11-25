class_name RobotVoiceRow
extends RefCounted

## One robot type's looping voice (#1363, AUD-2): which loop it plays, how
## loud, the pitch range its speed moves through, how far it carries and how
## much quieter a wall makes it. Plain data from `robot_voices.json` (ARC-4).

## The robot type's id, as in its `data/robots/*.json`.
var id: String = ""
## The loop, a `res://` path.
var sound: String = ""
var volume_db: float = 0.0
## Pitch at rest and at the type's `max_speed`.
var pitch_min: float = 1.0
var pitch_max: float = 1.0
## Beyond this many metres the voice is not played at all.
var range_m: float = 30.0
## Added to the volume when a wall stands between robot and pilot; 0 or below.
var muffle_db: float = -12.0


## The pitch for a robot moving at `speed` m/s whose top speed is `max_speed`.
func pitch_for(speed: float, max_speed: float) -> float:
	var fraction: float = clampf(speed / max_speed, 0.0, 1.0) if max_speed > 0.0 else 0.0
	return lerpf(pitch_min, pitch_max, fraction)
