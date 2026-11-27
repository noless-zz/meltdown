class_name AimRaySpec
extends RefCounted

## How the aim ray looks (#1451, CRW-2, RUN-1, ARC-4): its width, colour,
## length with nothing hit, and the dot where it lands. Read from
## `res://xr/aim_ray.json` so the owner can change them after a headset session.
## A rejected file names its field and leaves the built-in values, so the ray
## still shows.

const DEFAULT_FILE: String = "res://xr/aim_ray.json"
## Number keys and their allowed range, inclusive.
const RANGES: Dictionary[String, Array] = {
	"width_m": [0.001, 0.02],
	"length_m": [0.2, 5.0],
	"dot_size_m": [0.005, 0.08],
}
## Colour keys: `[r, g, b, a]`, each 0..1.
const COLOR_KEYS: Array[String] = ["color", "dot_color"]

## The ray's thickness, metres.
var width_m: float = 0.004
## How far the ray reaches when it points at nothing; it fades out to its tip.
var length_m: float = 1.5
## The dot's diameter where the ray lands, metres.
var dot_size_m: float = 0.02
var color: Color = Color(0.55, 0.85, 1.0, 0.7)
var dot_color: Color = Color(0.9, 0.97, 1.0, 0.95)
## Set when the file was rejected; empty otherwise.
var error: String = ""


## Parses one JSON object holding every key once and nothing else. On failure
## `error` names the field and every value is the built-in one.
static func parse_json(text: String) -> AimRaySpec:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not (RANGES.has(key) or COLOR_KEYS.has(key)):
			return _rejected("unknown key \"%s\"" % str(key))
	var spec: AimRaySpec = AimRaySpec.new()
	for key: String in RANGES:
		if not data.has(key):
			return _rejected("missing key \"%s\"" % key)
		var value: Variant = data[key]
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return _rejected("key \"%s\" must be a number" % key)
		if float(value) < float(RANGES[key][0]) or float(value) > float(RANGES[key][1]):
			return _rejected("key \"%s\" is %s, must be within %s..%s" % [key, value, RANGES[key][0], RANGES[key][1]])
		spec.set(key, float(value))
	for key: String in COLOR_KEYS:
		if not data.has(key):
			return _rejected("missing key \"%s\"" % key)
		var parsed: Variant = _color(data[key])
		if parsed == null:
			return _rejected("key \"%s\" must be [r, g, b, a], each 0..1" % key)
		spec.set(key, parsed)
	return spec


## Reads and parses `path`; a missing file is rejected like bad text.
static func load_file(path: String = DEFAULT_FILE) -> AimRaySpec:
	if not FileAccess.file_exists(path):
		return _rejected("file %s not found" % path)
	var spec: AimRaySpec = parse_json(FileAccess.get_file_as_string(path))
	if spec.error != "":
		spec.error = "%s: %s" % [path, spec.error]
	return spec


static func _color(value: Variant) -> Variant:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 4:
		return null
	var parts: Array[float] = []
	for part: Variant in value:
		if typeof(part) != TYPE_FLOAT and typeof(part) != TYPE_INT:
			return null
		if float(part) < 0.0 or float(part) > 1.0:
			return null
		parts.append(float(part))
	return Color(parts[0], parts[1], parts[2], parts[3])


static func _rejected(message: String) -> AimRaySpec:
	var spec: AimRaySpec = AimRaySpec.new()
	spec.error = message
	return spec
