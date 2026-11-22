class_name Projectile
extends RefCounted

## One live projectile, owned by `Sim` and advanced on the fixed tick (CMB-1).
## Plain data in world space: no node, so the server can simulate it and the
## view can draw it from the same state (MP-2).

var position: Vector3 = Vector3.ZERO
## Metres per second.
var velocity: Vector3 = Vector3.ZERO
## Who fired it. Zero or more: the index in `Sim.ships` of the ship that
## fired it. Negative: a robot fired it, as `-1 - robot_index` (the robot's
## index in `Sim.robots` when it fired). A mark in the existing field rather
## than a new one, so projectiles of runs recorded before robots fired keep
## their hashes (ARC-2).
var owner_index: int = 0
## Ticks it still flies; it is removed when this reaches zero.
var ticks_left: int = 0
## Damage it deals to what it hits.
var damage: float = 0.0
## The primary slot of the ship's gun that fired it (0 is slot 1, the right
## gun); 0 for a robot's shot. Both slots fire together (#1261), and the view
## draws each slot's bolts from its own gun. Not hashed: it changes nothing a
## shot does, and the position, velocity and damage are hashed already.
var slot: int = 0


func _init(p_position: Vector3 = Vector3.ZERO, p_velocity: Vector3 = Vector3.ZERO,
		p_owner_index: int = 0, p_ticks_left: int = 0, p_damage: float = 0.0) -> void:
	position = p_position
	velocity = p_velocity
	owner_index = p_owner_index
	ticks_left = p_ticks_left
	damage = p_damage


## Moves one tick and counts it off. Returns false once its lifetime is over.
func advance() -> bool:
	position += velocity * ShipState.TICK_DT
	ticks_left -= 1
	return ticks_left > 0


## The `owner_index` of a shot fired by robot `robot_index`.
static func robot_owner(robot_index: int) -> int:
	return -1 - robot_index


## True for a shot a robot fired: it can hit ships and never robots. Ship shots
## hit robots and never ships, their own included.
func is_robot_owned() -> bool:
	return owner_index < 0


## Where the segment `from`..`to` first comes within `radius` of `centre`, as a
## fraction 0..1 of the segment, or -1.0 if it never does. A segment rather
## than a point, because a shot moves further in one tick than a small target
## is wide. A segment starting inside enters at 0. Shared by robot and ship
## targets so both are hit by the same rule.
static func segment_entry(from: Vector3, to: Vector3, centre: Vector3, radius: float) -> float:
	var offset: Vector3 = from - centre
	var outside: float = offset.dot(offset) - radius * radius
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


func state_hash() -> int:
	return hash([position, velocity, owner_index, ticks_left, damage])
