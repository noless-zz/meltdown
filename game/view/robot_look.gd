class_name RobotLook
extends RefCounted

## Parses `res://view/robot_look.json`, how each robot type is drawn (CMB-3,
## ARC-4). Kept apart from `RobotView` so the node stays small.
##
##     {"default": <entry>, "robots": {<id>: <entry>, ...}, "effects": <effects>}
##
## An entry needs `shape`, `scale` and `emission_color`, and may add:
## - `stretch`: [x, y, z], the body's proportions, so a type is not just a
##   primitive (default [1, 1, 1]);
## - `parts`: extra pieces `{"shape", "size": [x, y, z], "offset": [x, y, z],
##   "eye": bool}` in units of the robot's drawn size, for a silhouette that
##   reads at 20 m. An eye part is lit only while the robot is awake;
## - `eye_color`: [r, g, b] of the eye parts;
## - `tell`: `{"pitch_deg_per_mps", "roll_deg_per_mps", "max_deg"}`, how far
##   the drawn body leans with its velocity: nose down when it closes (a
##   chaser) and banked into a sideways move (a strafer). Optional
##   `yaw_deg_per_mps` turns the body into a sideways move instead, so it
##   skids flat (#638), and `watch_dim` (0..1) dims the eye by that much while
##   the robot has no line to its target. See `RobotTells`;
## - `skin`: its surface pattern, accent colour and face plate (#661), see
##   `RobotSkin`. Without one the body is plain.
## `effects` is optional; missing keys keep `DEFAULT_EFFECTS`.

const SHAPES: Array[String] = ["sphere", "box", "capsule", "prism", "cylinder", "cone", "torus"]
const ENTRY_KEYS: Array[String] = ["shape", "scale", "emission_color"]
const OPTIONAL_ENTRY_KEYS: Array[String] = ["stretch", "parts", "eye_color", "tell", "skin"]
const TOP_KEYS: Array[String] = ["default", "robots"]
const OPTIONAL_TOP_KEYS: Array[String] = ["effects"]
const PART_KEYS: Array[String] = ["shape", "size", "offset"]
const TELL_KEYS: Array[String] = ["pitch_deg_per_mps", "roll_deg_per_mps", "max_deg"]
const OPTIONAL_TELL_KEYS: Array[String] = ["yaw_deg_per_mps", "watch_dim"]
## Size relative to the robot's collision radius, inclusive.
const SCALE_RANGE: Array[float] = [0.1, 4.0]
const STRETCH_RANGE: Array[float] = [0.1, 4.0]
const PART_SIZE_RANGE: Array[float] = [0.02, 4.0]
const PART_OFFSET_RANGE: Array[float] = [-4.0, 4.0]
const MAX_PARTS: int = 8
const TELL_RANGES: Dictionary[String, Array] = {
	"pitch_deg_per_mps": [0.0, 10.0],
	"roll_deg_per_mps": [0.0, 10.0],
	"max_deg": [0.0, 60.0],
	"yaw_deg_per_mps": [0.0, 10.0],
	"watch_dim": [0.0, 1.0],
}
const EFFECT_COLOR_KEYS: Array[String] = ["hit_flash_color", "burst_color"]
const EFFECT_RANGES: Dictionary[String, Array] = {
	"hit_flash_seconds": [0.03, 0.5],
	"damaged_below": [0.0, 1.0],
	"damaged_brightness": [0.0, 1.0],
	# Under three sputters a second, as the reactor's flicker (CMF-3).
	"damaged_flicker_period": [0.34, 10.0],
	"damaged_flicker_depth": [0.0, 1.0],
	"burst_seconds": [0.1, 3.0],
	"burst_radii": [1.0, 10.0],
	"windup_energy": [0.0, 8.0],
}
const DEFAULT_EFFECTS: Dictionary = {
	"hit_flash_seconds": 0.12,
	"hit_flash_color": Color(1.0, 1.0, 1.0),
	"damaged_below": 0.5,
	"damaged_brightness": 0.45,
	"damaged_flicker_period": 0.6,
	"damaged_flicker_depth": 0.6,
	"burst_seconds": 0.7,
	"burst_radii": 3.5,
	"burst_color": Color(1.0, 0.75, 0.35),
	"windup_energy": 2.5,
}
const NO_TELL: Dictionary = {
	"pitch_deg_per_mps": 0.0, "roll_deg_per_mps": 0.0, "max_deg": 0.0,
	"yaw_deg_per_mps": 0.0, "watch_dim": 0.0,
}
const FALLBACK: Dictionary = {
	"shape": "sphere", "scale": 1.0, "emission_color": Color(0.8, 0.8, 0.8),
	"stretch": Vector3.ONE, "parts": [], "eye_color": Color(1.0, 1.0, 1.0), "tell": NO_TELL,
	"skin": RobotSkin.PLAIN,
}


