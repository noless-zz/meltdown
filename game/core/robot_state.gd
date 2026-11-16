class_name RobotState
extends RefCounted

## One live robot, owned by `Sim` and advanced on the fixed tick (CMB-3).
## Plain data in world space: no node, so the server simulates it and the view
## draws it from the same state (MP-2). Its type's numbers come from `def`, a
## data file, so a new robot type needs no new code (ARC-4).

var def: RobotDef = null
var position: Vector3 = Vector3.ZERO
## Metres per second.
var velocity: Vector3 = Vector3.ZERO
var orientation: Basis = Basis.IDENTITY
## Hull points left; starts at `def.hull`.
var hull: float = 0.0


func _init(p_def: RobotDef, p_position: Vector3 = Vector3.ZERO,
		p_orientation: Basis = Basis.IDENTITY) -> void:
	def = p_def
	position = p_position
	orientation = p_orientation
	hull = p_def.hull


## Moves one tick according to `def.movement`. Every movement is treated as
## hover until chase and strafe get their own issue.
func step() -> void:
	_hover()


## Holds position: any velocity is braked towards zero at `def.acceleration`,
## never past it, and capped at `def.max_speed`.
func _hover() -> void:
	var brake: float = def.acceleration * ShipState.TICK_DT
	var speed: float = velocity.length()
	if speed <= brake:
		velocity = Vector3.ZERO
	else:
		velocity = velocity * ((speed - brake) / speed)
	velocity = velocity.limit_length(def.max_speed)
	position += velocity * ShipState.TICK_DT


## Keeps the robot's sphere inside `bounds`. Robots do not bounce or take wall
## damage like ships: on each axis where it crossed a wall it is placed back on
## the wall and its velocity into that wall is removed. A box narrower than the
## robot holds it on the centre line, as `BoxBounds.contain_impact` does ships.
func keep_inside(bounds: BoxBounds) -> void:
	for axis: int in 3:
		var low: float = bounds.min_corner[axis] + def.radius
		var high: float = bounds.max_corner[axis] - def.radius
		if low > high:
			low = (bounds.min_corner[axis] + bounds.max_corner[axis]) * 0.5
			high = low
		if position[axis] < low:
			position[axis] = low
			velocity[axis] = maxf(velocity[axis], 0.0)
		elif position[axis] > high:
			position[axis] = high
			velocity[axis] = minf(velocity[axis], 0.0)


## Tagged fields, so a value moving from one field to another changes the hash.
func state_hash() -> int:
	return hash([
		"def", def.values_hash(),
		"position", position,
		"velocity", velocity,
		"orientation", orientation,
		"hull", hull,
	])
