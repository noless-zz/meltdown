class_name RobotSpawnList
extends RefCounted

## The robots a level starts with, read from a level data file (ARC-4, CMB-3).
## Parsed like `RobotDef`: the caller reads the files and hands over their
## text, because core never opens files.
##
## The file is one JSON object with one key, `robots`, a list of entries:
##
##     {"robots": [
##         {"id": "drone", "position": [0.0, 0.5, -16.0], "facing": [0.0, 0.0, 1.0]}
##     ]}
##
## `id` names `res://data/robots/<id>.json`; `position` is metres in the
## simulation's space; `facing` is the direction the robot faces at spawn.

const TOP_KEYS: Array[String] = ["robots"]
const ENTRY_KEYS: Array[String] = ["id", "position", "facing"]

## In file order, with `def` null until `resolve` succeeds.
var spawns: Array[RobotSpawn] = []
## Set by `parse_json` when the text was rejected; empty otherwise.
var error: String = ""


## Parses the text of a level's spawn file. A missing or unknown key is an
## error, naming the entry, so a typo cannot drop a robot silently. On failure
## `error` is set and `spawns` is empty.
static func parse_json(text: String) -> RobotSpawnList:
	var list: RobotSpawnList = RobotSpawnList.new()
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _failed("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _failed("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if not TOP_KEYS.has(key):
			return _failed("unknown key \"%s\"" % str(key))
	if typeof(data.get("robots")) != TYPE_ARRAY:
		return _failed("key \"robots\" must be a list")
	var entries: Array = data["robots"]
	for index: int in entries.size():
		var problem: String = list._add_entry(entries[index])
		if problem != "":
			return _failed("robot %d: %s" % [index + 1, problem])
	return list


## Ids of the robot types the list names, each once, in first-use order.
func ids() -> Array[String]:
	var found: Array[String] = []
	for spawn: RobotSpawn in spawns:
		if not found.has(spawn.id):
			found.append(spawn.id)
	return found


## Gives every spawn its type from `texts`, robot data file text by id.
## Returns "" or the first problem; on a problem no spawn is resolved, so a
## level never starts with some of its robots missing.
func resolve(texts: Dictionary) -> String:
	var defs: Dictionary[String, RobotDef] = {}
	for id: String in ids():
		if not texts.has(id):
			return "robot \"%s\": data file not found" % id
		var def: RobotDef = RobotDef.parse_json(texts[id])
		if def.error != "":
			return "robot \"%s\": %s" % [id, def.error]
		if def.id != id:
			return "robot \"%s\": its file says id \"%s\"" % [id, def.id]
		defs[id] = def
	for spawn: RobotSpawn in spawns:
		spawn.def = defs[spawn.id]
	return ""


func _add_entry(entry: Variant) -> String:
	if typeof(entry) != TYPE_DICTIONARY:
		return "must be a JSON object"
	var data: Dictionary = entry
	for key: Variant in data:
		if not ENTRY_KEYS.has(key):
			return "unknown key \"%s\"" % str(key)
	for key: String in ENTRY_KEYS:
		if not data.has(key):
			return "missing key \"%s\"" % key
	if typeof(data["id"]) != TYPE_STRING:
		return "\"id\" must be a string"
	var id_problem: String = ShipLoadout.check_id("id", data["id"])
	if id_problem != "":
		return id_problem
	var read: Array[Vector3i] = []
	var problem: String = RobotSpawn.read_mm(data["position"], "position", read)
	if problem == "":
		problem = RobotSpawn.read_mm(data["facing"], "facing", read)
	if problem != "":
		return problem
	if read[1] == Vector3i.ZERO:
		return "facing must not be zero"
	var spawn: RobotSpawn = RobotSpawn.new(null, read[0], read[1])
	spawn.id = data["id"]
	spawns.append(spawn)
	return ""


static func _failed(message: String) -> RobotSpawnList:
	var list: RobotSpawnList = RobotSpawnList.new()
	list.error = message
	return list
