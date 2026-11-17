extends RefCounted

## Generated levels place meltdown debris from a data file (#398, RUN-4, GEN-1,
## GEN-3, ARC-4, ARC-2): the file is checked key by key, naming every missing
## key; over seeds 0..999 the same seed gives the same debris, every entry keeps
## the file's distances (robots' too, #436) and sits on the escape route, every level still passes
## `LevelValidator`, and with every entry let fall or held back by
## `DebrisRouteGuard` the start stays reachable from the reactor. Without a
## plan there is no debris, and the plan changes neither `output_hash` nor the
## robots.

const SeedSweep := preload("res://tests/seed_sweep.gd")
const DEBRIS_FILE: String = "res://data/gen/debris.json"
const SEEDS: int = 1000
const TIME_LIMIT_MS: int = 60000
const VALID: Dictionary = {"count": [1, 3], "radius": [1, 2], "after_seconds": [5, 30],
		"min_start_distance": 10, "min_reactor_distance": 5, "min_robot_distance": 2,
		"latest_fall_fraction": 0.8}


func _plan() -> DebrisPlan:
	return DebrisPlan.parse_json(FileAccess.get_file_as_string(DEBRIS_FILE))


func _rejects(data: Dictionary, names: Array) -> String:
	var plan: DebrisPlan = DebrisPlan.parse_json(JSON.stringify(data))
	if plan.error == "":
		return "%s accepted" % JSON.stringify(data)
	for name: String in names:
		if not plan.error.contains(name):
			return "error \"%s\" does not name %s" % [plan.error, name]
	return ""


func test_data_file_reads() -> String:
	var plan: DebrisPlan = _plan()
	if plan.error != "":
		return "debris.json: %s" % plan.error
	if plan.min_count < 1 or plan.max_count < plan.min_count:
		return "count %d..%d" % [plan.min_count, plan.max_count]
	if plan.min_radius_mm < 1 or plan.max_radius_mm < plan.min_radius_mm:
		return "radius %d..%d mm" % [plan.min_radius_mm, plan.max_radius_mm]
	if plan.min_after_ticks < 1 or plan.max_after_ticks < plan.min_after_ticks:
		return "after %d..%d ticks" % [plan.min_after_ticks, plan.max_after_ticks]
	var parsed: DebrisPlan = DebrisPlan.parse_json(JSON.stringify(VALID))
	if parsed.error != "" or parsed.min_radius_mm != 1000 or parsed.max_after_ticks != 1800 \
			or parsed.min_start_distance_mm != 10000 or parsed.min_reactor_distance_mm != 5000 \
			or parsed.latest_fall_fraction != 0.8:
		return "VALID read as %s, radius %d mm, after %d ticks, distances %d and %d mm" % [parsed.error,
				parsed.min_radius_mm, parsed.max_after_ticks, parsed.min_start_distance_mm,
				parsed.min_reactor_distance_mm]
	return ""


func test_data_file_is_rejected_naming_the_bad_key() -> String:
	var cases: Array = [
		["count", 3, "count"], ["count", [3], "count"], ["count", [1.5, 3], "count"],
		["count", [3, 1], "count"], ["count", [-1, 2], "count"],
		["radius", [0, 2], "radius"], ["radius", [1, 50], "radius"], ["radius", ["big", 2], "radius"],
		["after_seconds", [0, 10], "after_seconds"], ["after_seconds", [20, 10], "after_seconds"],
		["min_start_distance", -1, "min_start_distance"],
		["min_reactor_distance", "far", "min_reactor_distance"], ["colour", "red", "colour"],
		["min_robot_distance", -0.5, "min_robot_distance"],
		["min_robot_distance", [2], "min_robot_distance"],
		["latest_fall_fraction", 0.05, "latest_fall_fraction"],
		["latest_fall_fraction", 1.5, "latest_fall_fraction"],
		["latest_fall_fraction", "late", "latest_fall_fraction"],
	]
	for case: Array in cases:
		var data: Dictionary = VALID.duplicate(true)
		data[case[0]] = case[1]
		var problem: String = _rejects(data, [case[2]])
		if problem != "":
			return problem
	for key: String in VALID:
		var data: Dictionary = VALID.duplicate(true)
		data.erase(key)
		var problem: String = _rejects(data, ["\"%s\"" % key])
		if problem != "":
			return problem
	if _rejects({}, ["\"count\"", "\"radius\"", "\"after_seconds\"", "\"min_start_distance\"",
			"\"min_reactor_distance\"", "\"min_robot_distance\"", "\"latest_fall_fraction\""]) != "":
		return "an empty file did not name every missing key: %s" % DebrisPlan.parse_json("{}").error
	if DebrisPlan.parse_json("[]").error == "":
		return "a JSON list was accepted"
	return "" if DebrisPlan.parse_json("{").error != "" else "broken JSON was accepted"


