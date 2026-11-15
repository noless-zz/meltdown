class_name ShipInput
extends RefCounted

## One ship's input for one simulation tick.
##
## Inputs are stored as integers in thousandths rather than floats. A replay
## file and a network packet then carry exactly the numbers the simulation
## used, so replaying them cannot drift by a rounding error in text or on
## another device (ARC-2).

const SCALE: int = 1000

## Ship-space thrust in thousandths: each axis -1000..1000 (x strafe, y lift,
## z forward is negative).
var thrust_q: Vector3i = Vector3i.ZERO
## Pitch, yaw and roll rate in milliradians per second.
var turn_q: Vector3i = Vector3i.ZERO
## Afterburner held. A bool is already exact, so it needs no scaling.
var afterburner: bool = false
## Put this ship back at its start pose, at rest, before this tick's thrust.
## A development and solo-play aid for a pilot who has left the mine (#81);
## whether co-op allows it is decided in M5.
var reset_to_start: bool = false


func _init(
		p_thrust_q: Vector3i = Vector3i.ZERO,
		p_turn_q: Vector3i = Vector3i.ZERO,
		p_afterburner: bool = false,
		p_reset_to_start: bool = false) -> void:
	thrust_q = p_thrust_q
	turn_q = p_turn_q
	afterburner = p_afterburner
	reset_to_start = p_reset_to_start


## Rounds analogue values (thrust -1..1 per axis, turn in radians per second)
## to the stored precision. Callers must simulate with the returned input, not
## with the original floats, or a recording will not match what was flown.
static func from_floats(thrust: Vector3, turn: Vector3, p_afterburner: bool = false) -> ShipInput:
	return ShipInput.new(
		Vector3i((thrust * SCALE).round()), Vector3i((turn * SCALE).round()), p_afterburner)


func thrust() -> Vector3:
	return Vector3(thrust_q) / float(SCALE)


func turn() -> Vector3:
	return Vector3(turn_q) / float(SCALE)
