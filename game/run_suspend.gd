class_name RunSuspend
extends RefCounted

## Suspends a run at the shaft choice and rebuilds it for the hub's resume
## (#1107, RUN-8, RUN-7, CRF-2). The shaft panel offers one more row, worded in
## `data/run/suspend.json`, when the run has a save store: the escape has
## already banked as every escape does, so suspending only writes the run's
## `RunResume.to_save` through `RunSaveStore`. Nothing is saved before that
## row is confirmed, so quitting at the choice leaves no save, and a lost ship
## never writes one (RUN-7).
##
## A save keeps the shafts chosen before the choice it was made at, so the
## resumed run still has that choice due: it takes the first offered shaft, as
## a restart without a choice does (`RunWiring.resume`).
##
## It sits beside `main.gd`, as `RunWiring` does, because it joins the core run
## to the `meta/` save; it keeps `run_wiring.gd` under 300 lines.

const WORDS_FILE: String = "res://data/run/suspend.json"
const LOG_PREFIX: String = "[meltdown run]"
## The shaft panel's kind for the suspend row. Shaft kinds are plain words
## from the shaft file, so this one can never be offered as a shaft.
const ROW_KIND: String = "@suspend"
const KEYS: Array[String] = ["row_text", "detail_text"]
## Used when the words file is missing or rejected; matches the shipped file.
const FALLBACK: Dictionary = {"row_text": "Suspend run", "detail_text": "bank, save and leave for the hub"}


## The suspend row's words from `text` (the words file's when empty), or
## `FALLBACK` with one logged line naming the problem.
static func words(text: String = "") -> Dictionary:
	if text == "":
		text = FileAccess.get_file_as_string(WORDS_FILE) if FileAccess.file_exists(WORDS_FILE) else ""
	var problem: String = _check(text)
	if problem != "":
		print("%s %s: %s; the suspend row uses built-in words" % [LOG_PREFIX, WORDS_FILE, problem])
		return FALLBACK
	return JSON.parse_string(text)


## Writes `run`'s save at its shaft choice. False, with `run.error` set and
## logged and nothing written, when the run has no save store, is not at a
## choice, or the save is refused; the hub must be able to open too, since
## suspending leaves for it.
static func save(run: RunWiring) -> bool:
	if run.saves == null:
		return _refuse(run, "the run has no save store")
	if not run.active() or not run.escape_taken or not run.state.needs_choice():
		return _refuse(run, "a run is suspended only at the shaft choice")
	var hub_problem: String = HubConfig.load_shipped().error
	if hub_problem != "":
		return _refuse(run, "the hub cannot open: %s" % hub_problem)
	var saved: RunSave = RunResume.to_save(run.state, ship_id(run.ship.ship_path), ship_loadout(run.ship.ship_path))
	if saved.error != "":
		return _refuse(run, saved.error)
	if not run.saves.save(saved):
		return _refuse(run, run.saves.message)
	print("%s run %d suspended before level %d" % [LOG_PREFIX, saved.run_seed, saved.next_level])
	return true


## The run `saved` holds, rebuilt on `run`'s run file and shafts; null, with
## `run.error` set, when it cannot be.
static func rebuild(run: RunWiring, saved: RunSave) -> RunState:
	var plan: RunPlan = RunPlan.build(saved.run_seed, run.run_text)
	if plan.error != "":
		_refuse(run, "%s rejected: %s" % [RunWiring.RUN_FILE, plan.error])
		return null
	var state: RunState = RunResume.resume(saved, plan, run.shafts)
	if state.error != "":
		_refuse(run, state.error)
		return null
	return state


## The ship data id of the file at `path`: `default_ship` for `.../default_ship.json`.
static func ship_id(path: String) -> String:
	return path.get_file().get_basename()


## The ship file's weapon slots, or {} when it cannot be read.
static func ship_loadout(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) \
		if FileAccess.file_exists(path) else null
	if typeof(parsed) != TYPE_DICTIONARY or typeof((parsed as Dictionary).get("loadout")) != TYPE_DICTIONARY:
		return {}
	return (parsed as Dictionary)["loadout"]


static func _refuse(run: RunWiring, reason: String) -> bool:
	run.error = reason
	print("%s not suspending or resuming the run: %s" % [LOG_PREFIX, reason])
	return false


static func _check(text: String) -> String:
	if text == "":
		return "file not found"
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]
	if typeof(json.data) != TYPE_DICTIONARY:
		return "top level must be a JSON object"
	var data: Dictionary = json.data
	for key: Variant in data:
		if not KEYS.has(str(key)):
			return "unknown key \"%s\"" % str(key)
	for key: String in KEYS:
		if typeof(data.get(key)) != TYPE_STRING or String(data[key]).strip_edges() == "":
			return "key \"%s\" must be a non-empty string" % key
	return ""
