class_name ShipState
extends RefCounted

## Deterministic state of one ship, advanced on the fixed simulation tick.
##
## No nodes, no input devices, no wall-clock time: the same sequence of
## inputs always produces the same state (ARC-1, ARC-2). Presentation and
## comfort code read this state and never write it (ARC-3).

const TICK_RATE: int = 60
const TICK_DT: float = 1.0 / TICK_RATE

var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var orientation: Basis = Basis.IDENTITY

var max_speed: float = 20.0
var acceleration: float = 40.0
var damping: float = 2.0

## Afterburner (FLT-2). Energy is in abstract units; rates are per second and
## applied per tick. With these values a full pool lasts four seconds of boost
## and refills from empty in eight.
var max_energy: float = 100.0
var energy: float = 100.0
var afterburner_max_speed: float = 35.0
var afterburner_acceleration: float = 80.0
var afterburner_drain: float = 25.0
var energy_recharge: float = 12.5
## Once the pool runs dry the afterburner stays off until energy is back at
## this level. Without it, a held button would flick the boost on and off
## every tick as each tick's recharge was spent at once.
var afterburner_restart_energy: float = 25.0
## True from the tick the pool ran dry until it reaches the restart level.
var afterburner_locked: bool = false


## Advances one tick.
## `thrust` is in ship space, each axis in -1..1 (x strafe, y lift, z forward
## is negative, matching Godot's camera convention).
## `turn` is pitch, yaw and roll rate in radians per second.
## `afterburner` is whether the afterburner is held this tick.
func step(thrust: Vector3, turn: Vector3, afterburner: bool = false) -> void:
	if turn != Vector3.ZERO:
		orientation = orientation.rotated(orientation.x.normalized(), turn.x * TICK_DT)
		orientation = orientation.rotated(orientation.y.normalized(), turn.y * TICK_DT)
		orientation = orientation.rotated(orientation.z.normalized(), turn.z * TICK_DT)
		orientation = orientation.orthonormalized()
	var boosting: bool = _update_energy(afterburner)
	var speed_before: float = velocity.length()
	var wish: Vector3 = orientation * thrust.limit_length(1.0)
	velocity += wish * (afterburner_acceleration if boosting else acceleration) * TICK_DT
	velocity -= velocity * minf(damping * TICK_DT, 1.0)
	# After a boost the ship may be above the normal cap. Clamping straight to
	# it would stop the ship hard in one tick; instead the speed may not grow
	# and damping brings it back down over the next second or so.
	var cap: float = afterburner_max_speed if boosting else maxf(max_speed, speed_before)
	velocity = velocity.limit_length(cap)
	position += velocity * TICK_DT


## Drains or recharges the pool for this tick and returns whether the
## afterburner is active on it.
func _update_energy(held: bool) -> bool:
	if afterburner_locked and energy >= afterburner_restart_energy:
		afterburner_locked = false
	var boosting: bool = held and not afterburner_locked and energy > 0.0
	if boosting:
		energy = maxf(energy - afterburner_drain * TICK_DT, 0.0)
		if energy <= 0.0:
			afterburner_locked = true
	else:
		energy = minf(energy + energy_recharge * TICK_DT, max_energy)
	return boosting


## Hash of the full state, used by replay tests and network desync checks.
func state_hash() -> int:
	return hash([position, velocity, orientation, energy, afterburner_locked])
