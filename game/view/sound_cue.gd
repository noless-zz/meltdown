class_name SoundCue
extends RefCounted

## One row of the sound cue table (#1290, AUD-1): which sound a cue plays, how
## loud, and the range its pitch is picked from so repeats do not sound
## identical. Plain data read from `res://data/audio/cues.json` (ARC-4).

## The cue's name in the table: a `SimEvent.Kind` name, `SHOT_FIRED`,
## `SHOT_FIRED:<weapon id>` or `BOLT_IMPACT`.
var id: String = ""
## The sound file, a `res://` path.
var sound: String = ""
var volume_db: float = 0.0
var pitch_min: float = 1.0
var pitch_max: float = 1.0
## Events smaller than this (`SimEvent.magnitude`) stay silent: a ship sliding
## along a wall reports a tiny impact every tick, which should not rattle.
var min_magnitude: float = 0.0


## Whether an event of size `magnitude` sounds this cue.
func sounds_at(magnitude: float) -> bool:
	return magnitude >= min_magnitude


## The pitch for a play, `roll` (0..1) of the way through the range. The roll
## comes from the view's own generator, never the simulation's (ARC-1).
func pitch(roll: float) -> float:
	return lerpf(pitch_min, pitch_max, clampf(roll, 0.0, 1.0))
