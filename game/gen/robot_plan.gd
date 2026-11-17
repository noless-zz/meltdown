class_name RobotPlan
extends RefCounted

## The robots a generated level gets (#378, GEN-1, CMB-3, ARC-4), read from
## `data/gen/robots.json`:
##
##     {"types": ["drone", "glider"], "min_per_level": 4, "max_per_level": 8,
##      "max_per_module": 2, "min_start_distance": 20, "min_reactor_distance": 8}
##
## `types` names robot files in `data/robots/`, each once. A level gets from
## `min_per_level` to `max_per_level` robots, at most `max_per_module` in any
## one module. Distances are metres from the level's start and from the
## reactor's centre, held as whole millimetres so placement is exact (ARC-2).
## The caller hands over the file's text and the robot files' text by id,
## because `gen/` never opens files; the robot files give each type's radius,
## which sets how much room a robot needs.

const KEYS: Array[String] = ["types", "min_per_level", "max_per_level", "max_per_module",
		"min_start_distance", "min_reactor_distance"]
## Furthest a distance key may be, metres: far beyond any level.
const MAX_DISTANCE_M: float = 10000.0

## Robot type ids in file order.
var types: Array[String] = []
## Each type's collision radius in millimetres, same order as `types`.
var radii_mm: Array[int] = []
var min_per_level: int = 0
var max_per_level: int = 0
var max_per_module: int = 1
var min_start_distance_mm: int = 0
var min_reactor_distance_mm: int = 0
## Set by `parse_json` when the text was rejected; empty otherwise.
var error: String = ""


## Parses the plan's text. `robot_texts` maps a robot id to its data file's
## text; a type missing from it, or whose file is rejected, is named.
static func parse_json(text: String, robot_texts: Dictionary) -> RobotPlan:
	var plan: RobotPlan = RobotPlan.new()
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		plan.error = "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]
		return plan
	if typeof(json.data) != TYPE_DICTIONARY:
		plan.error = "top level must be a JSON object"
		return plan
	plan.error = plan._read(json.data, robot_texts)
	if plan.error != "":
		plan.types.clear()
		plan.radii_mm.clear()
	return plan


## Each type's radius in millimetres by id, as `LevelValidator.validate` takes
## them for a generated level's unresolved robots.
func radii_by_id() -> Dictionary[String, int]:
	var radii: Dictionary[String, int] = {}
	for index: int in types.size():
		radii[types[index]] = radii_mm[index]
	return radii


func _read(data: Dictionary, robot_texts: Dictionary) -> String:
	var problem: String = LevelDef._check_keys(data, KEYS)
	if problem == "":
		problem = _read_types(data["types"], robot_texts)
	var counts: Array[int] = []
	for key: String in ["min_per_level", "max_per_level", "max_per_module"]:
		if problem == "":
			problem = _read_count(data[key], key, 1 if key == "max_per_module" else 0, counts)
	if problem != "":
		return problem
	min_per_level = counts[0]
	max_per_level = counts[1]
	max_per_module = counts[2]
	if max_per_level < min_per_level:
		return "max_per_level must not be below min_per_level"
	var distances: Array[int] = []
	for key: String in ["min_start_distance", "min_reactor_distance"]:
		problem = _read_distance(data[key], key, distances)
		if problem != "":
			return problem
	min_start_distance_mm = distances[0]
	min_reactor_distance_mm = distances[1]
	return ""


func _read_types(value: Variant, robot_texts: Dictionary) -> String:
	if typeof(value) != TYPE_ARRAY or (value as Array).is_empty():
		return "types must be a non-empty list of robot ids"
	for entry: Variant in value:
		if typeof(entry) != TYPE_STRING:
			return "types must be a non-empty list of robot ids"
		var id: String = entry
		if types.has(id):
			return "types: \"%s\" is listed twice" % id
		if not robot_texts.has(id):
			return "types: unknown robot \"%s\"" % id
		var def: RobotDef = RobotDef.parse_json(robot_texts[id])
		if def.error != "":
			return "types: robot \"%s\": %s" % [id, def.error]
		if def.id != id:
			return "types: robot \"%s\": its file says id \"%s\"" % [id, def.id]
		types.append(id)
		radii_mm.append(roundi(def.radius * RobotSpawn.SCALE))
	return ""


static func _read_count(value: Variant, key: String, least: int, into: Array[int]) -> String:
	# JSON numbers arrive as floats; a whole number is all that is accepted.
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT \
			or not is_finite(float(value)) or float(value) != floorf(float(value)) \
			or float(value) < float(least) or float(value) > 1000.0:
		return "%s must be a whole number from %d to 1000" % [key, least]
	into.append(int(value))
	return ""


static func _read_distance(value: Variant, key: String, into: Array[int]) -> String:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT \
			or not is_finite(float(value)) or float(value) < 0.0 or float(value) > MAX_DISTANCE_M:
		return "%s must be a number of metres from 0 to %s" % [key, MAX_DISTANCE_M]
	into.append(roundi(float(value) * RobotSpawn.SCALE))
	return ""
