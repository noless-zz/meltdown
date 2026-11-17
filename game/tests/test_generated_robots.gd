extends RefCounted

## The generator places robots from a data file (#378, GEN-1, GEN-2, CMB-3,
## ARC-4): the file is checked key by key; over 1,000 seeds every 10-module
## level gets a robot count within the plan's bounds, each robot inside a box
## with its radius and a ship's diameter clear, outside the start module and
## far enough from the start and the reactor; the same seed gives the same
## robots; and without a plan there are none.

const SeedSweep := preload("res://tests/seed_sweep.gd")
const ROBOTS_FILE: String = "res://data/gen/robots.json"
const ROBOTS_DIR: String = "res://data/robots/"
const SEEDS: int = 1000
const TIME_LIMIT_MS: int = 20000
const VALID: Dictionary = {"types": ["drone", "glider"], "min_per_level": 2, "max_per_level": 5,
		"max_per_module": 2, "min_start_distance": 20, "min_reactor_distance": 8}


## Every robot file's text by id.
static func _robot_texts() -> Dictionary:
	var texts: Dictionary = {}
	for file: String in DirAccess.get_files_at(ROBOTS_DIR):
		if file.ends_with(".json"):
			texts[file.trim_suffix(".json")] = FileAccess.get_file_as_string(ROBOTS_DIR + file)
	return texts


func _plan() -> RobotPlan:
	return RobotPlan.parse_json(FileAccess.get_file_as_string(ROBOTS_FILE), _robot_texts())


func _rejects(data: Dictionary, names: String) -> String:
	var plan: RobotPlan = RobotPlan.parse_json(JSON.stringify(data), _robot_texts())
	if plan.error == "":
		return "%s accepted" % JSON.stringify(data)
	if not plan.types.is_empty():
		return "a rejected plan kept its types"
	return "" if plan.error.contains(names) else "error \"%s\" does not name %s" % [plan.error, names]


func test_data_file_reads() -> String:
	var plan: RobotPlan = _plan()
	if plan.error != "":
		return "robots.json: %s" % plan.error
	if plan.types.is_empty() or plan.types.size() != plan.radii_mm.size():
		return "read %d types and %d radii" % [plan.types.size(), plan.radii_mm.size()]
	if plan.min_per_level < 1 or plan.max_per_level < plan.min_per_level or plan.max_per_module < 1:
		return "counts %d..%d, %d per module" % [plan.min_per_level, plan.max_per_level, plan.max_per_module]
	var drone: int = plan.types.find("drone")
	if drone >= 0 and plan.radii_mm[drone] != 800:
		return "drone radius read as %d mm" % plan.radii_mm[drone]
	return ""


func test_data_file_is_rejected_naming_the_bad_key() -> String:
	var cases: Array = [
		["types", [], "types"], ["types", "drone", "types"], ["types", ["drone", 3], "types"],
		["types", ["drone", "dragon"], "dragon"], ["types", ["drone", "drone"], "drone"],
		["min_per_level", -1, "min_per_level"], ["min_per_level", 1.5, "min_per_level"],
		["max_per_level", "many", "max_per_level"], ["max_per_level", 1, "max_per_level"],
		["max_per_module", 0, "max_per_module"], ["min_start_distance", -1, "min_start_distance"],
		["min_reactor_distance", "far", "min_reactor_distance"], ["colour", "red", "colour"],
	]
	for case: Array in cases:
		var data: Dictionary = VALID.duplicate(true)
		data[case[0]] = case[1]
		var problem: String = _rejects(data, case[2])
		if problem != "":
			return problem
	for key: String in VALID:
		var data: Dictionary = VALID.duplicate(true)
		data.erase(key)
		var problem: String = _rejects(data, "\"%s\"" % key)
		if problem != "":
			return problem
	if RobotPlan.parse_json("[]", _robot_texts()).error == "":
		return "a JSON list was accepted"
	var broken: Dictionary = _robot_texts()
	broken["drone"] = "{}"
	var plan: RobotPlan = RobotPlan.parse_json(JSON.stringify(VALID), broken)
	return "" if plan.error.contains("drone") else "a broken drone file gave \"%s\"" % plan.error


