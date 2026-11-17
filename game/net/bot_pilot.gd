class_name BotPilot
extends ShipInputSource

## Flies one ship of a `Sim` against its robots: turns to the nearest live
## robot, holds an engagement distance and fires when the robot is in range
## and in front of the nose (CMB-3, PLT-4). Used to check automatically that
## a level can be beaten (gate G2) without a person flying it.
##
## It only reads the simulation and answers with a `ShipInput`, exactly what a
## pilot's controllers would give, so the server stays the only writer of
## state (MP-2). No randomness and no clock: the same flight gives the same
## inputs (ARC-1, ARC-2). In a level it remembers only where it last stood out
## of every robot's line of fire, to fall back there.

## Distance to the target the bot tries to hold, metres. Far enough that a
## robot's shots take a moment to arrive, close enough that every shipped
## primary weapon reaches.
const ENGAGE_DISTANCE: float = 15.0
## The bot holds fire unless the target is within this angle of the nose,
## degrees. Shots leave straight ahead, so a wide cone would waste energy.
const FIRE_CONE_HALF_ANGLE_DEG: float = 5.0
## Turn rates the bot asks for at most, radians per second. Equal to the
## thumbstick mapping's limits (`ThumbstickMapping.MAX_PITCH_RATE` and
## `MAX_YAW_RATE`, tested), so the bot flies no faster than a pilot can. `net/`
## may not depend on `xr/`, so the values are repeated here.
const MAX_PITCH_RATE: float = PI / 2.0
const MAX_YAW_RATE: float = PI / 2.0
## Turn rate asked for per radian off the target, per second. Below the tick
## rate, so a turn never overshoots within one tick; this value settles a
## small error in about half a second.
const TURN_GAIN: float = 6.0
## Closing speed wanted per metre away from `ENGAGE_DISTANCE`, per second.
const CLOSING_GAIN: float = 1.0
## Thrust per metre per second of closing speed still missing: full thrust
## once the error reaches 4 m/s.
const THRUST_GAIN: float = 0.25
## Fastest the bot flies along a route through a level, metres per second.
## Well under the ship's cap, so it can stop within an opening's width at full
## thrust when it turns a corner.
const ROUTE_SPEED: float = 10.0
## Slowest the bot flies towards an opening on its way to somewhere else,
## metres per second. Without it the bot slows ever more as it nears the
## opening's centre and hangs at the corner under fire (#334). Below the
## ship's wall damage threshold, so brushing a wall past the corner is free.
const CORNER_SPEED: float = 3.0
## In a level, the bot falls back out of fire once its shield drops below
## this many points, and comes on again only with the shield full, so hull
## damage comes in short exchanges rather than one long one (#334). In the
## G2 level every robot is awake from the start, so a straight fight is lost.
const RETREAT_SHIELD: float = 20.0
## A robot out of sight that closes on the ship faster than this, metres per
## second, is waited for where the bot stands rather than met round a corner.
const CLOSING_ROBOT_SPEED: float = 0.5

var _sim: Sim = null
var _ship_index: int = 0
## Null without a level: the bot then flies straight at its target.
var _route: LevelRoute = null
## The level's walls, for the line of sight to a robot; null without a level.
var _walls: BoxUnion = null
var _goal: Vector3 = Vector3.ZERO
var _has_goal: bool = false
## Where the ship last stood with no robot able to shoot it, while routed.
var _last_safe: Vector3 = Vector3.ZERO
var _has_safe: bool = false
var _retreating: bool = false
## Firing points round an intact reactor (#375); null without a level.
var _flank: BotFlank = null


## With a `level`, the bot routes through its boxes rather than flying into
## rock (#289); without one it flies straight, as before.
func _init(sim: Sim, ship_index: int = 0, level: LevelDef = null) -> void:
	_sim = sim
	_ship_index = ship_index
	if level != null and level.error == "" and not level.union.boxes.is_empty():
		_route = LevelRoute.new(level)
		_walls = level.union
		_flank = BotFlank.new(sim, _walls, _route)


## A point to fly to and stop at once no robot is left, such as a level's exit.
func set_goal(point: Vector3) -> void:
	_goal = point
	_has_goal = true


