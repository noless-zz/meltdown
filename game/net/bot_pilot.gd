class_name BotPilot
extends ShipInputSource

## Flies one ship of a `Sim` against its robots: turns to the nearest live
## robot, holds an engagement distance and fires when the robot is in range
## and in front of the nose (CMB-3, PLT-4). Used to check automatically that
## a level can be beaten (gate G2) without a person flying it. In a level it
## also picks the robot cheapest to aim at, weaves across the line of fire and
## falls back to cover when outnumbered (#492; `BotAim`, `BotDodge`, `BotCover`,
## `BotFallback`).
##
## It only reads the simulation and answers with a `ShipInput`, exactly what a
## pilot's controllers would give, so the server stays the only writer of
## state (MP-2). No randomness and no clock: the same flight gives the same
## inputs (ARC-1, ARC-2).

## Distance to the target the bot tries to hold, metres. Far enough that a
## robot's shots take a moment to arrive, close enough that every shipped
## primary weapon reaches.
const ENGAGE_DISTANCE: float = 15.0
## Aiming lives in `BotAim` (#492); the names stay here for callers.
const FIRE_CONE_HALF_ANGLE_DEG: float = BotAim.FIRE_CONE_HALF_ANGLE_DEG
const MAX_PITCH_RATE: float = BotAim.MAX_PITCH_RATE
const MAX_YAW_RATE: float = BotAim.MAX_YAW_RATE
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
## Falling back and waiting live in `BotFallback` (#1135); the names stay here for callers.
const RETREAT_SHIELD: float = BotFallback.RETREAT_SHIELD
const OUTNUMBERED: int = BotFallback.OUTNUMBERED
const CLOSING_ROBOT_SPEED: float = BotFallback.CLOSING_ROBOT_SPEED
const MAX_WAIT_TICKS: int = BotFallback.MAX_WAIT_TICKS

var _sim: Sim = null
var _ship_index: int = 0
## Null without a level: the bot then flies straight at its target.
var _route: LevelRoute = null
## The level's walls, for the line of sight to a robot; null without a level.
var _walls: BoxUnion = null
var _goal: Vector3 = Vector3.ZERO
var _has_goal: bool = false
## Firing points round an intact reactor (#375); null without a level.
var _flank: BotFlank = null
## Reactor and exit steps (#360); null without a level.
var _escape: BotEscape = null
## Weaving across the line of fire (#492); null without a level.
var _dodge: BotDodge = null
## Places out of every robot's line of fire (#492); null without a level.
var _cover: BotCover = null
## Falling back and waiting (#1135); null without a level.
var _fallback: BotFallback = null
## Stalled (#658), the bot neither weaves nor turns to the robot; null without a level.
var _stall: BotStall = null
## A miner to hold at before the reactor (#1084); null unless a recording sets one.
var _rescue: BotRescue = null


## With a `level`, the bot routes through its boxes rather than flying into
## rock (#289); without one it flies straight, as before.
func _init(sim: Sim, ship_index: int = 0, level: LevelDef = null) -> void:
	_sim = sim
	_ship_index = ship_index
	if level != null and level.error == "" and not level.union.boxes.is_empty():
		_route = LevelRoute.new(level)
		_walls = level.union
		_flank = BotFlank.new(sim, _walls, _route)
		_escape = BotEscape.new(sim, ship_index, _walls, _route)
		_dodge = BotDodge.new(_walls)
		_cover = BotCover.new(sim, level, _route)
		_fallback = BotFallback.new(sim, _cover)
		_stall = BotStall.new()


## A point to fly to and stop at once no robot is left, such as a level's exit.
func set_goal(point: Vector3) -> void:
	_goal = point
	_has_goal = true


## Before the reactor, hold at `miner` (millimetres, from `MinerRescue.trapped`)
## until it is rescued (#1084, `BotRescue`). Needs a level; without one it is ignored.
func set_rescue_goal(miner: Vector3i) -> void:
	_rescue = BotRescue.new(_sim, _route, miner) if _route != null else null