func test_thousand_seeds_get_robots_within_the_plan() -> String:
	var modules: Array[ModuleDef] = SeedSweep.load_modules()
	var reactor_plan: ReactorPlan = SeedSweep.load_reactor_plan()
	var plan: RobotPlan = _plan()
	var ship_radius: float = SeedSweep.ship_radius()
	var started: int = Time.get_ticks_msec()
	var checked: int = 0
	for level_seed: int in range(1, SEEDS + 1):
		var generator: MineGenerator = MineGenerator.generate(level_seed, modules, SeedSweep.MODULE_COUNT)
		if generator.placements.size() != SeedSweep.MODULE_COUNT:
			continue
		var level: LevelDef = generator.to_level_def(reactor_plan, ship_radius, plan)
		var problem: String = _check(generator, level, plan, ship_radius)
		if problem != "":
			return "seed %d: %s" % [level_seed, problem]
		checked += 1
	if checked < SEEDS / 2:
		return "only %d seeds placed every module" % checked
	var elapsed: int = Time.get_ticks_msec() - started
	return "" if elapsed <= TIME_LIMIT_MS else "%d seeds took %d ms, limit %d" % [SEEDS, elapsed, TIME_LIMIT_MS]


func _check(generator: MineGenerator, level: LevelDef, plan: RobotPlan, ship_radius: float) -> String:
	var count: int = level.robots.spawns.size()
	if count < plan.min_per_level or count > plan.max_per_level:
		return "%d robots, plan allows %d..%d (%s)" % [count, plan.min_per_level, plan.max_per_level,
				generator.robot_note]
	# The start module found from the start position, independently of the generator.
	var start_module: int = -1
	for index: int in generator.placements.size():
		var placement: ModulePlacement = generator.placements[index]
		for box: int in range(placement.first_box, placement.end_box):
			if level.union.boxes[box].holds(level.start_position(), 0.0):
				start_module = index
	if start_module < 0:
		return "start is in no module's box"
	var per_module: Dictionary[int, int] = {}
	for spawn: RobotSpawn in level.robots.spawns:
		var type: int = plan.types.find(spawn.id)
		if type < 0:
			return "robot of type \"%s\" is not in the plan" % spawn.id
		if spawn.facing_mm == Vector3i.ZERO:
			return "robot at %s has no facing" % spawn.position()
		var clear: float = plan.radii_mm[type] / 1000.0 + 2.0 * ship_radius
		var diameter_mm: int = roundi(2000.0 * ship_radius)
		var holder: int = -1
		for index: int in generator.placements.size():
			var placement: ModulePlacement = generator.placements[index]
			for box: int in range(placement.first_box, placement.end_box):
				if index == start_module and level.union.boxes[box].holds(spawn.position(), 0.0):
					return "%s at %s is in the start module" % [spawn.id, spawn.position()]
				if _holds_mm(generator, box, spawn.position_mm, plan.radii_mm[type] + diameter_mm):
					holder = index
		if holder < 0:
			return "%s at %s is not inside a module box with %s m clear" % [spawn.id, spawn.position(), clear]
		per_module[holder] = per_module.get(holder, 0) + 1
		if per_module[holder] > plan.max_per_module:
			return "module %d has more than %d robots" % [holder, plan.max_per_module]
		if spawn.position().distance_to(level.start_position()) < plan.min_start_distance_mm / 1000.0:
			return "%s at %s is too near the start" % [spawn.id, spawn.position()]
		if level.reactor != null:
			var gap: float = maxf(plan.min_reactor_distance_mm / 1000.0, level.reactor.radius() + clear)
			if spawn.position().distance_to(level.reactor.position()) < gap:
				return "%s at %s is within %s m of the reactor" % [spawn.id, spawn.position(), gap]
	return ""


