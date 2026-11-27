class_name Checklist
extends RefCounted

## An in-game test checklist (#1325, DEV-6, DEV-7, ARC-4): one data file per
## gate or headset session under `res://data/checklists/`, shipped with the
## build and shown on the development builds' checklist page. The `docs/`
## copy is generated from the same file (`ChecklistMarkdown`), so the two
## cannot drift.
##
##     {"id": "g6", "title": "Gate G6: look, sound, speed", "issue": 1304,
##      "remarks": ["too hard", "unclear", "looks wrong", "broken"],
##      "parts": [{"title": "Base", "steps": [
##          {"id": "base_room", "do": "Sit in the base.", "look_for": "A room, not the dark.",
##           "action": {"comfort": 1}, "remarks": ["too dark"]}]}]}
##
## `id` names the results file and each step's `id` names it there, so both are
## lower-case letters, digits and underscores, the step ids unique. `issue`
## (the gate issue the results go to) and a step's `remarks` and `action` are
## optional. An action has exactly one key: `comfort` (a preset, 1 to 4),
## `seed` (a whole number of at least 0), `level` (a `res://` level file that
## exists), `tunnel` (true) or `station` (a station id in the home base's
## `ROOM_FILE`, #1408). A rejected file names the field in `error`.

const DIR: String = "res://data/checklists"
## The home base room; a `station` action names one of its stations. Read as data only.
const ROOM_FILE: String = "res://data/hub/room.json"
const NAME_CHARACTERS: String = "abcdefghijklmnopqrstuvwxyz0123456789_"
const KEYS: Array[String] = ["id", "title", "issue", "remarks", "parts"]
const PART_KEYS: Array[String] = ["title", "steps"]
const STEP_KEYS: Array[String] = ["id", "do", "look_for", "remarks", "action"]
## The comfort presets a step may set; the custom mode is the pilot's own file.
const MAX_PRESET: int = 4

var id: String = ""
var title: String = ""
## The gate issue the results belong to; 0 when the file names none.
var issue: int = 0
## The remarks every step offers unless it lists its own.
var remarks: Array[String] = []
## Each part's title, in order.
var parts: Array[String] = []
## Every step, part by part, top to bottom.
var steps: Array[ChecklistStep] = []
## Why the file was rejected; empty when it was read.
var error: String = ""


## The checklist files shipped in `dir`, in name order.
static func files(dir: String = DIR) -> Array[String]:
	var found: Array[String] = []
	for file: String in ResourceLoader.list_directory(dir):
		if file.ends_with(".json"):
			found.append(dir.path_join(file))
	found.sort()
	return found


## Reads `path`; a missing file or a rejected one comes back with `error` set.
static func load_file(path: String) -> Checklist:
	if not FileAccess.file_exists(path):
		var missing: Checklist = Checklist.new()
		missing.error = "file not found"
		return missing
	return parse(FileAccess.get_file_as_string(path))


static func parse(text: String) -> Checklist:
	var checklist: Checklist = Checklist.new()
	var json: JSON = JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		checklist.error = "not a JSON object"
		return checklist
	checklist.error = checklist._read(json.data)
	if checklist.error != "":
		checklist.steps.clear()
	return checklist


func is_valid() -> bool:
	return error == "" and not steps.is_empty()


## The step with `step_id`, or null.
func step(step_id: String) -> ChecklistStep:
	for item: ChecklistStep in steps:
		if item.id == step_id:
			return item
	return null


func _read(data: Dictionary) -> String:
	var unknown: String = _unknown_key(data, KEYS)
	if unknown != "":
		return "unknown key \"%s\"" % unknown
	if not _is_name(data.get("id")):
		return "\"id\" must be lower-case letters, digits and underscores"
	id = data["id"]
	if not _is_text(data.get("title")):
		return "\"title\" must be a non-empty string"
	title = data["title"]
	if data.has("issue"):
		if not _is_whole(data["issue"], 1):
			return "\"issue\" must be a whole number of at least 1"
		issue = int(data["issue"])
	var problem: String = _read_remarks(data.get("remarks", []), remarks, "\"remarks\"")
	if problem != "":
		return problem
	if typeof(data.get("parts")) != TYPE_ARRAY or (data["parts"] as Array).is_empty():
		return "\"parts\" must be a non-empty list"
	for index: int in (data["parts"] as Array).size():
		problem = _read_part(data["parts"][index])
		if problem != "":
			return "part %d: %s" % [index + 1, problem]
	return ""


