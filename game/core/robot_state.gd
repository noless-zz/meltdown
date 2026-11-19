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
## Which way a strafer circles its target: +1 or -1. `Sim` sets it from the
## spawn index, so the choice is deterministic and does not change when an
## earlier robot is destroyed and the indices shift (ARC-2).
var strafe_direction: int = 1
## The weapon it fires, resolved by the caller from `def.weapon` because core
## opens no files. Null: it never fires. Robots have no energy pool.
var weapon: WeaponDef = null
## Ticks until it can fire again, as `ShipState.fire_cooldown`.
var fire_cooldown: int = 0
## False while a robot with a wake range waits for a ship; it neither moves
## nor fires until `wake_if_near` or a hit wakes it, and then stays awake (#301).
var awake: bool = true
## Ticks in a row it has had no clear line to its target, up to
## `def.lose_target_ticks()`, where it has dropped the target (#615).
var unseen_ticks: int = 0

## The chase stand-off, the strafe band and its radial gain come from `def`
## (`standoff_radii`, `strafe_min_distance`, `strafe_max_distance`,
## `strafe_radial_gain`), so tuning a robot is a data change (ARC-4, #246).
## A robot fires only at a target within this angle of its facing, degrees.
## Shots leave along the facing, so a wider cone would mostly miss.
const FIRE_CONE_HALF_ANGLE_DEG: float = 10.0


func _init(p_def: RobotDef, p_position: Vector3 = Vector3.ZERO,
		p_orientation: Basis = Basis.IDENTITY) -> void:
	def = p_def
	position = p_position
	orientation = p_orientation
	hull = p_def.hull
	awake = not p_def.has_wake_range()


## Moves one tick according to `def.movement`, towards or around `target`,
## the ship `Sim` chose for it. With no target every movement is hover and the
## robot does not turn: there is nothing to face.
func step(target: ShipState = null) -> void:
	if target == null:
		_hover()
		return
	var offset: Vector3 = target.position - position
	var distance: float = offset.length()
	# A target exactly on the centre gives no direction; keep the facing.
	var to_target: Vector3 = offset / distance if distance > 0.0 else forward()
	turn_towards(to_target)
	match def.movement:
		"chase":
			_chase(to_target, distance, chase_standoff(target))
		"strafe":
			_strafe(to_target, distance)
		_:
			_hover()


## The direction the robot faces: its local -z, as for ships.
func forward() -> Vector3:
	return -orientation.z.normalized()


## Largest turn in one tick, radians.
func max_turn_per_tick() -> float:
	return deg_to_rad(def.turn_rate) * ShipState.TICK_DT


## Distance from the target's centre a chaser holds.
func chase_standoff(target: ShipState) -> float:
	return def.standoff_radii * def.radius + target.radius


## Turns the facing towards `direction` (unit length) by at most
## `max_turn_per_tick`. The rotation is about the axis perpendicular to both,
## so the facing moves by exactly the turned angle and no roll is added.
func turn_towards(direction: Vector3) -> void:
	var facing: Vector3 = forward()
	var angle: float = StableAngle.between(facing, direction)
	if angle <= 0.0:
		return
	var axis: Vector3 = facing.cross(direction)
	if axis.length_squared() < 1e-12:
		# Exactly behind: any perpendicular axis will do; the robot's own up
		# keeps the choice deterministic.
		axis = orientation.y
	var turn: float = minf(angle, max_turn_per_tick())
	orientation = Basis(axis.normalized(), turn) * orientation
	orientation = orientation.orthonormalized()


## Closes on the target along the facing, slowing so that it can stop at
## `standoff` with its own acceleration; inside the stand-off it backs away.
## The approach is scaled by how well it faces the target, so a chaser still
## turning does not fly off sideways.
func _chase(to_target: Vector3, distance: float, standoff: float) -> void:
	var gap: float = distance - standoff
	var desired: Vector3 = Vector3.ZERO
	if gap > 0.0:
		var alignment: float = maxf(forward().dot(to_target), 0.0)
		desired = forward() * _stopping_speed(gap) * alignment
	elif gap < 0.0:
		desired = -to_target * _stopping_speed(-gap)
	_steer(desired)


## Circles the target sideways in `strafe_direction`, about the world vertical
## (or the world x axis when straight above or below it), drifting back to the
## middle of the distance band.
func _strafe(to_target: Vector3, distance: float) -> void:
	var axis: Vector3 = Vector3.UP
	if absf(to_target.dot(axis)) > 0.99:
		axis = Vector3.RIGHT
	var sideways: Vector3 = to_target.cross(axis).normalized() * float(strafe_direction)
	var middle: float = (def.strafe_min_distance + def.strafe_max_distance) * 0.5
	var radial: float = clampf((distance - middle) * def.strafe_radial_gain,
		-def.max_speed, def.max_speed)
	# Outside the band, getting back in comes first.
	if distance < def.strafe_min_distance or distance > def.strafe_max_distance:
		radial = signf(radial) * def.max_speed
	_steer((sideways * def.max_speed + to_target * radial).limit_length(def.max_speed))


