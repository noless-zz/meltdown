class_name RobotPlan
extends RefCounted

## The robots a generated level gets (#378, GEN-1, CMB-3, ARC-4), read from
## `data/gen/robots.json`:
##
##     {"types": ["drone", "glider"], "min_per_level": 4, "max_per_level": 8,
##      "max_per_module": 2, "min_start_distance": 20, "min_reactor_distance": 8,
##      "near_start_distance": 40, "max_near_start": 2}
##
## `types` names robot files in `data/robots/`, each once. A level gets from
## `min_per_level` to `max_per_level` robots, at most `max_per_module` in any
## one module. Distances are metres from the level's start and from the
## reactor's centre, held as whole millimetres so placement is exact (ARC-2).
## The caller hands over the file's text and the robot files' text by id,
## because `gen/` never opens files; the robot files give each type's radius,
## which sets how much room a robot needs.
##
## `max_near_start` caps how many robots stand within `near_start_distance` of
## the start (#531, GEN-3), so a short level cannot open on an ambush; the
## owner tunes how busy the start is here, without code (ARC-4).
##
## A run's shaft can ask for a busier or quieter level with a robot scale
## (#991, RUN-1, GEN-2): `scaled(robot_scale, placements)` is a copy whose
## count range is `round(min_per_level * robot_scale)` to
## `round(max_per_level * robot_scale)`. The top is capped at `max_per_module`
## robots in every module but the start's, yet the cap never takes it below
## `max_per_level`, and the bottom never rises above the top; so a scale of
## 1.0 or more never gives a range below the file's, and 1.0 gives exactly the
## file's range and the same levels. The scale is a number from 0 to
## `MAX_ROBOT_SCALE`; anything else is an error on the copy.

const KEYS: Array[String] = ["types", "min_per_level", "max_per_level", "max_per_module",
		"min_start_distance", "min_reactor_distance", "near_start_distance", "max_near_start"]
## Furthest a distance key may be, metres: far beyond any level.
const MAX_DISTANCE_M: float = 10000.0
## Largest robot scale `scaled` accepts.
const MAX_ROBOT_SCALE: float = 10.0

## Robot type ids in file order.
var types: Array[String] = []
## Each type's collision radius in millimetres, same order as `types`.
var radii_mm: Array[int] = []
var min_per_level: int = 0
var max_per_level: int = 0
var max_per_module: int = 1
var min_start_distance_mm: int = 0
var min_reactor_distance_mm: int = 0
var near_start_distance_mm: int = 0
## Most robots allowed within `near_start_distance_mm` of the start.
var max_near_start: int = 0
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


## This plan with its robot count range scaled by `robot_scale` for a level of
## `placements` modules, as the class comment says. A bad scale gives a copy
## with `error` set and no types.
func scaled(robot_scale: float = 1.0, placements: int = 0) -> RobotPlan:
	var copy: RobotPlan = RobotPlan.new()
	copy.types = types.duplicate()
	copy.radii_mm = radii_mm.duplicate()
	copy.max_per_module = max_per_module
	copy.min_start_distance_mm = min_start_distance_mm
	copy.min_reactor_distance_mm = min_reactor_distance_mm
	copy.near_start_distance_mm = near_start_distance_mm
	copy.max_near_start = max_near_start
	copy.error = error
	if not is_finite(robot_scale) or robot_scale < 0.0 or robot_scale > MAX_ROBOT_SCALE:
		copy.error = "robot_scale must be a number from 0 to %s" % MAX_ROBOT_SCALE
	if copy.error != "":
		copy.types.clear()
		copy.radii_mm.clear()
		return copy
	var range_: Vector2i = count_range(robot_scale, placements)
	copy.min_per_level = range_.x
	copy.max_per_level = range_.y
	return copy


## The scaled robot count range, lowest in `x` and highest in `y`, for a valid
## `robot_scale` and a level of `placements` modules (0 when unknown: no cap).
func count_range(robot_scale: float, placements: int = 0) -> Vector2i:
	var high: int = roundi(max_per_level * robot_scale)
	if placements > 0:
		# Every module but the start's holds at most `max_per_module`.
		var room: int = max_per_module * maxi(placements - 1, 0)
		high = mini(high, maxi(room, max_per_level))
	var low: int = mini(roundi(min_per_level * robot_scale), high)
	return Vector2i(low, high)


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
	for key: String in ["min_start_distance", "min_reactor_distance", "near_start_distance"]:
		problem = _read_distance(data[key], key, distances)
		if problem != "":
			return problem
	min_start_distance_mm = distances[0]
	min_reactor_distance_mm = distances[1]
	near_start_distance_mm = distances[2]
	problem = _read_count(data["max_near_start"], "max_near_start", 0, counts)
	if problem != "":
		return problem
	max_near_start = counts[3]
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