## Returns `{"default": <look>, "robots": {<id>: <look>}, "effects": {...}}`
## with colours as `Color` and vectors as `Vector3`, or a dictionary holding
## only `"error"`, which names the field.
static func parse(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not (TOP_KEYS.has(key) or OPTIONAL_TOP_KEYS.has(key)):
			return _rejected("unknown key \"%s\"" % str(key))
	for key: String in TOP_KEYS:
		if not data.has(key):
			return _rejected("missing key \"%s\"" % key)
	var default_look: Dictionary = _parse_entry("default", data["default"])
	if default_look.has("error"):
		return default_look
	if typeof(data["robots"]) != TYPE_DICTIONARY:
		return _rejected("key \"robots\" must be an object of robot id to look")
	var robots: Dictionary = {}
	var given: Dictionary = data["robots"]
	for id: Variant in given:
		var look: Dictionary = _parse_entry("robots.%s" % str(id), given[id])
		if look.has("error"):
			return look
		robots[str(id)] = look
	var effects: Dictionary = _parse_effects(data.get("effects", {}))
	if effects.has("error"):
		return effects
	return {"default": default_look, "robots": robots, "effects": effects}


static func _parse_entry(field: String, entry: Variant) -> Dictionary:
	if typeof(entry) != TYPE_DICTIONARY:
		return _rejected("\"%s\" must be an object" % field)
	var data: Dictionary = entry
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not (ENTRY_KEYS.has(key) or OPTIONAL_ENTRY_KEYS.has(key)):
			return _rejected("\"%s\" has unknown key \"%s\"" % [field, str(key)])
	for key: String in ENTRY_KEYS:
		if not data.has(key):
			return _rejected("\"%s\" is missing key \"%s\"" % [field, key])
	var look: Dictionary = FALLBACK.duplicate(true)
	var error: String = _shape(field + ".shape", data["shape"])
	if error == "":
		error = _number(field + ".scale", data["scale"], SCALE_RANGE)
	if error == "":
		error = _color(field + ".emission_color", data["emission_color"])
	if error == "" and data.has("stretch"):
		error = _vector(field + ".stretch", data["stretch"], STRETCH_RANGE)
	if error == "" and data.has("eye_color"):
		error = _color(field + ".eye_color", data["eye_color"])
	if error != "":
		return _rejected(error)
	look["shape"] = data["shape"]
	look["scale"] = float(data["scale"])
	look["emission_color"] = _to_color(data["emission_color"])
	if data.has("stretch"):
		look["stretch"] = _to_vector(data["stretch"])
	if data.has("eye_color"):
		look["eye_color"] = _to_color(data["eye_color"])
	if data.has("parts"):
		var parts: Variant = _parse_parts(field + ".parts", data["parts"])
		if typeof(parts) == TYPE_STRING:
			return _rejected(parts)
		look["parts"] = parts
	if data.has("tell"):
		var tell: Dictionary = _parse_numbers(field + ".tell", data["tell"], TELL_RANGES, TELL_KEYS)
		if tell.has("error"):
			return tell
		look["tell"] = NO_TELL.merged(tell, true)
	if data.has("skin"):
		var skin: Dictionary = RobotSkin.parse(field + ".skin", data["skin"])
		if skin.has("error"):
			return skin
		look["skin"] = skin
	return look


## The parts as dictionaries, or a String naming the bad field.
static func _parse_parts(field: String, value: Variant) -> Variant:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() > MAX_PARTS:
		return "\"%s\" must be an array of at most %d parts" % [field, MAX_PARTS]
	var parts: Array[Dictionary] = []
	var given: Array = value
	for index: int in given.size():
		var name: String = "%s.%d" % [field, index]
		if typeof(given[index]) != TYPE_DICTIONARY:
			return "\"%s\" must be an object" % name
		var part: Dictionary = given[index]
		for key: Variant in part:
			if typeof(key) != TYPE_STRING or not (PART_KEYS.has(key) or key == "eye"):
				return "\"%s\" has unknown key \"%s\"" % [name, str(key)]
		for key: String in PART_KEYS:
			if not part.has(key):
				return "\"%s\" is missing key \"%s\"" % [name, key]
		var error: String = _shape(name + ".shape", part["shape"])
		if error == "":
			error = _vector(name + ".size", part["size"], PART_SIZE_RANGE)
		if error == "":
			error = _vector(name + ".offset", part["offset"], PART_OFFSET_RANGE)
		if error == "" and part.has("eye") and typeof(part["eye"]) != TYPE_BOOL:
			error = "\"%s.eye\" must be true or false" % name
		if error != "":
			return error
		parts.append({"shape": part["shape"], "size": _to_vector(part["size"]),
			"offset": _to_vector(part["offset"]), "eye": part.get("eye", false)})
	return parts


static func _parse_effects(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _rejected("\"effects\" must be an object")
	var data: Dictionary = value
	var effects: Dictionary = DEFAULT_EFFECTS.duplicate()
	var numbers: Dictionary = {}
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not effects.has(key):
			return _rejected("\"effects\" has unknown key \"%s\"" % str(key))
		if EFFECT_COLOR_KEYS.has(key):
			var error: String = _color("effects." + key, data[key])
			if error != "":
				return _rejected(error)
			effects[key] = _to_color(data[key])
		else:
			numbers[key] = data[key]
	var parsed: Dictionary = _parse_numbers("effects", numbers, EFFECT_RANGES, [])
	if parsed.has("error"):
		return parsed
	effects.merge(parsed, true)
	return effects


## Numbers of `value` checked against `ranges`; every key in `required` is needed.
static func _parse_numbers(field: String, value: Variant, ranges: Dictionary, required: Array[String]) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _rejected("\"%s\" must be an object" % field)
	var data: Dictionary = value
	var out: Dictionary = {}
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not ranges.has(key):
			return _rejected("\"%s\" has unknown key \"%s\"" % [field, str(key)])
		var error: String = _number("%s.%s" % [field, key], data[key], ranges[key])
		if error != "":
			return _rejected(error)
		out[key] = float(data[key])
	for key: String in required:
		if not out.has(key):
			return _rejected("\"%s\" is missing key \"%s\"" % [field, key])
	return out


static func _shape(field: String, value: Variant) -> String:
	if typeof(value) != TYPE_STRING or not SHAPES.has(value):
		return "\"%s\" is %s, must be one of %s" % [field, JSON.stringify(value), ", ".join(PackedStringArray(SHAPES))]
	return ""


static func _number(field: String, value: Variant, limits: Array) -> String:
	# A bool must not pass as 0 or 1.
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return "\"%s\" must be a number" % field
	if float(value) < float(limits[0]) or float(value) > float(limits[1]):
		return "\"%s\" is %s, must be within %s..%s" % [field, value, limits[0], limits[1]]
	return ""


static func _vector(field: String, value: Variant, limits: Array) -> String:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 3:
		return "\"%s\" must be [x, y, z]" % field
	for part: Variant in value:
		var error: String = _number(field, part, limits)
		if error != "":
			return error
	return ""


static func _color(field: String, value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 3:
		return "\"%s\" must be [red, green, blue]" % field
	for part: Variant in value:
		if typeof(part) != TYPE_FLOAT and typeof(part) != TYPE_INT:
			return "\"%s\" must hold numbers" % field
		if float(part) < 0.0 or float(part) > 1.0:
			return "\"%s\" has %s, must be within 0..1" % [field, part]
	return ""


static func _to_color(value: Array) -> Color:
	return Color(float(value[0]), float(value[1]), float(value[2]))


static func _to_vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


static func _rejected(message: String) -> Dictionary:
	return {"error": message}
