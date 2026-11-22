class_name AcceptanceSuiteParts
extends RefCounted

## Suite parts (#1297, DEV-6, ARC-4): a suite may list `"include": ["m6/perf", ...]`,
## each a file `<folder>/<name>.json` under the suite's own folder holding only
## `{"steps": [...]}`. Their steps run after the suite's own, in the listed
## order, and report under the including suite's name. Parts let lanes that
## work at the same time each own a file of a milestone's suite (decision
## record 0003), where one shared suite file would make them edit the same lines.
##
## A part lives in a subfolder, so `AcceptanceSuite.load_named` never lists it
## as a suite of its own. A part may hold no steps yet; a suite whose own steps
## and parts are all empty runs as "no steps" and is skipped (`AcceptanceReport`).

const INCLUDE_KEY: String = "include"
const PART_KEYS: Array[String] = ["steps"]


## Why `raw` is not a list of distinct part names, or "".
static func check_names(raw: Variant) -> String:
	if typeof(raw) != TYPE_ARRAY:
		return "%s: must be a list of part names" % INCLUDE_KEY
	var names: Array = raw
	var seen: Array[String] = []
	for index: int in names.size():
		var part: Variant = names[index]
		if typeof(part) != TYPE_STRING or not is_part_name(part):
			return "%s[%d]: '%s' is not a part name: a folder and a file name such as 'm6/perf', each of a-z, 0-9, '_' and '-'" \
				% [INCLUDE_KEY, index, str(part)]
		if seen.has(part):
			return "%s[%d]: '%s' is listed twice" % [INCLUDE_KEY, index, part]
		seen.append(part)
	return ""


## True for `<folder>/<name>` with both plain names: no `..`, no deeper folder,
## so an include cannot reach outside the suites folder.
static func is_part_name(part: String) -> bool:
	var pieces: PackedStringArray = part.split("/")
	return pieces.size() == 2 and AcceptanceSuite.is_plain_name(pieces[0]) \
		and AcceptanceSuite.is_plain_name(pieces[1])


## Parses `raw_steps` and appends them to `suite`. A step id may be used once
## across the suite and all its parts, so a report never names two steps alike.
static func add_steps(raw_steps: Array, suite: AcceptanceSuite) -> String:
	for index: int in raw_steps.size():
		var field: String = "steps[%d]" % index
		var step: AcceptanceStep = AcceptanceStep.new()
		var problem: String = AcceptanceStepParser.parse(raw_steps[index], field, step)
		if problem == "" and _has_id(suite, step.id):
			problem = "%s.id: '%s' is used by an earlier step" % [field, step.id]
		if problem != "":
			return problem
		suite.steps.append(step)
	return ""


## Appends the steps of every part `suite` includes, read from `suites_dir`, in
## the listed order. Why one could not be read, naming its file, or "".
static func add_parts(suite: AcceptanceSuite, suites_dir: String) -> String:
	for part: String in suite.includes:
		var path: String = suites_dir.path_join(part + AcceptanceSuite.SUITE_EXTENSION)
		var problem: String = _add_part(suite, path)
		if problem != "":
			return "%s %s: %s: %s" % [INCLUDE_KEY, part, path, problem]
	return ""


static func _add_part(suite: AcceptanceSuite, path: String) -> String:
	if not FileAccess.file_exists(path):
		return "cannot open the part"
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]
	if typeof(json.data) != TYPE_DICTIONARY:
		return "top level must be a JSON object"
	var data: Dictionary = json.data
	var problem: String = AcceptanceStepParser.unknown_key(data, PART_KEYS, "")
	if problem != "":
		return problem
	if typeof(data.get("steps")) != TYPE_ARRAY:
		return "steps: must be a list of steps, empty for none yet"
	return add_steps(data["steps"], suite)


static func _has_id(suite: AcceptanceSuite, id: String) -> bool:
	for step: AcceptanceStep in suite.steps:
		if step.id == id:
			return true
	return false