## True if `point` is at least `clear_mm` inside every face of box `box`,
## checked in the generator's whole millimetres so float rounding plays no part.
static func _holds_mm(generator: MineGenerator, box: int, point: Vector3i, clear_mm: int) -> bool:
	for axis: int in 3:
		if point[axis] - clear_mm < generator.min_mm[box][axis] \
				or point[axis] + clear_mm > generator.max_mm[box][axis]:
			return false
	return true


func test_same_seed_same_robots_and_hash_unchanged() -> String:
	var modules: Array[ModuleDef] = SeedSweep.load_modules()
	var reactor_plan: ReactorPlan = SeedSweep.load_reactor_plan()
	var plan: RobotPlan = _plan()
	var first: MineGenerator = MineGenerator.generate(42, modules, SeedSweep.MODULE_COUNT)
	var before: int = first.output_hash()
	var a: LevelDef = first.to_level_def(reactor_plan, 1.0, plan)
	if first.output_hash() != before:
		return "placing robots changed output_hash"
	var again: LevelDef = first.to_level_def(reactor_plan, 1.0, plan)
	var b: LevelDef = MineGenerator.generate(42, modules, SeedSweep.MODULE_COUNT) \
			.to_level_def(reactor_plan, 1.0, plan)
	if a.robots.spawns.is_empty():
		return "seed 42 has no robots"
	for other: LevelDef in [again, b]:
		var problem: String = _same(a, other)
		if problem != "":
			return problem
	var c: LevelDef = MineGenerator.generate(43, modules, SeedSweep.MODULE_COUNT) \
			.to_level_def(reactor_plan, 1.0, plan)
	return "seeds 42 and 43 placed the same robots" if _same(a, c) == "" else ""


func _same(a: LevelDef, b: LevelDef) -> String:
	if a.robots.spawns.size() != b.robots.spawns.size():
		return "%d robots, then %d" % [a.robots.spawns.size(), b.robots.spawns.size()]
	for index: int in a.robots.spawns.size():
		var x: RobotSpawn = a.robots.spawns[index]
		var y: RobotSpawn = b.robots.spawns[index]
		if x.id != y.id or x.position_mm != y.position_mm or x.facing_mm != y.facing_mm:
			return "robot %d: %s %s %s, then %s %s %s" % [index, x.id, x.position_mm, x.facing_mm,
					y.id, y.position_mm, y.facing_mm]
	return ""


func test_without_a_plan_there_are_no_robots() -> String:
	var modules: Array[ModuleDef] = SeedSweep.load_modules()
	var reactor_plan: ReactorPlan = SeedSweep.load_reactor_plan()
	var with_plan: LevelDef = MineGenerator.generate(7, modules, SeedSweep.MODULE_COUNT) \
			.to_level_def(reactor_plan, 1.0, _plan())
	var generator: MineGenerator = MineGenerator.generate(7, modules, SeedSweep.MODULE_COUNT)
	var level: LevelDef = generator.to_level_def(reactor_plan, 1.0)
	if not level.robots.spawns.is_empty() or generator.robot_note != "":
		return "robots were placed without a plan"
	if not generator.to_level_def().robots.spawns.is_empty():
		return "robots were placed with no plans at all"
	if with_plan.reactor == null or level.reactor == null \
			or with_plan.reactor.position_mm != level.reactor.position_mm \
			or with_plan.start_position_mm != level.start_position_mm:
		return "the robot plan moved the reactor or the start"
	return ""


func test_placed_robots_resolve_from_their_files() -> String:
	var level: LevelDef = MineGenerator.generate(11, SeedSweep.load_modules(), SeedSweep.MODULE_COUNT) \
			.to_level_def(SeedSweep.load_reactor_plan(), 1.0, _plan())
	var problem: String = level.robots.resolve(_robot_texts())
	return "" if problem == "" else "resolve: %s" % problem
