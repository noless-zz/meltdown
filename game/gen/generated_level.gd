class_name GeneratedLevel
extends RefCounted

## Turns a `MineGenerator`'s output into a `LevelDef` the game can fly (#317,
## #356, #378): its boxes, the start `MineGenerator.START_INSET_MM` inside the
## oldest open connector facing in, with a `ReactorPlan` a reactor, and with a
## `RobotPlan` robots (none without one).
##
## The reactor goes to the module furthest from the first module in joins:
## each placement is one join further than its parent, and parents are always
## placed earlier, so one pass in placement order is the breadth-first walk
## over the placement parents. Ties go to the later placement. It sits at the
## centre of that module's largest box (ties to the lower box), so an L-shaped
## module still holds it; it is left out, with `MineGenerator.reactor_note`
## set, when the furthest module is fewer than `min_hops` joins away or that
## box cannot hold the reactor with a ship's diameter clear on every side.
## Positions are whole millimetres from the placements, so the same seed puts
## the reactor in the same place on every device (GEN-2, ARC-2).
##
## With a `RobotPlan` (#378) robots follow the reactor: a count from the plan's
## range, each of a type from the plan, in a box of a module other than the
## start's, at a whole-millimetre point with the robot's radius and a ship's
## diameter clear of that box's faces, of the reactor and of every robot
## already placed, and at least the plan's distances from the start and the
## reactor's centre. Each robot faces along one of the six axes. Every choice
## comes from a `RandomNumberGenerator` seeded from the generator's
## `output_hash`, itself fixed by the level seed, so the same seed gives the
## same robots however often the level is built, and the generator is left as
## it was (ARC-2). A robot that finds no room in `ROBOT_TRIES` draws ends the
## placing, with `MineGenerator.robot_note` saying how many were placed.
##
## With a `DebrisPlan` (#398) meltdown debris follows the robots, placed by
## `DebrisPlan.place` on the escape route from its own seeded draws, so the
## robots and `output_hash` are the same with or without it, and kept
## `min_robot_distance` clear of the robots placed (#436). Without a plan the
## level has no debris.

## Draws for one robot before the placing gives up.
const ROBOT_TRIES: int = 64
## The six directions a placed robot may face, millimetres.
const FACINGS: Array[Vector3i] = [
	Vector3i(RobotSpawn.SCALE, 0, 0), Vector3i(-RobotSpawn.SCALE, 0, 0),
	Vector3i(0, RobotSpawn.SCALE, 0), Vector3i(0, -RobotSpawn.SCALE, 0),
	Vector3i(0, 0, RobotSpawn.SCALE), Vector3i(0, 0, -RobotSpawn.SCALE),
]


## The level for `generator`. With no open connector the level is empty and
## `error` says so, as `LevelDef.parse_json` leaves it. Not checked here:
## `LevelValidator` does that.
static func build(generator: MineGenerator, plan: ReactorPlan, ship_radius: float,
		robot_plan: RobotPlan = null, debris_plan: DebrisPlan = null) -> LevelDef:
	var level: LevelDef = LevelDef.new()
	generator.reactor_note = ""
	generator.reactor_placement = -1
	generator.robot_note = ""
	generator.debris_note = ""
	if generator.open_connectors.is_empty():
		level.error = "no open connector to start at"
		return level
	var opening: ModuleConnector = generator.open_connectors[0]
	var inward: Vector3i = -ModuleTurns.outward(opening)
	level.union = BoxUnion.new(generator.union.boxes.duplicate())
	level.start_position_mm = opening.position_mm + inward * MineGenerator.START_INSET_MM
	level.start_facing_mm = inward * RobotSpawn.SCALE
	if plan != null:
		_place_reactor(generator, plan, ship_radius, level)
	if robot_plan != null:
		_place_robots(generator, robot_plan, ship_radius, level)
	if debris_plan != null:
		level.debris = debris_plan.place(generator, level, ship_radius, robot_plan)
	return level


## The placement whose open connector the start sits in.
static func start_placement(generator: MineGenerator) -> int:
	return generator.open_owner[0].x


## Joins between the first module and each placement, in placement order.
static func hops(generator: MineGenerator) -> Array[int]:
	var found: Array[int] = []
	for placement: ModulePlacement in generator.placements:
		found.append(0 if placement.parent < 0 else found[placement.parent] + 1)
	return found


## The box index of a placement's largest box; ties go to the lower index.
static func largest_box(generator: MineGenerator, placement: ModulePlacement) -> int:
	var best: int = placement.first_box
	var best_volume: int = -1
	for index: int in range(placement.first_box, placement.end_box):
		var size: Vector3i = generator.max_mm[index] - generator.min_mm[index]
		var volume: int = size.x * size.y * size.z
		if volume > best_volume:
			best = index
			best_volume = volume
	return best


