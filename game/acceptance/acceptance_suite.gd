class_name AcceptanceSuite
extends RefCounted

## A named, ordered list of acceptance steps, read from a JSON data file in
## SUITES_DIR (DEV-6, ARC-4). The suites live outside `tests/` because every
## export preset leaves `tests/*` out, and a suite must reach the headset.
##
## File format:
##
##     {
##         "name": "m1",
##         "steps": [
##             {"id": "fly", "replay": "res://acceptance/replays/x.replay",
##              "preset": 2, "checks": ["final_hash"], "expected_hash": 123,
##              "required": false, "level": "g2",
##              "expected_outcome": "ESCAPED"}
##         ],
##         "manual_only": false
##     }
##
## A run step may name scratch `profile` and `fitting` files (#1057): its run's
## levels then fly the ship built from them, as `--run` builds it from the
## pilot's own files; a run step without them flies the plain ship file
## (`AcceptanceFittedStart`).
##
## `manual_only` (optional, default false) keeps a suite out of NIGHTLY: the
## 25-minute soak is too long for the nightly headset run and is dispatched by
## hand instead (#812).
##
## Each step's fields are read and checked by `AcceptanceStepParser` (#817).
## Unknown keys, unknown checks and bad values are rejected with the field
## named, like `ShipTuning`: a mistyped key would otherwise switch a check off
## and the suite would still pass.

const SUITES_DIR: String = "res://acceptance/suites"
const SUITE_EXTENSION: String = ".json"
## Asking for this name loads every suite; it is not a file.
const ALL: String = "all"
## Asking for this name loads every suite that is not `manual_only`: what the
## nightly device run executes (#812). A new suite joins it without a change
## to the workflow. It is not a file either.
const NIGHTLY: String = "nightly"

const SUITE_KEYS: Array[String] = ["name", "steps", "manual_only"]

var name: String = ""
## Left out of NIGHTLY; run only when asked for by name or by ALL.
var manual_only: bool = false
var steps: Array[AcceptanceStep] = []
## Set when the text or file was rejected; the field is named in the message.
var error: String = ""


## The suites asked for by `suite_name`: one suite, every suite in SUITES_DIR
## in name order for ALL, or every suite but the `manual_only` ones for
## NIGHTLY. A suite that could not be read is still returned, with `error`
## set, so the caller can report it rather than skip it.
static func load_named(suite_name: String, suites_dir: String = SUITES_DIR) -> Array[AcceptanceSuite]:
	var found: Array[AcceptanceSuite] = []
	if suite_name != ALL and suite_name != NIGHTLY:
		found.append(load_file(suites_dir.path_join(suite_name + SUITE_EXTENSION)) if _is_plain_name(suite_name)
			else _failed("suite name '%s' may only use a-z, 0-9, '_' and '-'" % suite_name))
		return found
	var files: PackedStringArray = DirAccess.get_files_at(suites_dir)
	var names: Array[String] = []
	for file: String in files:
		if file.ends_with(SUITE_EXTENSION):
			names.append(file)
	names.sort()
	for file: String in names:
		var suite: AcceptanceSuite = load_file(suites_dir.path_join(file))
		# An unreadable suite stays in, so a broken file still fails the night.
		if suite_name == NIGHTLY and suite.error == "" and suite.manual_only:
			continue
		found.append(suite)
	return found


## Why `found` cannot be run, or "": every suite must load before anything
## flies, so a missing or rejected suite ends the run with this message.
static func unreadable(found: Array[AcceptanceSuite]) -> String:
	if found.is_empty():
		return "no suite found"
	for suite: AcceptanceSuite in found:
		if suite.error != "":
			return "cannot run: %s" % suite.error
	return ""


## Reads one suite file. Its `name` must equal the file name without the
## extension, so `--acceptance=m1` and the report name the same suite.
static func load_file(path: String) -> AcceptanceSuite:
	if not FileAccess.file_exists(path):
		return _failed("cannot open %s" % path)
	var suite: AcceptanceSuite = parse_json(FileAccess.get_file_as_string(path))
	var stem: String = path.get_file().trim_suffix(SUITE_EXTENSION)
	if suite.error == "" and suite.name != stem:
		suite = _failed("name: '%s' does not match the file name '%s'" % [suite.name, stem])
	if suite.error != "":
		suite.error = "%s: %s" % [path, suite.error]
	return suite


## Parses the text of a suite file. On failure the returned suite has
## `error` set and no steps.
static func parse_json(text: String) -> AcceptanceSuite:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _failed("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _failed("top level must be a JSON object")
	var data: Dictionary = json.data
	var problem: String = AcceptanceStepParser.unknown_key(data, SUITE_KEYS, "")
	if problem != "":
		return _failed(problem)
	if typeof(data.get("name")) != TYPE_STRING or str(data["name"]) == "":
		return _failed("name: must be a non-empty string")
	if typeof(data.get("steps")) != TYPE_ARRAY or (data["steps"] as Array).is_empty():
		return _failed("steps: must be a list of at least one step")
	if typeof(data.get("manual_only", false)) != TYPE_BOOL:
		return _failed("manual_only: must be true or false")
	var suite: AcceptanceSuite = AcceptanceSuite.new()
	suite.name = data["name"]
	suite.manual_only = data.get("manual_only", false)
	var ids: Dictionary[String, bool] = {}
	var raw_steps: Array = data["steps"]
	for index: int in raw_steps.size():
		var field: String = "steps[%d]" % index
		var step: AcceptanceStep = AcceptanceStep.new()
		problem = AcceptanceStepParser.parse(raw_steps[index], field, step)
		if problem == "" and ids.has(step.id):
			problem = "%s.id: '%s' is used by an earlier step" % [field, step.id]
		if problem != "":
			return _failed(problem)
		ids[step.id] = true
		suite.steps.append(step)
	return suite


## Keeps a launch argument from reaching outside SUITES_DIR.
static func _is_plain_name(suite_name: String) -> bool:
	if suite_name == "":
		return false
	for character: String in suite_name:
		if not (character >= "a" and character <= "z") and not (character >= "0" and character <= "9") \
				and character != "_" and character != "-":
			return false
	return true


static func _failed(message: String) -> AcceptanceSuite:
	var suite: AcceptanceSuite = AcceptanceSuite.new()
	suite.error = message
	return suite
