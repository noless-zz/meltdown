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
##              "required": false}
##         ]
##     }
##
## Unknown keys, unknown checks and bad values are rejected with the field
## named, like `ShipTuning`: a mistyped key would otherwise switch a check off
## and the suite would still pass.

const SUITES_DIR: String = "res://acceptance/suites"
const SUITE_EXTENSION: String = ".json"
## Asking for this name loads every suite; it is not a file.
const ALL: String = "all"

const SUITE_KEYS: Array[String] = ["name", "steps"]
const STEP_KEYS: Array[String] = ["id", "replay", "preset", "checks", "expected_hash", "required"]
## Largest whole number a JSON double holds exactly; a hash above it could not
## be compared reliably.
const MAX_EXACT_INT: float = 9007199254740992.0

var name: String = ""
var steps: Array[AcceptanceStep] = []
## Set when the text or file was rejected; the field is named in the message.
var error: String = ""


## The suites asked for by `suite_name`: one suite, or every suite in
## SUITES_DIR in name order for ALL. A suite that could not be read is still
## returned, with `error` set, so the caller can report it rather than skip it.
static func load_named(suite_name: String, suites_dir: String = SUITES_DIR) -> Array[AcceptanceSuite]:
	var found: Array[AcceptanceSuite] = []
	if suite_name != ALL:
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
		found.append(load_file(suites_dir.path_join(file)))
	return found


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
	var problem: String = _unknown_key(data, SUITE_KEYS, "")
	if problem != "":
		return _failed(problem)
	if typeof(data.get("name")) != TYPE_STRING or str(data["name"]) == "":
		return _failed("name: must be a non-empty string")
	if typeof(data.get("steps")) != TYPE_ARRAY or (data["steps"] as Array).is_empty():
		return _failed("steps: must be a list of at least one step")
	var suite: AcceptanceSuite = AcceptanceSuite.new()
	suite.name = data["name"]
	var ids: Dictionary[String, bool] = {}
	var raw_steps: Array = data["steps"]
	for index: int in raw_steps.size():
		var field: String = "steps[%d]" % index
		var step: AcceptanceStep = AcceptanceStep.new()
		problem = _parse_step(raw_steps[index], field, step)
		if problem == "" and ids.has(step.id):
			problem = "%s.id: '%s' is used by an earlier step" % [field, step.id]
		if problem != "":
			return _failed(problem)
		ids[step.id] = true
		suite.steps.append(step)
	return suite


static func _parse_step(raw: Variant, field: String, step: AcceptanceStep) -> String:
	if typeof(raw) != TYPE_DICTIONARY:
		return "%s: must be a JSON object" % field
	var data: Dictionary = raw
	var problem: String = _unknown_key(data, STEP_KEYS, field + ".")
	if problem != "":
		return problem
	if typeof(data.get("id")) != TYPE_STRING or str(data["id"]) == "":
		return "%s.id: must be a non-empty string" % field
	step.id = data["id"]
	if data.has("replay"):
		if typeof(data["replay"]) != TYPE_STRING or str(data["replay"]) == "":
			return "%s.replay: must be a non-empty path" % field
		step.replay_path = data["replay"]
	if data.has("preset"):
		if not _is_whole(data["preset"]):
			return "%s.preset: must be a whole number" % field
		step.preset = int(data["preset"])
		if step.preset < AcceptanceStep.MIN_PRESET or step.preset > AcceptanceStep.MAX_PRESET:
			return "%s.preset: %d is outside %d..%d" % [
				field, step.preset, AcceptanceStep.MIN_PRESET, AcceptanceStep.MAX_PRESET]
	if data.has("required"):
		if typeof(data["required"]) != TYPE_BOOL:
			return "%s.required: must be true or false" % field
		step.required = data["required"]
	problem = _parse_checks(data.get("checks"), field + ".checks", step)
	if problem != "":
		return problem
	return _parse_expected_hash(data, field, step)


static func _parse_checks(raw: Variant, field: String, step: AcceptanceStep) -> String:
	if typeof(raw) != TYPE_ARRAY or (raw as Array).is_empty():
		return "%s: must be a list of at least one check" % field
	var raw_checks: Array = raw
	for index: int in raw_checks.size():
		var check: Variant = raw_checks[index]
		if typeof(check) != TYPE_STRING or not AcceptanceStep.KNOWN_CHECKS.has(check):
			return "%s[%d]: unknown check '%s', known: %s" % [
				field, index, str(check), ", ".join(AcceptanceStep.KNOWN_CHECKS)]
		if step.checks.has(check):
			return "%s[%d]: '%s' is listed twice" % [field, index, check]
		step.checks.append(check)
	return ""


## The final_hash check needs both a replay to fly and the hash it must end
## with; a hash without the check would be read and then never compared.
static func _parse_expected_hash(data: Dictionary, field: String, step: AcceptanceStep) -> String:
	var wants_hash: bool = step.has_check(AcceptanceStep.CHECK_FINAL_HASH)
	if not data.has("expected_hash"):
		return "%s.expected_hash: needed by the final_hash check" % field if wants_hash else ""
	if not wants_hash:
		return "%s.expected_hash: only used by the final_hash check, which the step does not list" % field
	var value: Variant = data["expected_hash"]
	if not _is_whole(value) or float(value) < 0.0 or float(value) > MAX_EXACT_INT:
		return "%s.expected_hash: must be a whole number from 0 to %d" % [field, int(MAX_EXACT_INT)]
	if step.replay_path == "":
		return "%s.replay: needed by the final_hash check" % field
	step.expected_hash = int(value)
	return ""


static func _unknown_key(data: Dictionary, allowed: Array[String], prefix: String) -> String:
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not allowed.has(key):
			return "%s%s: unknown key" % [prefix, str(key)]
	return ""


## JSON numbers arrive as floats. A bool must not pass as 0 or 1.
static func _is_whole(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return typeof(value) == TYPE_FLOAT and is_finite(value) and float(value) == floorf(value)


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
