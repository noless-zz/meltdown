class_name BotFlank
extends RefCounted

## Finds the bot pilot a firing point round an intact reactor (CMB-3, RUN-2,
## #375). Since #345 a live reactor stops shots both ways, so a robot sitting
## behind it on the tunnel's axis can neither be hit nor hit back. The bot
## then flies to a point off that line, inside the walls, from which a shot
## reaches the robot, and fires from there.
##
## Candidates are points at fixed distances from the robot in a fixed list of
## directions, so the same flight gives the same choice (ARC-1, ARC-2). Of
## those the walls hold with the ship's radius to spare, that the route joins
## to the ship and from which a shot clears the walls and the reactor, the one
## nearest the ship wins; ties go to the lowest index. Only reads the sim.

## Distances from the robot to try, metres, nearest the bot's engagement
## distance first.
const DISTANCES: Array[float] = [15.0, 10.0, 20.0, 7.0]
## Extra room kept between a firing line and the reactor's surface, metres,
## so that the ship's drift and the robot's movement do not put the reactor
## back in the way at once.
const REACTOR_CLEARANCE: float = 1.0
## Extra room kept between a firing point and the walls, metres, beyond the
## ship's radius.
const WALL_CLEARANCE: float = 1.0

var _sim: Sim = null
var _walls: BoxUnion = null
var _route: LevelRoute = null
## Every direction with components -1, 0 or 1, normalised, in a fixed order.
var _directions: Array[Vector3] = []
## The robot being flanked and the point chosen for it; INF when none.
var _target: RobotState = null
var _point: Vector3 = Vector3.INF


func _init(sim: Sim, walls: BoxUnion, route: LevelRoute) -> void:
	_sim = sim
	_walls = walls
	_route = route
	for x: int in [0, 1, -1]:
		for y: int in [0, 1, -1]:
			for z: int in [0, 1, -1]:
				if x != 0 or y != 0 or z != 0:
					_directions.append(Vector3(x, y, z).normalized())


## Where to fly instead of at `target`, or `Vector3.INF` to go on as usual:
## the robot is out of sight only because an intact reactor is in the way, or
## the bot is already on its way to a firing point for it. A point is kept
## while it still serves, so the bot does not hop between near-equal ones.
func point_for(ship: ShipState, target: RobotState, in_sight: bool) -> Vector3:
	var weapon: WeaponDef = ship.primary_slots[ship.selected_primary]
	if target == null or in_sight or weapon == null or _sim.reactor == null \
			or _sim.reactor.destroyed:
		_target = null
		return Vector3.INF
	var speed: float = weapon.projectile_speed
	var blocked: bool = reactor_blocks(ship.position, target.position, speed)
	if target != _target:
		_target = null
		if not blocked:
			return Vector3.INF
		_target = target
		_point = firing_point(ship, target.position, speed, weapon_range(weapon))
	elif blocked and not good_point(ship, _point, target.position, speed):
		_point = firing_point(ship, target.position, speed, weapon_range(weapon))
	return _point


static func weapon_range(weapon: WeaponDef) -> float:
	return weapon.projectile_speed * float(weapon.lifetime_ticks()) * ShipState.TICK_DT


## Whether the shot line from `from` to `point` is blocked by an intact
## reactor and by nothing else: the walls let it through, so the bot is close
## enough that moving aside will open a line.
func reactor_blocks(from: Vector3, point: Vector3, speed: float) -> bool:
	if _sim.reactor == null or _sim.reactor.segment_entry(from, point) < 0.0:
		return false
	return reaches_walls(_walls, from, point, speed)


## The firing point nearest `ship` from which a shot at `speed` and range
## `weapon_range` reaches `target`, clear of the reactor; `Vector3.INF` when
## no candidate qualifies.
func firing_point(ship: ShipState, target: Vector3, speed: float, weapon_range: float) -> Vector3:
	var best: Vector3 = Vector3.INF
	var best_distance: float = INF
	for distance: float in DISTANCES:
		if distance > weapon_range:
			continue
		for direction: Vector3 in _directions:
			var point: Vector3 = target + direction * distance
			var d: float = ship.position.distance_squared_to(point)
			if d < best_distance and good_point(ship, point, target, speed):
				best = point
				best_distance = d
	return best


## Whether the bot can stand at `point` and hit `target` from there.
func good_point(ship: ShipState, point: Vector3, target: Vector3, speed: float) -> bool:
	if point == Vector3.INF:
		return false
	if not _walls.holds(point, ship.radius + WALL_CLEARANCE):
		return false
	if not line_clears_reactor(point, target):
		return false
	if not reaches_walls(_walls, point, target, speed):
		return false
	return not _route.chain(ship.position, point, ship.radius).is_empty()


## Whether the segment keeps REACTOR_CLEARANCE off an intact reactor.
func line_clears_reactor(from: Vector3, to: Vector3) -> bool:
	var reactor: ReactorState = _sim.reactor
	if reactor == null or reactor.destroyed:
		return true
	return Projectile.segment_entry(from, to, reactor.position(),
		reactor.radius() + REACTOR_CLEARANCE) < 0.0


## Whether a shot from `from` straight at `point` stays in open space all the
## way, as `ProjectileHits` ends it where it leaves (`LineOfSight`, #615); the
## same line decides whether a robot sees and fires. The shot's `speed` no
## longer matters: a wall stops it wherever a tick ends. Without walls
## everything is reached.
static func reaches_walls(walls: BoxUnion, from: Vector3, point: Vector3, _speed: float) -> bool:
	return LineOfSight.clear(walls, from, point)
