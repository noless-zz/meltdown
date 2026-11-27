class_name LevelLoadPlan
extends RefCounted

## What the m6 `level_load` step loads and the budget it judges by (#1445,
## PRF-7, ARC-4), read from `acceptance/checks/level_load.json`, so the budget
## and the levels are data and not code.
##
## `run_seeds` name runs; each one loads that run's deepest level, the last of
## its plan, reached through `shaft`, the way `RunWiring` builds it: the shaft's
## seed and its robot count scale. The busiest shaft gives the heaviest load. A
## run seed whose plan is shorter than the longest run `data/run/run.json`
## allows is refused, so the step never quietly times a shallow level.
## `levels` adds named level files, such as the stress level (PRF-8).
##
## The budget lives here and not in the step because a new step key would edit
## `AcceptanceStepParser`, which #1444 is changing at the same time.

const FILE: String = "res://acceptance/checks/level_load.json"
const KEYS: Array[String] = ["budget_seconds", "run_seeds", "shaft", "levels"]
## PRF-7 asks for several seeds of the deepest level, not one lucky one.
const FEWEST_RUN_SEEDS: int = 3
## Largest whole number a JSON double holds exactly.
const MAX_EXACT_SEED: float = 9007199254740992.0

var budget_seconds: float = 0.0
var run_seeds: Array[int] = []
var shaft: String = ""
var levels: Array[String] = []
## The first problem, naming its field; empty when the plan can be used.
var error: String = ""


## The plan in the file at `path`; a missing file is an error.
static func load_file(path: String = FILE) -> LevelLoadPlan:
	if not FileAccess.file_exists(path):
		var missing: LevelLoadPlan = LevelLoadPlan.new()
		missing.error = "%s: file not found" % path
		return missing
	return parse_json(FileAccess.get_file_as_string(path))


static func parse_json(text: String) -> LevelLoadPlan:
	var plan: LevelLoadPlan = LevelLoadPlan.new()
	plan.error = plan._parse(text)
	return plan


## Every load the step times, in order, as {"label", "source", "shaft"}: the
## deepest level of each run seed through the plan's shaft, then each level
## file. `shaft` is "" for a level flown alone, which gets no run rules. Empty,
## with `error` set, when a run or the shaft cannot be used.
func loads(run_text: String, shafts: ShaftOffer) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if error != "":
		return found
	if shafts.error != "" or not shafts.kinds.has(shaft):
		error = "shaft: '%s' is not a shaft in shafts.json%s" % [shaft,
			"" if shafts.error == "" else " (%s)" % shafts.error]
		return found
	var robot_scale: float = float((shafts.risks[shaft] as Dictionary)["robot_count"])
	for run_seed: int in run_seeds:
		var run: RunPlan = RunPlan.build(run_seed, run_text)
		if run.error != "":
			error = "run.json: %s" % run.error
			return []
		if run.level_count() != run.max_levels:
			error = "run_seeds: run %d has %d levels, not the deepest run's %d" \
				% [run_seed, run.level_count(), run.max_levels]
			return []
		var last: int = run.level_count() - 1
		var level_seed: int = run.level_seed_through(last, shafts, shaft)
		found.append({"label": "run %d level %d seed %d" % [run_seed, run.depth(last), level_seed],
			"source": LevelSwitch.seed_source(level_seed, robot_scale), "shaft": shaft})
	for level_name: String in levels:
		found.append({"label": "level %s" % level_name, "source": LevelSwitch.path_for(level_name), "shaft": ""})
	return found


func _parse(text: String) -> String:
	var json: JSON = JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return "must be a JSON object"
	var data: Dictionary = json.data
	for key: Variant in data:
		if not KEYS.has(key):
			return "%s: unknown key" % str(key)
	for key: String in KEYS:
		if not data.has(key):
			return "%s: missing" % key
	var budget: Variant = data["budget_seconds"]
	if (typeof(budget) != TYPE_FLOAT and typeof(budget) != TYPE_INT) or float(budget) <= 0.0:
		return "budget_seconds: must be a number above 0"
	budget_seconds = float(budget)
	if typeof(data["run_seeds"]) != TYPE_ARRAY or (data["run_seeds"] as Array).size() < FEWEST_RUN_SEEDS:
		return "run_seeds: must list at least %d run seeds" % FEWEST_RUN_SEEDS
	for value: Variant in data["run_seeds"]:
		if not _is_seed(value) or run_seeds.has(int(value)):
			return "run_seeds: %s is not a new whole number from 0 up" % str(value)
		run_seeds.append(int(value))
	if typeof(data["shaft"]) != TYPE_STRING or str(data["shaft"]) == "":
		return "shaft: must name a shaft kind"
	shaft = data["shaft"]
	if typeof(data["levels"]) != TYPE_ARRAY:
		return "levels: must be a list of level names"
	for value: Variant in data["levels"]:
		if typeof(value) != TYPE_STRING or LevelSwitch.path_for(value) == "" \
				or not FileAccess.file_exists(LevelSwitch.path_for(value)):
			return "levels: '%s' is not a level file" % str(value)
		levels.append(value)
	return ""


static func _is_seed(value: Variant) -> bool:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return false
	var number: float = float(value)
	return number >= 0.0 and number == floorf(number) and number < MAX_EXACT_SEED