static func _place_reactor(generator: MineGenerator, plan: ReactorPlan, ship_radius: float,
		level: LevelDef) -> void:
	var depth: Array[int] = hops(generator)
	var furthest: int = 0
	for index: int in depth.size():
		if depth[index] >= depth[furthest]:
			furthest = index
	if depth[furthest] < plan.min_hops:
		generator.reactor_note = "no reactor: the furthest module is %d joins from the first, below %d" \
				% [depth[furthest], plan.min_hops]
		return
	var box: int = largest_box(generator, generator.placements[furthest])
	var low: Vector3i = generator.min_mm[box]
	var high: Vector3i = generator.max_mm[box]
	var centre: Vector3i = (low + high) / 2
	var clear_mm: int = plan.reactor.radius_mm + roundi(2.0 * ship_radius * RobotSpawn.SCALE)
	for axis: int in 3:
		if centre[axis] - clear_mm < low[axis] or centre[axis] + clear_mm > high[axis]:
			generator.reactor_note = "no reactor: box %d of module %d is too small for the reactor and a ship's diameter" \
					% [box, furthest]
			return
	var reactor: ReactorState = plan.reactor.fresh_copy()
	reactor.position_mm = centre
	reactor.exit_radius_mm = level.exit_radius_mm
	level.reactor = reactor
	generator.reactor_placement = furthest


static func _place_robots(generator: MineGenerator, plan: RobotPlan, ship_radius: float,
		level: LevelDef) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([generator.output_hash(), "robots"])
	var start: int = start_placement(generator)
	var in_module: Array[int] = []
	in_module.resize(generator.placements.size())
	var wanted: int = plan.min_per_level + _pick(rng, plan.max_per_level - plan.min_per_level + 1)
	var radii: Array[int] = []
	for count: int in wanted:
		var spawn: RobotSpawn = null
		for attempt: int in ROBOT_TRIES:
			spawn = _try_robot(generator, plan, ship_radius, level, rng, start, in_module, radii)
			if spawn != null:
				break
		if spawn == null:
			generator.robot_note = "placed %d of %d robots: no room found in %d tries" \
					% [count, wanted, ROBOT_TRIES]
			return
		level.robots.spawns.append(spawn)


## One draw: a type, a module, a box and a point. The spawn, with its module
## counted and its radius kept in `radii`, or null when the point fails a check.
static func _try_robot(generator: MineGenerator, plan: RobotPlan, ship_radius: float,
		level: LevelDef, rng: RandomNumberGenerator, start: int, in_module: Array[int],
		radii: Array[int]) -> RobotSpawn:
	var open: Array[int] = []
	for index: int in generator.placements.size():
		if index != start and in_module[index] < plan.max_per_module:
			open.append(index)
	if open.is_empty():
		return null
	var type: int = _pick(rng, plan.types.size())
	var module: int = open[_pick(rng, open.size())]
	var placement: ModulePlacement = generator.placements[module]
	var box: int = placement.first_box + _pick(rng, placement.end_box - placement.first_box)
	var radius: int = plan.radii_mm[type]
	var diameter: int = roundi(2.0 * ship_radius * RobotSpawn.SCALE)
	var clear: int = radius + diameter
	var point: Vector3i = Vector3i.ZERO
	for axis: int in 3:
		var low: int = generator.min_mm[box][axis] + clear
		var high: int = generator.max_mm[box][axis] - clear
		if high < low:
			return null
		point[axis] = low + _pick(rng, high - low + 1)
	var facing: Vector3i = FACINGS[_pick(rng, FACINGS.size())]
	if _distance_squared(point, level.start_position_mm) < _squared(plan.min_start_distance_mm):
		return null
	if level.reactor != null:
		var reactor_gap: int = maxi(plan.min_reactor_distance_mm, level.reactor.radius_mm + clear)
		if _distance_squared(point, level.reactor.position_mm) < _squared(reactor_gap):
			return null
	for index: int in level.robots.spawns.size():
		var other: Vector3i = level.robots.spawns[index].position_mm
		if _distance_squared(point, other) < _squared(radii[index] + clear):
			return null
	var spawn: RobotSpawn = RobotSpawn.new(null, point, facing)
	spawn.id = plan.types[type]
	in_module[module] += 1
	radii.append(radius)
	return spawn


static func _distance_squared(a: Vector3i, b: Vector3i) -> int:
	var d: Vector3i = a - b
	return d.x * d.x + d.y * d.y + d.z * d.z


static func _squared(value: int) -> int:
	return value * value


## A whole number from 0 up to, not including, `size`.
static func _pick(rng: RandomNumberGenerator, size: int) -> int:
	return int(rng.randi() % size)
