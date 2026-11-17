class_name BotEscape
extends RefCounted

## The bot pilot's last two steps in a level with a reactor (RUN-2, RUN-3,
## DEV-6, #360): once no live robot is in reach it routes to the reactor and
## shoots it down, and once the reactor is destroyed it races back to its
## start position, the exit, before the meltdown countdown runs out.
##
## Kept apart from `BotPilot`, which is at its size limit. Only reads the sim
## and answers with a `ShipInput`, as a pilot's controllers would (MP-2). No
## randomness and no clock, so the same flight gives the same inputs (ARC-1,
## ARC-2). Without a reactor it never takes over, so earlier flights keep
## their hashes.
##
## On the way out the route treats openings that solid meltdown debris blocks
## as closed (RUN-4, #443), and is planned again each time another entry turns
## solid. Before the reactor dies, and on levels without debris, nothing changes.

## Fastest the bot asks for on the way out, metres per second: the
## afterburner's cap with the shipped tuning. The ship's own cap applies.
const ESCAPE_SPEED: float = 35.0
## Deceleration the bot plans with before a corner, metres per second squared.
## Well under the ship's thrust plus damping, so it slows in time even with
## the afterburner locked out.
const BRAKING: float = 15.0
## Thrust per metre per second of velocity still missing on the way out: full
## thrust once the error reaches 1 m/s.
const ESCAPE_THRUST_GAIN: float = 1.0
## The afterburner is held only while the ship is this much slower than the
## speed wanted along the route, metres per second, so it is not spent on
## braking or holding speed.
const BOOST_MARGIN: float = 2.0

var _sim: Sim = null
var _ship_index: int = 0
var _walls: BoxUnion = null
var _route: LevelRoute = null
## Solid debris entries the route was last planned around.
var _solid_seen: int = 0


func _init(sim: Sim, ship_index: int, walls: BoxUnion, route: LevelRoute) -> void:
	_sim = sim
	_ship_index = ship_index
	_walls = walls
	_route = route


## Whether the escape steps fly the ship now instead of the fight: the level
## has a reactor, and it is destroyed or no live robot is in reach. A robot is
## in reach when a shot gets to it or the route joins the ship to it, so a
## robot the bot can still hunt is hunted first.
func takes_over(pilot: BotPilot, ship: ShipState) -> bool:
	var reactor: ReactorState = _sim.reactor
	if reactor == null:
		return false
	if reactor.destroyed:
		return true
	for robot: RobotState in _sim.robots:
		if robot.is_alive() and (pilot.shot_reaches(ship, robot.position) \
				or not _route.chain(ship.position, robot.position, ship.radius).is_empty()):
			return false
	return true


## The input for this tick once `takes_over` is true. `target` is the robot
## the pilot would answer and `in_sight` whether a shot reaches it.
func next_input(ship: ShipState, target: RobotState, in_sight: bool) -> ShipInput:
	if ship.escaped or ship.hull <= 0.0:
		return ShipInput.new()
	if _sim.reactor.destroyed:
		_plan_around_debris(ship)
		return _escape_input(ship, target, in_sight)
	return _reactor_input(ship)


## Routes towards the reactor, holds the engagement distance once a shot gets
## to it and fires only then, with the nose on its centre.
func _reactor_input(ship: ShipState) -> ShipInput:
	var centre: Vector3 = _sim.reactor.position()
	var reaches: bool = reactor_shot_reaches(ship)
	var waypoint: Vector3 = _route.next_waypoint(ship.position, centre, ship.radius)
	var hold: float = BotPilot.ENGAGE_DISTANCE if reaches and waypoint == centre else 0.0
	var min_speed: float = -BotPilot.ROUTE_SPEED if waypoint == centre else BotPilot.CORNER_SPEED
	var offset: Vector3 = waypoint - ship.position
	var distance: float = offset.length()
	var wanted: Vector3 = Vector3.ZERO
	if distance > 0.0:
		var speed: float = clampf((distance - hold) * BotPilot.CLOSING_GAIN, min_speed,
			BotPilot.ROUTE_SPEED)
		wanted = offset / distance * speed
	var push: Vector3 = ((wanted - ship.velocity) * BotPilot.THRUST_GAIN).limit_length(1.0)
	var basis_inverse: Basis = ship.orientation.transposed()
	var look: Vector3 = centre - ship.position if reaches else offset
	var input: ShipInput = ShipInput.from_floats(basis_inverse * push,
		BotPilot.turn_towards(basis_inverse * look))
	input.fire_primary = reaches and BotPilot.should_fire(ship, look)
	return input


## Races along the route to the exit: full thrust, the afterburner while the
## ship is short of the speed wanted and energy allows (the sim locks it out
## when the pool runs dry), braking before each corner. A robot in sight gets
## the nose and a shot when in the cone; thrust is in ship space, so that
## never slows the run.
func _escape_input(ship: ShipState, target: RobotState, in_sight: bool) -> ShipInput:
	var exit: Vector3 = exit_point()
	var waypoint: Vector3 = _route.next_waypoint(ship.position, exit, ship.radius)
	var offset: Vector3 = waypoint - ship.position
	var distance: float = offset.length()
	var wanted: Vector3 = Vector3.ZERO
	var speed: float = ESCAPE_SPEED
	if distance > 0.0:
		if waypoint != exit:
			# Slow enough at the opening to turn without striking the wall.
			speed = minf(ESCAPE_SPEED, BotPilot.CORNER_SPEED + sqrt(2.0 * BRAKING * distance))
		wanted = offset / distance * speed
	var push: Vector3 = ((wanted - ship.velocity) * ESCAPE_THRUST_GAIN).limit_length(1.0)
	var along: float = ship.velocity.dot(offset / distance) if distance > 0.0 else 0.0
	var basis_inverse: Basis = ship.orientation.transposed()
	var look: Vector3 = offset
	if in_sight:
		look = BotPilot.lead_point(ship, target) - ship.position
	var input: ShipInput = ShipInput.from_floats(basis_inverse * push,
		BotPilot.turn_towards(basis_inverse * look), along < speed - BOOST_MARGIN)
	input.fire_primary = in_sight and BotPilot.should_fire(ship, look)
	return input


## Plans the route again around the debris once more entries are solid than
## last time. Held entries never turn solid, so they leave the route open.
func _plan_around_debris(ship: ShipState) -> void:
	var debris: MeltdownDebris = _sim.debris
	if debris == null:
		return
	var solid: int = 0
	for index: int in debris.size():
		if debris.is_solid(index):
			solid += 1
	if solid > _solid_seen:
		_solid_seen = solid
		_route.close_blocked(debris, ship.radius)


## The exit: this ship's start position (`ExitRule`).
func exit_point() -> Vector3:
	return _sim.start_positions[_ship_index]


## Whether a shot from `ship`'s selected primary weapon, fired at the intact
## reactor's centre, gets to its surface inside the walls. Like
## `BotPilot.shot_reaches`, but the reactor is the target, not an obstacle.
func reactor_shot_reaches(ship: ShipState) -> bool:
	var weapon: WeaponDef = ship.primary_slots[ship.selected_primary]
	var reactor: ReactorState = _sim.reactor
	if weapon == null or reactor == null or reactor.destroyed:
		return false
	var centre: Vector3 = reactor.position()
	var entry: float = reactor.segment_entry(ship.position, centre)
	if entry < 0.0:
		return false
	var surface: Vector3 = ship.position.lerp(centre, entry)
	return BotFlank.reaches_walls(_walls, ship.position, surface, weapon.projectile_speed)