## Reads the sim as it stands before tick `tick` and returns the input to fly.
func next_input(_tick: int) -> ShipInput:
	if _sim == null or _ship_index < 0 or _ship_index >= _sim.ships.size():
		return ShipInput.new()
	var ship: ShipState = _sim.ships[_ship_index]
	var target: RobotState = nearest_robot(ship.position)
	if _route != null:
		return _routed_input(ship, _target_in_level(ship, target))
	if target == null:
		return ShipInput.new()
	var offset: Vector3 = target.position - ship.position
	var distance: float = offset.length()
	# Ship space: x right, y up, forward is -z. The basis is orthonormal, so
	# its transpose is its inverse.
	var local: Vector3 = ship.orientation.transposed() * offset
	var turn: Vector3 = _turn_towards(local)
	var thrust: Vector3 = Vector3.ZERO
	if distance > 0.0:
		var to_target: Vector3 = offset / distance
		var closing: float = ship.velocity.dot(to_target)
		var wanted: float = (distance - ENGAGE_DISTANCE) * CLOSING_GAIN
		var push: float = clampf((wanted - closing) * THRUST_GAIN, -1.0, 1.0)
		thrust = local / distance * push
	var input: ShipInput = ShipInput.from_floats(thrust, turn)
	input.fire_primary = should_fire(ship, offset)
	return input


## Flying in a level: towards the robot, or the goal when none is left, by
## way of the next waypoint when the straight way is not clear. Thrust aims at
## the velocity wanted, not only the closing speed, so drift across the route
## is cancelled and the ship stays off the walls at corners. While the robot is
## in sight the nose stays on it and the bot fires on the way, so a robot that
## sees the ship round a corner is shot back at rather than given free shots
## (#334); thrust is in ship space, so the route is flown whichever way the
## nose points. With no robot in sight and none firing, the bot waits while
## robots close on it or its shield recharges; with its shield low under fire
## it falls back to where it last stood safe.
func _routed_input(ship: ShipState, target: RobotState) -> ShipInput:
	var threatened: bool = under_fire(ship)
	if not threatened:
		_last_safe = ship.position
		_has_safe = true
		_retreating = false
	elif _has_safe and ship.shield < RETREAT_SHIELD:
		_retreating = true
	var in_sight: bool = target != null and shot_reaches(ship, target.position)
	var flank_point: Vector3 = _flank.point_for(ship, target, in_sight)
	var flanking: bool = flank_point != Vector3.INF
	var aim: Vector3 = _goal
	var hold: float = 0.0
	if _retreating:
		aim = _last_safe
	elif flanking:
		aim = flank_point
	elif target != null:
		aim = target.position
		# Out of reach (behind the reactor, say), holding off would only
		# trade shots one way: close in until a shot gets through.
		hold = ENGAGE_DISTANCE if in_sight else 0.0
	elif not _has_goal:
		return ShipInput.new()
	var waypoint: Vector3 = _route.next_waypoint(ship.position, aim, ship.radius)
	var min_speed: float = -ROUTE_SPEED
	if waypoint != aim:
		hold = 0.0
		min_speed = CORNER_SPEED
	var offset: Vector3 = waypoint - ship.position
	var distance: float = offset.length()
	var wanted: Vector3 = Vector3.ZERO
	var waiting: bool = target != null and not in_sight and not threatened and not flanking \
		and (robots_closing(ship) or ship.shield < ship.max_shield)
	if not waiting and distance > 0.0:
		var speed: float = clampf((distance - hold) * CLOSING_GAIN, min_speed, ROUTE_SPEED)
		wanted = offset / distance * speed
	var push: Vector3 = ((wanted - ship.velocity) * THRUST_GAIN).limit_length(1.0)
	var basis_inverse: Basis = ship.orientation.transposed()
	var lead: Vector3 = lead_point(ship, target) - ship.position if in_sight else offset
	if flanking:
		# Nose on the robot, so the first tick the line opens is a shot.
		lead = target.position - ship.position
	var input: ShipInput = ShipInput.from_floats(basis_inverse * push, _turn_towards(basis_inverse * lead))
	# Only when a shot gets there: one at a robot behind rock would hit the rock.
	input.fire_primary = in_sight and should_fire(ship, lead)
	return input


## Where `target` will be when a shot fired now reaches it, if it keeps its
## velocity: the shot's flight time is taken over the present distance.
static func lead_point(ship: ShipState, target: RobotState) -> Vector3:
	var weapon: WeaponDef = ship.primary_slots[ship.selected_primary]
	if weapon == null or weapon.projectile_speed <= 0.0:
		return target.position
	var flight: float = ship.position.distance_to(target.position) / weapon.projectile_speed
	return target.position + target.velocity * flight