func test_without_a_plan_there_is_no_debris_and_nothing_else_changes() -> String:
	var modules: Array[ModuleDef] = SeedSweep.load_modules()
	var reactor_plan: ReactorPlan = SeedSweep.load_reactor_plan()
	var robot_plan: RobotPlan = SeedSweep.load_robot_plan()
	var generator: MineGenerator = MineGenerator.generate(42, modules, SeedSweep.MODULE_COUNT,
			SeedSweep.load_loop_bridges())
	var before: int = generator.output_hash()
	var without: LevelDef = generator.to_level_def(reactor_plan, 1.0, robot_plan)
	if without.debris != null:
		return "a level without a plan has debris"
	var with: LevelDef = generator.to_level_def(reactor_plan, 1.0, robot_plan, _plan())
	if generator.output_hash() != before:
		return "placing debris changed output_hash"
	if with.debris == null or with.debris.size() == 0:
		return "seed 42 has no debris (%s)" % generator.debris_note
	if with.robots.spawns.size() != without.robots.spawns.size():
		return "%d robots without debris, %d with" % [without.robots.spawns.size(), with.robots.spawns.size()]
	for index: int in with.robots.spawns.size():
		if with.robots.spawns[index].position_mm != without.robots.spawns[index].position_mm:
			return "robot %d moved when debris was placed" % index
	if with.reactor.position_mm != without.reactor.position_mm:
		return "the reactor moved when debris was placed"
	var no_reactor: LevelDef = generator.to_level_def(null, 1.0, robot_plan, _plan())
	return "" if no_reactor.debris == null else "a level with no reactor has debris"


func test_seeds_get_debris_that_never_closes_the_escape() -> String:
	var modules: Array[ModuleDef] = SeedSweep.load_modules()
	var validator: LevelValidator = SeedSweep.load_validator()
	var reactor_plan: ReactorPlan = SeedSweep.load_reactor_plan()
	var bridges: LoopBridges = SeedSweep.load_loop_bridges()
	var robot_plan: RobotPlan = SeedSweep.load_robot_plan()
	var plan: DebrisPlan = _plan()
	var radius: float = SeedSweep.ship_radius()
	var started: int = Time.get_ticks_msec()
	var placed: int = 0
	var solid: int = 0
	for level_seed: int in SEEDS:
		var generator: MineGenerator = MineGenerator.generate(level_seed, modules,
				SeedSweep.MODULE_COUNT, bridges)
		var level: LevelDef = generator.to_level_def(reactor_plan, radius, robot_plan, plan)
		var again: LevelDef = MineGenerator.generate(level_seed, modules, SeedSweep.MODULE_COUNT,
				bridges).to_level_def(reactor_plan, radius, robot_plan, plan)
		var problem: String = _same(level.debris, again.debris)
		if problem == "":
			problem = _check(generator, level, plan, radius)
		if problem == "":
			problem = _robots_clear(level, plan, robot_plan.radii_by_id())
		if problem == "":
			var found: Array[String] = validator.validate(level, radius, true,
					robot_plan.radii_by_id(), SeedSweep.start_module_boxes(generator))
			problem = "" if found.is_empty() else "validator: %s" % found[0]
		if problem != "":
			return "seed %d: %s" % [level_seed, problem]
		if level.debris == null:
			continue
		placed += level.debris.size()
		var fallen: Array[int] = []
		problem = _meltdown(level, radius, fallen)
		if problem != "":
			return "seed %d: %s" % [level_seed, problem]
		solid += fallen[0]
	# Most spots are kept clear only by the guard, so most entries must still fall.
	if placed < SEEDS or solid < placed / 2:
		return "%d entries over %d seeds, %d of them fell" % [placed, SEEDS, solid]
	var elapsed: int = Time.get_ticks_msec() - started
	return "" if elapsed <= TIME_LIMIT_MS else "%d seeds took %d ms, limit %d" % [SEEDS, elapsed, TIME_LIMIT_MS]


func _same(a: MeltdownDebris, b: MeltdownDebris) -> String:
	if a == null or b == null:
		return "" if a == b else "debris once, none the other time"
	if a.positions_mm != b.positions_mm or a.radii_mm != b.radii_mm or a.after_ticks != b.after_ticks:
		return "the same seed gave different debris: %s then %s" % [a.to_json(), b.to_json()]
	return ""