## Fastest speed from which `def.acceleration` still stops within `gap`
## metres, capped at `def.max_speed`. One tick of margin keeps the discrete
## tick from overshooting.
func _stopping_speed(gap: float) -> float:
	var a: float = def.acceleration
	var speed: float = sqrt(2.0 * a * gap + a * a * ShipState.TICK_DT * ShipState.TICK_DT) \
		- a * ShipState.TICK_DT
	return minf(maxf(speed, 0.0), def.max_speed)


## Changes velocity towards `desired` by at most `def.acceleration` this tick,
## caps it at `def.max_speed` and moves.
func _steer(desired: Vector3) -> void:
	var change: Vector3 = (desired - velocity).limit_length(def.acceleration * ShipState.TICK_DT)
	velocity = (velocity + change).limit_length(def.max_speed)
	position += velocity * ShipState.TICK_DT


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


## Wakes the robot if `ship`'s centre is within `def.wake_range` of its own.
## A robot without a wake range is already awake.
func wake_if_near(ship: ShipState) -> void:
	if awake or ship == null:
		return
	if position.distance_squared_to(ship.position) <= def.wake_range * def.wake_range:
		awake = true


## Takes `amount` hull points, never below zero. Negative amounts are ignored,
## so damage can never repair. A hit wakes a sleeping robot.
func apply_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	awake = true
	hull = maxf(hull - amount, 0.0)


## Where along the segment `from`..`to` it first comes within `def.radius` of
## this robot's centre, as a fraction 0..1 of the segment, or -1.0 if it never
## does; see `Projectile.segment_entry`.
func segment_entry(from: Vector3, to: Vector3) -> float:
	return Projectile.segment_entry(from, to, position, def.radius)


## How far its shot flies before expiring, metres; 0 without a weapon.
func weapon_range() -> float:
	if weapon == null:
		return 0.0
	return weapon.projectile_speed * float(weapon.lifetime_ticks()) * ShipState.TICK_DT


## Counts the fire interval down and fires when ready, if `in_sight` (a clear
## line from its centre to the target's through open space, `LineOfSight`) and
## `target` is within `weapon_range` and within `FIRE_CONE_HALF_ANGLE_DEG` of
## the facing. Returns the weapon that fired, or null. Call once per tick, after
## `step`, as ships call `ShipState.fire_primary`.
##
## Without a line for `def.lose_target_ticks()` in a row it drops the target
## (#615); when the line clears again it aims afresh, so its next shot waits a
## full fire interval. Moving is not affected.
func fire_at(target: ShipState, in_sight: bool = true) -> WeaponDef:
	if fire_cooldown > 0:
		fire_cooldown -= 1
	if weapon == null or target == null or not is_alive():
		return null
	if not in_sight:
		unseen_ticks = mini(unseen_ticks + 1, def.lose_target_ticks())
		return null
	if unseen_ticks > 0 and unseen_ticks >= def.lose_target_ticks():
		fire_cooldown = maxi(fire_cooldown, weapon.fire_interval_ticks)
	unseen_ticks = 0
	if fire_cooldown > 0:
		return null
	var offset: Vector3 = target.position - position
	var distance: float = offset.length()
	if distance > weapon_range():
		return null
	# A target exactly on the centre is straight ahead whichever way it faces.
	var cone: float = deg_to_rad(FIRE_CONE_HALF_ANGLE_DEG)
	if distance > 0.0 and StableAngle.between(forward(), offset) > cone:
		return null
	fire_cooldown = weapon.fire_interval_ticks
	return weapon


## Tagged fields, so a value moving from one field to another changes the hash.
## The weapon joins only on an armed robot, so robots that never carried one
## keep their hashes; the awake flag likewise only with a wake range.
func state_hash() -> int:
	var parts: Array = [
		"def", def.values_hash(),
		"position", position,
		"velocity", velocity,
		"orientation", orientation,
		"hull", hull,
		"strafe_direction", strafe_direction,
	]
	if weapon != null:
		parts.append_array(["weapon", weapon.values_hash(), "fire_cooldown", fire_cooldown])
	# Only robots with a wake range carry the flag, so pinned hashes stand (#301).
	if def.has_wake_range():
		parts.append_array(["awake", awake])
	# Only while the line is lost, so robots that always see keep their hashes.
	if unseen_ticks > 0:
		parts.append_array(["unseen_ticks", unseen_ticks])
	return hash(parts)