## Whether any live, armed robot could hit `ship` now: in its weapon's range
## with a clear line. Robots turn to their target, so facing is not counted.
## An intact reactor stops robot shots too (#345), so one behind it is no threat.
func under_fire(ship: ShipState) -> bool:
	for robot: RobotState in _sim.robots:
		if robot.is_alive() and robot.weapon != null \
				and robot.position.distance_to(ship.position) <= robot.weapon_range() \
				and (_sim.reactor == null or _sim.reactor.segment_entry(robot.position, ship.position) < 0.0) \
				and _reaches(robot.position, ship.position, robot.weapon.projectile_speed):
			return true
	return false


## Whether any live robot is closing on `ship` faster than CLOSING_ROBOT_SPEED.
func robots_closing(ship: ShipState) -> bool:
	for robot: RobotState in _sim.robots:
		if robot.is_alive() and robot.position != ship.position \
				and robot.velocity.dot((ship.position - robot.position).normalized()) > CLOSING_ROBOT_SPEED:
			return true
	return false


## In a level, the nearest robot a shot can reach, or `nearest` when none can:
## the robot that can shoot back is the one to answer first.
func _target_in_level(ship: ShipState, nearest: RobotState) -> RobotState:
	var best: RobotState = null
	var best_distance: float = INF
	for robot: RobotState in _sim.robots:
		if not robot.is_alive() or not shot_reaches(ship, robot.position):
			continue
		var d: float = ship.position.distance_squared_to(robot.position)
		if d < best_distance:
			best = robot
			best_distance = d
	return best if best != null else nearest


## Whether a shot from `ship`'s selected primary weapon, fired straight at
## `point`, would reach it inside the walls. A shot is dropped once it ends a
## tick outside every box (`ProjectileHits`), so this checks the same points:
## one per tick of flight. An intact reactor in the way takes the shot, so
## a robot behind it is out of reach too. An empty slot never reaches anything.
func shot_reaches(ship: ShipState, point: Vector3) -> bool:
	var weapon: WeaponDef = ship.primary_slots[ship.selected_primary]
	if weapon == null:
		return false
	if _sim.reactor != null and _sim.reactor.segment_entry(ship.position, point) >= 0.0:
		return false
	return _reaches(ship.position, point, weapon.projectile_speed)


## Whether a shot at `speed` from `from` straight at `point` stays inside the
## walls at the end of every tick of its flight.
func _reaches(from: Vector3, point: Vector3, speed: float) -> bool:
	return BotFlank.reaches_walls(_walls, from, point, speed)


## Turn rates that bring the nose to `local`, a direction in ship space,
## within the caps.
static func _turn_towards(local: Vector3) -> Vector3:
	# Positive pitch raises the nose and positive yaw turns it left (see
	# `ShipState.step`). Straight behind, atan2 gives a full half turn, so
	# the bot turns at its full rate rather than stalling.
	var pitch_error: float = atan2(local.y, -local.z)
	var yaw_error: float = atan2(-local.x, -local.z)
	return Vector3(
		clampf(pitch_error * TURN_GAIN, -MAX_PITCH_RATE, MAX_PITCH_RATE),
		clampf(yaw_error * TURN_GAIN, -MAX_YAW_RATE, MAX_YAW_RATE),
		0.0)


## The live robot nearest to `point`, or null when there is none. Only a
## strictly nearer robot replaces the best, so ties go to the lower index.
func nearest_robot(point: Vector3) -> RobotState:
	var best: RobotState = null
	var best_distance: float = INF
	for robot: RobotState in _sim.robots:
		if not robot.is_alive():
			continue
		var d: float = point.distance_squared_to(robot.position)
		if d < best_distance:
			best = robot
			best_distance = d
	return best


## Whether `ship` should hold fire at a target `offset` away: within its
## selected primary weapon's range and within the cone ahead of its nose. An
## empty slot has no range, so an unarmed ship never fires.
static func should_fire(ship: ShipState, offset: Vector3) -> bool:
	var weapon: WeaponDef = ship.primary_slots[ship.selected_primary]
	if weapon == null:
		return false
	var weapon_range: float = weapon.projectile_speed * float(weapon.lifetime_ticks()) \
		* ShipState.TICK_DT
	var distance: float = offset.length()
	if distance > weapon_range:
		return false
	if distance == 0.0:
		return true
	var nose: Vector3 = -ship.orientation.z.normalized()
	return nose.angle_to(offset) <= deg_to_rad(FIRE_CONE_HALF_ANGLE_DEG)
