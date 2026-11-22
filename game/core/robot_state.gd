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
## Shots left in the burst under way; 0 between bursts (#612).
var burst_shots_left: int = 0
## Ticks spent winding up for the next burst's first shot; 0 when not.
var windup_elapsed: int = 0

## The chase stand-off, the strafe band and its radial gain come from `def`
## (`standoff_radii`, `strafe_min_distance`, `strafe_max_distance`,
## `strafe_radial_gain`), so tuning a robot is a data change (ARC-4, #246);
## `RobotSteering` applies them.
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


## Moves one tick according to `def.movement`, towards or around `target`;
## the movement itself lives in `RobotSteering` (#1155).
func step(target: ShipState = null) -> void:
	RobotSteering.step(self, target)


## The direction the robot faces: its local -z, as for ships.
func forward() -> Vector3:
	return -orientation.z.normalized()


## Largest turn in one tick, radians.
func max_turn_per_tick() -> float:
	return RobotSteering.max_turn_per_tick(self)


## Distance from the target's centre a chaser holds.
func chase_standoff(target: ShipState) -> float:
	return RobotSteering.chase_standoff(self, target)


## Turns the facing towards `direction` (unit length) by at most
## `max_turn_per_tick`.
func turn_towards(direction: Vector3) -> void:
	RobotSteering.turn_towards(self, direction)


## Keeps the robot's sphere inside `bounds`; see `RobotSteering.keep_inside`.
func keep_inside(bounds: BoxBounds) -> void:
	RobotSteering.keep_inside(self, bounds)


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
## Shots come in bursts (#612): a burst's first shot follows
## `weapon.windup_ticks` ticks in which it could fire (any tick it could not
## starts the wind-up over), and its last is followed by
## `weapon.burst_cooldown_ticks()`. Moving is not affected. Without a line for
## `def.lose_target_ticks()` in a row it drops the target (#615); when the line
## clears it aims afresh: a full fire interval, then a new burst.
func fire_at(target: ShipState, in_sight: bool = true) -> WeaponDef:
	if fire_cooldown > 0:
		fire_cooldown -= 1
	if weapon == null or target == null or not is_alive():
		windup_elapsed = 0
		return null
	if not in_sight:
		unseen_ticks = mini(unseen_ticks + 1, def.lose_target_ticks())
		windup_elapsed = 0
		return null
	if unseen_ticks > 0 and unseen_ticks >= def.lose_target_ticks():
		fire_cooldown = maxi(fire_cooldown, weapon.fire_interval_ticks)
		burst_shots_left = 0
	unseen_ticks = 0
	if fire_cooldown > 0 or not _can_hit(target):
		windup_elapsed = 0
		return null
	if burst_shots_left == 0 and windup_elapsed < weapon.windup_ticks:
		windup_elapsed += 1
		return null
	windup_elapsed = 0
	if burst_shots_left == 0:
		burst_shots_left = weapon.burst_shots
	burst_shots_left -= 1
	fire_cooldown = weapon.fire_interval_ticks if burst_shots_left > 0 \
		else weapon.burst_cooldown_ticks()
	return weapon


## True while it winds up for a burst, so the view can show it coming (#604).
func is_winding_up() -> bool:
	return windup_elapsed > 0


## True when `target` is within `weapon_range` and the fire cone.
func _can_hit(target: ShipState) -> bool:
	var offset: Vector3 = target.position - position
	var distance: float = offset.length()
	if distance > weapon_range():
		return false
	# A target exactly on the centre is straight ahead whichever way it faces.
	var cone: float = deg_to_rad(FIRE_CONE_HALF_ANGLE_DEG)
	return distance <= 0.0 or StableAngle.between(forward(), offset) <= cone


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
	# Only for weapons that fire in bursts, so other robots keep their hashes.
	if weapon != null and weapon.has_bursts():
		parts.append_array(["burst_shots_left", burst_shots_left, "windup_elapsed", windup_elapsed])
	return hash(parts)
