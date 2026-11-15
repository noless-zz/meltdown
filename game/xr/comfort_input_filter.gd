class_name ComfortInputFilter
extends RefCounted

## Applies one player's comfort preset to that player's turn input before it
## is sent to the simulation (CMF-1, CMF-3, ARC-3).
##
## Snap turning is a one-tick turn of the ship rather than a jump of the view:
## the view then only ever moves with the ship's simulated motion (CMF-8), and
## the core sees an ordinary input it treats like every other player's
## (CMF-6). Thrust and the afterburner always pass through unchanged, so a
## preset never alters speed.
##
## A snap axis fires once when its rate passes half the mapping's full rate,
## then stays at zero until the rate falls below a quarter of it. The gap
## between the two thresholds keeps a stick held near the trigger point from
## firing a burst of snaps.

## Fraction of full rate that fires a snap.
const SNAP_FIRE_FRACTION: float = 0.5
## Fraction of full rate the stick must fall below before the next snap.
const SNAP_REARM_FRACTION: float = 0.25

var preset: ComfortPreset
## Per snap axis: true while the stick has been released since the last snap.
var _pitch_armed: bool = true
var _yaw_armed: bool = true


func _init(p_preset: ComfortPreset) -> void:
	preset = p_preset


## Turn rate in milliradians per second that turns exactly `snap_angle_deg`
## in one simulation tick, as stored in `ShipInput.turn_q`.
func snap_rate_q() -> int:
	return roundi(deg_to_rad(preset.snap_angle_deg) / ShipState.TICK_DT * ShipInput.SCALE)


## Returns the input to simulate for this tick. Call once per tick, in order:
## the filter remembers whether each snap axis has been released.
func filter(input: ShipInput) -> ShipInput:
	var turn: Vector3i = input.turn_q
	if preset.pitch_mode == ComfortPreset.PitchMode.SNAP:
		var pitch: Array = _snap(turn.x, ThumbstickMapping.MAX_PITCH_RATE, _pitch_armed)
		turn.x = int(pitch[0])
		_pitch_armed = bool(pitch[1])
	if preset.yaw_mode == ComfortPreset.YawMode.SNAP:
		var yaw: Array = _snap(turn.y, ThumbstickMapping.MAX_YAW_RATE, _yaw_armed)
		turn.y = int(yaw[0])
		_yaw_armed = bool(yaw[1])
	if preset.roll_mode == ComfortPreset.RollMode.OFF_AUTO_LEVEL:
		turn.z = 0
	return ShipInput.new(input.thrust_q, turn, input.afterburner)


## Returns [filtered rate in milliradians per second, armed after this tick].
func _snap(rate_q: int, full_rate: float, armed: bool) -> Array:
	var magnitude: float = absf(float(rate_q)) / ShipInput.SCALE
	if armed and magnitude > full_rate * SNAP_FIRE_FRACTION:
		return [snap_rate_q() * signi(rate_q), false]
	if not armed and magnitude < full_rate * SNAP_REARM_FRACTION:
		return [0, true]
	return [0, armed]
