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


## True until the hull reaches zero; `Sim` removes the robot at the end of
## that tick.
func is_alive() -> bool:
	return hull > 0.0


## Takes `amount` hull points, never below zero. Negative amounts are ignored,
## so damage can never repair.
func apply_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	hull = maxf(hull - amount, 0.0)


## Where along the segment `from`..`to` it first comes within `def.radius` of
## this robot's centre, as a fraction 0..1 of the segment, or -1.0 if it never
## does. A segment rather than a point, because a shot moves further in one
## tick than a small robot is wide. A segment starting inside enters at 0.
func segment_entry(from: Vector3, to: Vector3) -> float:
	var offset: Vector3 = from - position
	var outside: float = offset.dot(offset) - def.radius * def.radius
	if outside <= 0.0:
		return 0.0
	var path: Vector3 = to - from
	var a: float = path.dot(path)
	if a == 0.0:
		return -1.0
	var b: float = offset.dot(path)
	var discriminant: float = b * b - a * outside
	if discriminant < 0.0:
		return -1.0
	# The nearer root. With the start outside, both roots share a sign, so a
	# negative one means the sphere lies behind the shot.
	var t: float = (-b - sqrt(discriminant)) / a
	if t < 0.0 or t > 1.0:
		return -1.0
	return t


## Tagged fields, so a value moving from one field to another changes the hash.
func state_hash() -> int:
	return hash([
		"def", def.values_hash(),
		"position", position,
		"velocity", velocity,
		"orientation", orientation,
		"hull", hull,
	])
