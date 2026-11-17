extends RefCounted

## Generates and validates a run of seeds and sums up the result (#317, GEN-3):
## shared by `test_level_validator.gd` (1,000 seeds per pull request) and
## `validate_seeds.gd`, which a nightly job can call with 10,000. Files are
## read here, not in `gen/`, which never opens files.

const MODULES_DIR: String = "res://data/modules/"
const VALIDATOR_FILE: String = "res://data/gen/validator.json"
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


static func ship_radius() -> float:
	return ShipTuning.parse_json(FileAccess.get_file_as_string(SHIP_FILE)).radius


## Seeds `first_seed` up to `first_seed + count - 1`. The result holds
## "seeds", "passed", "failed", "short" (levels the generator stopped short,
## which are still validated), "ms", and "failures": the first `KEPT_FAILURES`
## messages, each prefixed with its seed.
static func run(first_seed: int, count: int, module_count: int = MODULE_COUNT) -> Dictionary:
	var started: int = Time.get_ticks_msec()
	var modules: Array[ModuleDef] = load_modules()
	var validator: LevelValidator = load_validator()
	var radius: float = ship_radius()
	var result: Dictionary = {"seeds": count, "passed": 0, "failed": 0, "short": 0,
			"failures": [] as Array[String]}
	if validator.error != "":
		# A broken data file must not pass every seed on the defaults.
		result["failed"] = count
		result["failures"].append("validator.json: %s" % validator.error)
		result["ms"] = Time.get_ticks_msec() - started
		return result
	for level_seed: int in range(first_seed, first_seed + count):
		var generator: MineGenerator = MineGenerator.generate(level_seed, modules, module_count)
		if generator.note != "":
			result["short"] += 1
		var level: LevelDef = generator.to_level_def()
		var found: Array[String] = []
		if level.error != "":
			found.append("level: %s" % level.error)
		else:
			found = validator.validate(level, radius)
		if found.is_empty():
			result["passed"] += 1
			continue
		result["failed"] += 1
		for message: String in found:
			if result["failures"].size() < KEPT_FAILURES:
				result["failures"].append("seed %d: %s" % [level_seed, message])
	result["ms"] = Time.get_ticks_msec() - started
	return result


## One line for a log: "level validator: 1000 seeds, 1000 passed, 0 failed,
## 0 stopped short, 812 ms".
static func summary(result: Dictionary) -> String:
	return "level validator: %d seeds, %d passed, %d failed, %d stopped short, %d ms" % [
			result["seeds"], result["passed"], result["failed"], result["short"], result["ms"]]
