class_name ShipInput
extends RefCounted

## One ship's input for one simulation tick.
##
## Inputs are stored as integers in thousandths rather than floats. A replay
## file and a network packet then carry exactly the numbers the simulation
## used, so replaying them cannot drift by a rounding error in text or on
## another device (ARC-2).

const SCALE: int = 1000
## Straight ahead along the nose, ship space -z.
const NOSE_AIM_Q: Vector3i = Vector3i(0, 0, -SCALE)

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
## Primary fire held: the ship fires its selected primary weapon whenever its
## fire interval and energy allow (CMB-1).
var fire_primary: bool = false
## Slot the part in the hold into a primary weapon slot on this tick (SLV-1).
## Set by the cockpit's hand gesture; `PartSlotting` decides what it does.
var slot_held: bool = false
## Where the pilot asks the guns to point, in ship space, as a direction in
## thousandths (CMB-6, decision record 0010). The core keeps the guns inside
## the look-aim cone and turns them at its gimbal rate (`LookAim`). Defaults to
## the nose, which replays and network packets leave out, so every run recorded
## before look-aim reads back unchanged.
var aim_q: Vector3i = NOSE_AIM_Q


func _init(
		p_thrust_q: Vector3i = Vector3i.ZERO,
		p_turn_q: Vector3i = Vector3i.ZERO,
		p_afterburner: bool = false,
		p_reset_to_start: bool = false,
		p_fire_primary: bool = false,
		p_slot_held: bool = false) -> void:
	thrust_q = p_thrust_q
	turn_q = p_turn_q
	afterburner = p_afterburner
	reset_to_start = p_reset_to_start
	fire_primary = p_fire_primary
	slot_held = p_slot_held


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


## The aim as a unit direction in ship space; a zero aim is the nose.
func aim() -> Vector3:
	if aim_q == Vector3i.ZERO or aim_q == NOSE_AIM_Q:
		return LookAim.NOSE
	return Vector3(aim_q).normalized()


## Whether the aim is anywhere but the nose, so it must be carried.
func aims_off_nose() -> bool:
	return aim_q != NOSE_AIM_Q


## Rounds a ship-space aim direction of any non-zero length to the stored
## precision, as a unit vector in thousandths. A zero direction is the nose.
static func aim_q_from(direction: Vector3) -> Vector3i:
	if direction.is_zero_approx():
		return NOSE_AIM_Q
	return Vector3i((direction.normalized() * SCALE).round())


## Whether `value` can be an aim: every axis within -SCALE..SCALE and not zero.
static func aim_q_valid(value: Vector3i) -> bool:
	if value == Vector3i.ZERO:
		return false
	for axis: int in 3:
		if absi(value[axis]) > SCALE:
			return false
	return true
