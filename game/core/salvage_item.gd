class_name SalvageItem
extends RefCounted

## A part floating in the mine, dropped by a destroyed robot (SLV-1). Plain
## data owned by `Sim`, like a projectile, so the server simulates it and the
## view draws it from the same state (MP-2). The part is named by id only;
## resolving it to a weapon file is left to whoever picks it up, since core
## opens no files.

## Fraction of its speed an item loses per second. High enough that a part
## thrown off a fast robot settles within a few seconds, so the player can
## find it where the robot died.
const DAMPING_PER_SECOND: float = 2.0
## Below this speed, in metres per second, an item is put at rest, so it
## stops exactly instead of creeping forever.
const REST_SPEED: float = 0.01
## Size of the item's sphere for keeping it off the walls, in metres.
const RADIUS: float = 0.3

## The part's id: the destroyed robot's `RobotDef.salvage`.
var part_id: String = ""
var position: Vector3 = Vector3.ZERO
## Metres per second.
var velocity: Vector3 = Vector3.ZERO
## Index of the ship that dropped this part by slotting another, which may not
## take it back until its centre has left pickup range (`SalvagePickup`); -1
## for none. Part of the hash only while set, so earlier replays keep theirs.
var ignored_ship: int = -1


func _init(p_part_id: String = "", p_position: Vector3 = Vector3.ZERO,
		p_velocity: Vector3 = Vector3.ZERO) -> void:
	part_id = p_part_id
	position = p_position
	velocity = p_velocity


## The item `robot` leaves where it died, moving as it was, or null if its
## type carries no salvage.
static func dropped_by(robot: RobotState) -> SalvageItem:
	if robot.def.salvage.is_empty():
		return null
	return SalvageItem.new(robot.def.salvage, robot.position, robot.velocity)


## Moves one tick, slows towards rest and, with `bounds`, stays inside the
## walls the way robots do: placed back on a crossed wall with its velocity
## into that wall removed, never bouncing.
func advance(bounds: BoxBounds = null) -> void:
	position += velocity * ShipState.TICK_DT
	velocity *= maxf(1.0 - DAMPING_PER_SECOND * ShipState.TICK_DT, 0.0)
	if velocity.length() < REST_SPEED:
		velocity = Vector3.ZERO
	keep_inside(bounds)


## Holds the item inside `bounds` as `RobotState.keep_inside` does: clamped to
## the walls, any velocity into a wall dropped. Nothing happens for null, so
## `Sim` can pass the box a `BoxUnion` picks after the move.
func keep_inside(bounds: BoxBounds) -> void:
	if bounds == null:
		return
	for axis: int in 3:
		var low: float = bounds.min_corner[axis] + RADIUS
		var high: float = bounds.max_corner[axis] - RADIUS
		if low > high:
			low = (bounds.min_corner[axis] + bounds.max_corner[axis]) * 0.5
			high = low
		if position[axis] < low:
			position[axis] = low
			velocity[axis] = maxf(velocity[axis], 0.0)
		elif position[axis] > high:
			position[axis] = high
			velocity[axis] = minf(velocity[axis], 0.0)


func is_at_rest() -> bool:
	return velocity == Vector3.ZERO


func state_hash() -> int:
	if ignored_ship < 0:
		return hash([part_id, position, velocity])
	return hash([part_id, position, velocity, "ignored_ship", ignored_ship])