## Reads the sim as it stands before tick `tick` and returns the input to fly.
func next_input(_tick: int) -> ShipInput:
	if _sim == null or _ship_index < 0 or _ship_index >= _sim.ships.size():
		return ShipInput.new()
	var ship: ShipState = _sim.ships[_ship_index]
	# A destroyed ship takes no input (#601); sending none keeps replays of a
	# lost run honest about what the pilot could still do.
	if ship.is_destroyed():
		return ShipInput.new()
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
	var turn: Vector3 = turn_towards(local)
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
## nose points. When it waits or falls back instead is `BotFallback`'s call.
func _routed_input(ship: ShipState, target: RobotState) -> ShipInput:
	var shooter: RobotState = _cover.threat(ship)
	var threatened: bool = shooter != null
	_fallback.update(ship, threatened)
	var in_sight: bool = target != null and shot_reaches(ship, target.position)
	if _escape.takes_over(self, ship):
		if _rescue != null and not _sim.reactor.destroyed and _rescue.active():
			return _rescue.next_input(ship)
		return _escape.next_input(ship, target, in_sight)
	var flank_point: Vector3 = _flank.point_for(ship, target, in_sight)
	var flanking: bool = flank_point != Vector3.INF
	var aim: Vector3 = _goal
	var hold: float = 0.0
	var shelter: Vector3 = _fallback.shelter(ship)
	if shelter != Vector3.INF:
		aim = shelter
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
	var stalled: bool = _stall.update(ship.position)
	var waiting: bool = _fallback.waits(ship, target != null, in_sight, threatened, flanking, stalled)
	if not waiting and distance > 0.0:
		var speed: float = clampf((distance - hold) * CLOSING_GAIN, min_speed, ROUTE_SPEED)
		wanted = offset / distance * speed
	if threatened and not stalled:
		wanted += _dodge.velocity(ship, shooter.position)
	else:
		_dodge.reset()
	var push: Vector3 = ((wanted - ship.velocity) * THRUST_GAIN).limit_length(1.0)
	var basis_inverse: Basis = ship.orientation.transposed()
	var lead: Vector3 = lead_point(ship, target) - ship.position if in_sight else offset
	if flanking:
		# Nose on the robot, so the first tick the line opens is a shot.
		lead = target.position - ship.position
	var turn: Vector3 = turn_towards(basis_inverse * lead)
	if in_sight and not flanking and not stalled:
		turn = BotAim.track(ship, target)
	var input: ShipInput = ShipInput.from_floats(basis_inverse * push, turn)
	# Only when a shot gets there: one at a robot behind rock would hit the rock.
	input.fire_primary = in_sight and should_fire(ship, lead)
	return input


static func lead_point(ship: ShipState, target: RobotState) -> Vector3:
	return BotAim.lead_point(ship, target)


## Whether any live, armed robot could hit `ship` now (`BotFallback.under_fire`).
func under_fire(ship: ShipState) -> bool:
	return BotFallback.under_fire(_sim, _walls, ship)


## Whether any live robot is closing on `ship` faster than CLOSING_ROBOT_SPEED.
func robots_closing(ship: ShipState) -> bool:
	return BotFallback.robots_closing(_sim, ship)


## In a level, of the robots a shot can reach the one `BotAim.cost` rates
## cheapest, or `nearest` when none can: a robot that can shoot back is the one
## to answer first.
func _target_in_level(ship: ShipState, nearest: RobotState) -> RobotState:
	var best: RobotState = null
	var best_cost: float = INF
	for robot: RobotState in _sim.robots:
		if not robot.is_alive() or not shot_reaches(ship, robot.position):
			continue
		var cost: float = BotAim.cost(ship, robot)
		if cost < best_cost:
			best = robot
			best_cost = cost
	return best if best != null else nearest


## Whether a shot from `ship`'s selected primary weapon, fired straight at
## `point`, would reach it inside the walls: a shot ends where it leaves open
## space (`ProjectileHits`, `LineOfSight`), so this checks the same line. An
## intact reactor in the way takes the shot, so a robot behind it is out of
## reach too. An empty slot never reaches anything.
func shot_reaches(ship: ShipState, point: Vector3) -> bool:
	var weapon: WeaponDef = ship.primary_slots[ship.selected_primary]
	if weapon == null:
		return false
	if _sim.reactor != null and _sim.reactor.segment_entry(ship.position, point) >= 0.0:
		return false
	return BotFlank.reaches_walls(_walls, ship.position, point, weapon.projectile_speed)


static func turn_towards(local: Vector3) -> Vector3:
	return BotAim.turn_towards(local)


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


static func should_fire(ship: ShipState, offset: Vector3) -> bool:
	return BotAim.should_fire(ship, offset)
