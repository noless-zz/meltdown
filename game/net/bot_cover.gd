class_name BotCover
extends RefCounted

## Finds the bot pilot a place out of every robot's line of fire (CMB-3, #492).
##
## Generated levels wake every robot at the start, and the start often lies in
## a room several of them can see. Before this the bot fell back only to where
## it had last stood unseen, and a ship under fire from its first tick had no
## such place, so it fought the whole room at once and was often destroyed
## within seconds of the start. Now it flies to the nearest point
## no armed robot can hit, waits there for its shield and meets the robots as
## they come round the corner one by one.
##
## Candidates are the centres of the boxes a few openings away, the centres of
## those openings and points pushed towards each face of each box, in box index
## order, so the same flight gives the same choice (ARC-1, ARC-2). The nearest
## unexposed one by straight distance wins; ties go to the first found. Only
## reads the sim (MP-2).

## How many openings away from the ship cover is looked for.
const MAX_HOPS: int = 3
## Room kept between a candidate point and the walls, metres, beyond the
## ship's radius.
const WALL_CLEARANCE: float = 1.0

var _sim: Sim = null
var _walls: BoxUnion = null
var _route: LevelRoute = null
## `_neighbours[i]` lists the boxes joined to box i, as `LevelDef.neighbours`.
var _neighbours: Array = []
## The point chosen last, kept while it stays unexposed; INF when none.
var _point: Vector3 = Vector3.INF


func _init(sim: Sim, level: LevelDef, route: LevelRoute) -> void:
	_sim = sim
	_walls = level.union
	_route = route
	for index: int in _walls.boxes.size():
		_neighbours.append(level.neighbours(index))


## Where to hide from the robots now, or `Vector3.INF` when no candidate near
## enough is out of every line of fire. A point is kept while it still serves,
## so the bot does not hop between near-equal ones.
func point_for(ship: ShipState) -> Vector3:
	if _point != Vector3.INF and not exposed(_point):
		return _point
	_point = Vector3.INF
	var best_distance: float = INF
	for point: Vector3 in candidates(ship):
		var d: float = ship.position.distance_squared_to(point)
		if d < best_distance and not exposed(point):
			_point = point
			best_distance = d
	return _point


## Forgets the chosen point, so the next call looks afresh.
func reset() -> void:
	_point = Vector3.INF


## Whether any live, armed robot could hit a ship at `point`.
func exposed(point: Vector3) -> bool:
	for robot: RobotState in _sim.robots:
		if hits(_sim, _walls, robot, point):
			return true
	return false


## The nearest live, armed robot that could hit `ship` now, or null.
func threat(ship: ShipState) -> RobotState:
	var best: RobotState = null
	var best_distance: float = INF
	for robot: RobotState in _sim.robots:
		var d: float = robot.position.distance_squared_to(ship.position)
		if d < best_distance and hits(_sim, _walls, robot, ship.position):
			best = robot
			best_distance = d
	return best


## How many live, armed robots could hit `ship` now.
func threat_count(ship: ShipState) -> int:
	var count: int = 0
	for robot: RobotState in _sim.robots:
		if hits(_sim, _walls, robot, ship.position):
			count += 1
	return count


## Whether `robot` is alive, armed and could hit a ship at `point`: in its
## weapon's range, with `walls` (none: open space) and an intact reactor
## letting the shot through. Robots turn to their target, so facing is not
## counted.
static func hits(sim: Sim, walls: BoxUnion, robot: RobotState, point: Vector3) -> bool:
	if not robot.is_alive() or robot.weapon == null:
		return false
	if robot.position.distance_to(point) > robot.weapon_range():
		return false
	if sim.reactor != null and sim.reactor.segment_entry(robot.position, point) >= 0.0:
		return false
	return BotFlank.reaches_walls(walls, robot.position, point, robot.weapon.projectile_speed)


## Points to hide at within MAX_HOPS openings of the ship, each held by the
## walls with room to spare and joined to the ship by the route.
func candidates(ship: ShipState) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var room: float = ship.radius + WALL_CLEARANCE
	for index: int in _boxes_near(ship):
		var box: BoxBounds = _walls.boxes[index]
		var centre: Vector3 = (box.min_corner + box.max_corner) * 0.5
		var spots: Array[Vector3] = [centre]
		for axis: int in 3:
			for sense: float in [-1.0, 1.0]:
				var spot: Vector3 = centre
				var half: float = (box.max_corner[axis] - box.min_corner[axis]) * 0.5
				spot[axis] += sense * maxf(half - room, 0.0)
				spots.append(spot)
		for other: int in _neighbours[index]:
			if other > index:
				spots.append(LevelRoute.opening_centre(box, _walls.boxes[other]))
		for spot: Vector3 in spots:
			if _walls.holds(spot, room) and not points.has(spot):
				points.append(spot)
	var joined: Array[Vector3] = []
	for point: Vector3 in points:
		if not _route.chain(ship.position, point, ship.radius).is_empty():
			joined.append(point)
	return joined


## Box indices within MAX_HOPS openings of a box holding the ship, in the
## order a breadth-first search finds them.
func _boxes_near(ship: ShipState) -> Array[int]:
	var found: Array[int] = []
	var hops: Dictionary[int, int] = {}
	for index: int in _walls.boxes.size():
		if _walls.boxes[index].holds(ship.position, 0.0):
			found.append(index)
			hops[index] = 0
	var next: int = 0
	while next < found.size():
		var index: int = found[next]
		next += 1
		if hops[index] >= MAX_HOPS:
			continue
		for other: int in _neighbours[index]:
			if not hops.has(other) and not _route.is_closed(index, other):
				hops[other] = hops[index] + 1
				found.append(other)
	return found