func _read_part(value: Variant) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "must be an object"
	var part: Dictionary = value
	var unknown: String = _unknown_key(part, PART_KEYS)
	if unknown != "":
		return "unknown key \"%s\"" % unknown
	if not _is_text(part.get("title")):
		return "\"title\" must be a non-empty string"
	if typeof(part.get("steps")) != TYPE_ARRAY or (part["steps"] as Array).is_empty():
		return "\"steps\" must be a non-empty list"
	parts.append(part["title"])
	for index: int in (part["steps"] as Array).size():
		var problem: String = _read_step(part["steps"][index])
		if problem != "":
			return "step %d: %s" % [index + 1, problem]
	return ""


func _read_step(value: Variant) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "must be an object"
	var data: Dictionary = value
	var unknown: String = _unknown_key(data, STEP_KEYS)
	if unknown != "":
		return "unknown key \"%s\"" % unknown
	if not _is_name(data.get("id")):
		return "\"id\" must be lower-case letters, digits and underscores"
	if step(data["id"]) != null:
		return "id \"%s\" given twice" % data["id"]
	for key: String in ["do", "look_for"]:
		if not _is_text(data.get(key)):
			return "\"%s\" must be a non-empty string" % key
	var made: ChecklistStep = ChecklistStep.new()
	made.id = data["id"]
	made.part = parts.size() - 1
	made.do_text = data["do"]
	made.look_for = data["look_for"]
	var problem: String = _read_remarks(data.get("remarks", []), made.remarks, "\"remarks\"")
	if problem == "" and made.remarks.is_empty():
		made.remarks = remarks.duplicate()
	if problem == "" and data.has("action"):
		problem = _read_action(data["action"], made)
	if problem == "":
		steps.append(made)
	return problem


static func _read_action(value: Variant, made: ChecklistStep) -> String:
	if typeof(value) != TYPE_DICTIONARY or (value as Dictionary).size() != 1:
		return "\"action\" must be an object with one of %s" % [ChecklistStep.ACTIONS]
	var kind: String = str((value as Dictionary).keys()[0])
	var given: Variant = (value as Dictionary)[kind]
	match kind:
		ChecklistStep.ACTION_COMFORT:
			if not _is_whole(given, 1) or int(given) > MAX_PRESET:
				return "\"comfort\" must be a preset from 1 to %d" % MAX_PRESET
			made.action_value = str(int(given))
		ChecklistStep.ACTION_SEED:
			if not _is_whole(given, 0):
				return "\"seed\" must be a whole number of at least 0"
			made.action_value = str(int(given))
		ChecklistStep.ACTION_LEVEL:
			if typeof(given) != TYPE_STRING or not (given as String).begins_with("res://") \
					or not FileAccess.file_exists(given):
				return "\"level\" must be a res:// level file that exists"
			made.action_value = given
		ChecklistStep.ACTION_TUNNEL:
			if typeof(given) != TYPE_BOOL or not bool(given):
				return "\"tunnel\" must be true"
		ChecklistStep.ACTION_STATION:
			var stations: Dictionary = station_labels()
			if typeof(given) != TYPE_STRING or not stations.has(given):
				return "\"station\" must be one of %s" % [stations.keys()]
			made.action_value = given
			made.action_label = stations[given]
		_:
			return "unknown action \"%s\"" % kind
	made.action = kind
	return ""


## The home base's station ids and their shown names, in the room file's order;
## empty when `room_file` cannot be read.
static func station_labels(room_file: String = ROOM_FILE) -> Dictionary:
	var labels: Dictionary = {}
	var room: Variant = JSON.parse_string(FileAccess.get_file_as_string(room_file)) \
		if FileAccess.file_exists(room_file) else null
	var listed: Variant = room.get("stations") if typeof(room) == TYPE_DICTIONARY else null
	for station: Variant in (listed if typeof(listed) == TYPE_ARRAY else []):
		if typeof(station) == TYPE_DICTIONARY and _is_name(station.get("id")):
			labels[station["id"]] = str(station.get("label", station["id"]))
	return labels


static func _read_remarks(value: Variant, into: Array[String], field: String) -> String:
	if typeof(value) != TYPE_ARRAY:
		return "%s must be a list of non-empty strings" % field
	for item: Variant in value:
		if not _is_text(item):
			return "%s must be a list of non-empty strings" % field
		into.append(item)
	return ""


static func _unknown_key(data: Dictionary, known: Array[String]) -> String:
	for key: Variant in data:
		if not known.has(str(key)):
			return str(key)
	return ""


static func _is_text(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and (value as String).strip_edges() != ""


static func _is_name(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or (value as String).is_empty():
		return false
	for character: String in (value as String):
		if not NAME_CHARACTERS.contains(character):
			return false
	return true


static func _is_whole(value: Variant, at_least: int) -> bool:
	return (value is int or value is float) and float(value) == float(int(value)) and int(value) >= at_least
