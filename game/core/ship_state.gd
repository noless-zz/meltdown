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


## Advances one tick.
## `thrust` is in ship space, each axis in -1..1 (x strafe, y lift, z forward
## is negative, matching Godot's camera convention).
## `turn` is pitch, yaw and roll rate in radians per second.
func step(thrust: Vector3, turn: Vector3) -> void:
	if turn != Vector3.ZERO:
		orientation = orientation.rotated(orientation.x.normalized(), turn.x * TICK_DT)
		orientation = orientation.rotated(orientation.y.normalized(), turn.y * TICK_DT)
		orientation = orientation.rotated(orientation.z.normalized(), turn.z * TICK_DT)
		orientation = orientation.orthonormalized()
	var wish: Vector3 = orientation * thrust.limit_length(1.0)
	velocity += wish * acceleration * TICK_DT
	velocity -= velocity * minf(damping * TICK_DT, 1.0)
	velocity = velocity.limit_length(max_speed)
	position += velocity * TICK_DT


## Hash of the full state, used by replay tests and network desync checks.
func state_hash() -> int:
	return hash([position, velocity, orientation])