## Counts, ranges, distances and spots, checked apart from `DebrisPlan.fits`.
func _check(generator: MineGenerator, level: LevelDef, plan: DebrisPlan, radius: float) -> String:
	if level.reactor == null:
		return "" if level.debris == null else "debris without a reactor"
	var count: int = 0 if level.debris == null else level.debris.size()
	if (count < plan.min_count or count > plan.max_count) and generator.debris_note == "":
		return "%d entries, plan allows %d..%d, and no note" % [count, plan.min_count, plan.max_count]
	var spots: Array[Vector3i] = DebrisSpots.escape_spots(generator, level, radius)
	for index: int in count:
		var debris: MeltdownDebris = level.debris
		var r: int = debris.radii_mm[index]
		var ticks: int = debris.after_ticks[index]
		if r < plan.min_radius_mm or r > plan.max_radius_mm:
			return "entry %d radius %d mm outside the plan" % [index, r]
		if ticks < plan.min_after_ticks or ticks > plan.max_after_ticks:
			return "entry %d falls after %d ticks, outside the plan" % [index, ticks]
		var at: Vector3 = debris.position(index)
		var to_start: float = at.distance_to(level.start_position()) - debris.radius(index)
		if to_start < plan.min_start_distance_mm / 1000.0 - 0.001:
			return "entry %d is %s m from the start" % [index, to_start]
		var to_reactor: float = at.distance_to(level.reactor.position()) - debris.radius(index) \
				- level.reactor.radius()
		if to_reactor < plan.min_reactor_distance_mm / 1000.0 - 0.001:
			return "entry %d is %s m from the reactor" % [index, to_reactor]
		if not spots.has(debris.positions_mm[index]):
			return "entry %d at %s is not on the escape route" % [index, at]
		if not level.union.holds(at, 0.0):
			return "entry %d at %s is outside the level" % [index, at]
	return ""


## Every entry keeps `min_robot_distance` from every robot, worked out apart
## from `DebrisPlan.clear_of_robots`.
func _robots_clear(level: LevelDef, plan: DebrisPlan, robot_radii: Dictionary[String, int]) -> String:
	if level.debris == null:
		return ""
	for index: int in level.debris.size():
		for robot: int in level.robots.spawns.size():
			var gap: float = level.debris.position(index).distance_to(
					level.robots.spawns[robot].position()) - level.debris.radius(index) \
					- robot_radii[level.robots.spawns[robot].id] / 1000.0
			if gap < plan.min_robot_distance_mm / 1000.0 - 0.001:
				return "entry %d is %s m from robot %d" % [index, gap, robot]
	return ""


## The meltdown with a ship at the reactor: each tick an entry falls due on is
## run through `DebrisRouteGuard`, jumping the clock between them, so every
## entry ends solid or held back. The start must still be reachable from the
## reactor. `fallen` gets the number that became solid.
func _meltdown(level: LevelDef, radius: float, fallen: Array[int]) -> String:
	var sim: Sim = Sim.new(0, 1)
	sim.set_walls(level.union)
	sim.set_start_pose(0, level.start_position(), Basis())
	sim.ships[0].radius = radius
	sim.ships[0].position = level.reactor.position()
	var reactor: ReactorState = level.reactor.fresh_copy()
	reactor.destroyed = true
	sim.set_reactor(reactor)
	sim.set_debris(level.debris.fresh_copy())
	var due: Array[int] = []
	for ticks: int in sim.debris.after_ticks:
		if not due.has(ticks):
			due.append(ticks)
	due.sort()
	var events: Array[SimEvent] = []
	for ticks: int in due:
		sim.debris.elapsed_ticks = ticks - 1
		DebrisRouteGuard.advance(sim, events)
	var count: int = 0
	for index: int in sim.debris.size():
		if sim.debris.elapsed_ticks < sim.debris.after_ticks[index]:
			return "entry %d never fell due" % index
		if sim.debris.is_solid(index):
			count += 1
	fallen.append(count)
	var all: Array[int] = []
	for box: int in level.union.boxes.size():
		all.append(box)
	var route: KnownRoute = KnownRoute.find(level.union, all, level.reactor.position(),
			level.start_position(), sim.debris, radius)
	if route.length_mm == EscapePath.UNREACHABLE:
		return "debris closed every route from the reactor to the start: %s" % sim.debris.to_json()
	return ""
