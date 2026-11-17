extends RefCounted

## Generates and validates a run of seeds and sums up the result (#317, GEN-3):
## shared by `test_level_validator.gd` (1,000 seeds per pull request) and
## `validate_seeds.gd`, which a nightly job can call with 10,000. Files are
## read here, not in `gen/`, which never opens files.

const MODULES_DIR: String = "res://data/modules/"
const VALIDATOR_FILE: String = "res://data/gen/validator.json"
const REACTOR_FILE: String = "res://data/gen/reactor.json"
const GENERATOR_FILE: String = "res://data/gen/generator.json"
const ROBOTS_FILE: String = "res://data/gen/robots.json"
const ROBOTS_DIR: String = "res://data/robots/"
const SHIP_FILE: String = "res://data/ships/default_ship.json"
## Modules per level, as in the generator's own 1,000-seed test.
const MODULE_COUNT: int = 10
## Failure messages kept in a result, so 10,000 bad seeds do not flood a log.
const KEPT_FAILURES: int = 10


## Every module file in `MODULES_DIR`, in file name order.
static func load_modules() -> Array[ModuleDef]:
	var modules: Array[ModuleDef] = []
	var files: PackedStringArray = DirAccess.get_files_at(MODULES_DIR)
	files.sort()
	for file: String in files:
		if file.ends_with(".json"):
			modules.append(ModuleDef.parse_json(FileAccess.get_file_as_string(MODULES_DIR + file)))
	return modules


static func load_validator() -> LevelValidator:
	return LevelValidator.parse_json(FileAccess.get_file_as_string(VALIDATOR_FILE))


static func load_reactor_plan() -> ReactorPlan:
	return ReactorPlan.parse_json(FileAccess.get_file_as_string(REACTOR_FILE))


static func load_loop_bridges() -> LoopBridges:
	return LoopBridges.parse_json(FileAccess.get_file_as_string(GENERATOR_FILE))


## Every robot file's text by id, for `RobotPlan.parse_json`.
static func robot_texts() -> Dictionary:
	var texts: Dictionary = {}
	for file: String in DirAccess.get_files_at(ROBOTS_DIR):
		if file.ends_with(".json"):
			texts[file.trim_suffix(".json")] = FileAccess.get_file_as_string(ROBOTS_DIR + file)
	return texts


static func load_robot_plan() -> RobotPlan:
	return RobotPlan.parse_json(FileAccess.get_file_as_string(ROBOTS_FILE), robot_texts())


## The boxes of the module the generated level starts in.
static func start_module_boxes(generator: MineGenerator) -> Array[int]:
	var boxes: Array[int] = []
	if generator.open_owner.is_empty():
		return boxes
	var start: int = GeneratedLevel.start_placement(generator)
	var placement: ModulePlacement = generator.placements[start]
	for box: int in range(placement.first_box, placement.end_box):
		boxes.append(box)
	return boxes


static func ship_radius() -> float:
	return ShipTuning.parse_json(FileAccess.get_file_as_string(SHIP_FILE)).radius


## Seeds `first_seed` up to `first_seed + count - 1`, each level with the
## generator's reactor (#356, #357), loops (#396) and robots (#378, #399). The result holds "seeds",
## "passed", "failed", "short" (levels the generator stopped short, which are
## still validated), "looped" (levels with at least one loop), "robots" (robots
## placed over all levels), "ms", "by_check" (seeds failing each of `LevelValidator.CHECKS`,
## plus "level" for levels that did not build), and "failures": the first
## `kept_failures` messages, each prefixed with its seed. A `kept_failures` of 0
## keeps every message, so the nightly job can list every failing seed (#358).
static func run(first_seed: int, count: int, module_count: int = MODULE_COUNT,
		kept_failures: int = KEPT_FAILURES) -> Dictionary:
	var started: int = Time.get_ticks_msec()
	var modules: Array[ModuleDef] = load_modules()
	var validator: LevelValidator = load_validator()
	var plan: ReactorPlan = load_reactor_plan()
	var bridges: LoopBridges = load_loop_bridges()
	var robot_plan: RobotPlan = load_robot_plan()
	var radius: float = ship_radius()
	var by_check: Dictionary[String, int] = {"level": 0}
	for check: String in LevelValidator.CHECKS:
		by_check[check] = 0
	var result: Dictionary = {"seeds": count, "passed": 0, "failed": 0, "short": 0, "looped": 0, "robots": 0,
			"by_check": by_check, "failures": [] as Array[String]}
	# A broken data file must not pass every seed on the defaults.
	var broken: String = ""
	if validator.error != "":
		broken = "validator.json: %s" % validator.error
	elif plan.error != "":
		broken = "reactor.json: %s" % plan.error
	elif bridges.error != "":
		broken = "generator.json: %s" % bridges.error
	elif robot_plan.error != "":
		broken = "robots.json: %s" % robot_plan.error
	var robot_radii: Dictionary[String, int] = robot_plan.radii_by_id()
	if broken != "":
		result["failed"] = count
		result["failures"].append(broken)
		result["ms"] = Time.get_ticks_msec() - started
		return result
	for level_seed: int in range(first_seed, first_seed + count):
		var generator: MineGenerator = MineGenerator.generate(level_seed, modules, module_count, bridges)
		if generator.note != "":
			result["short"] += 1
		if generator.loops > 0:
			result["looped"] += 1
		var level: LevelDef = generator.to_level_def(plan, radius, robot_plan)
		result["robots"] += level.robots.spawns.size()
		var found: Array[String] = []
		if level.error != "":
			found.append("level: %s" % level.error)
		else:
			found = validator.validate(level, radius, true, robot_radii, start_module_boxes(generator))
		if found.is_empty():
			result["passed"] += 1
			continue
		result["failed"] += 1
		var counted: Array[String] = []
		for message: String in found:
			var check: String = message.get_slice(":", 0)
			if by_check.has(check) and not counted.has(check):
				counted.append(check)
				by_check[check] += 1
			if kept_failures == 0 or result["failures"].size() < kept_failures:
				result["failures"].append("seed %d: %s" % [level_seed, message])
	result["ms"] = Time.get_ticks_msec() - started
	return result


## One line for a log: "level validator: 1000 seeds, 1000 passed, 0 failed,
## 0 stopped short, 812 ms; failing seeds by check: level 0, piece 0, ...".
## The by-check part is left out when the result has none.
static func summary(result: Dictionary) -> String:
	var line: String = "level validator: %d seeds, %d passed, %d failed, %d stopped short, %d ms" % [
			result["seeds"], result["passed"], result["failed"], result["short"], result["ms"]]
	if not result.has("by_check"):
		return line
	var counts: Array[String] = []
	for check: String in result["by_check"]:
		counts.append("%s %d" % [check, result["by_check"][check]])
	return line + "; failing seeds by check: " + ", ".join(counts)
