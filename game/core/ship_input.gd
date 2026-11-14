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


func _init(p_thrust_q: Vector3i = Vector3i.ZERO, p_turn_q: Vector3i = Vector3i.ZERO) -> void:
	thrust_q = p_thrust_q
	turn_q = p_turn_q


## Rounds analogue values (thrust -1..1 per axis, turn in radians per second)
## to the stored precision. Callers must simulate with the returned input, not
## with the original floats, or a recording will not match what was flown.
static func from_floats(thrust: Vector3, turn: Vector3) -> ShipInput:
	return ShipInput.new(Vector3i((thrust * SCALE).round()), Vector3i((turn * SCALE).round()))


func thrust() -> Vector3:
	return Vector3(thrust_q) / float(SCALE)


func turn() -> Vector3:
	return Vector3(turn_q) / float(SCALE)
