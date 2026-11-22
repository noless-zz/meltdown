class_name AimReticleLook
extends RefCounted

## Parses `res://view/aim_reticle_look.json`, the look of the aiming reticle
## (CMB-6, ARC-4, #923, #1211): how far ahead of the ship the ring floats along
## the gun direction, its size, its colour, the cone around the aim in which a
## robot within the active weapon's range draws the ring onto it, and how much
## of the colour's alpha the ring keeps while no robot is there.
##
##     {"distance_m": 5..200, "radius_m": 0.05..10, "thickness_m": 0.005..1,
##      "cone_degrees": 0.5..30, "dim_alpha": 0.05..1, "color": [r, g, b, a]}
##
## With no robot ahead the ring is drawn at a fixed distance rather than on the
## wall the guns point at, so it reads the same in an open cavern and a narrow
## tunnel.

const DEFAULT_FILE: String = "res://view/aim_reticle_look.json"

## Inclusive ranges of the number keys.
const RANGES: Dictionary[String, Array] = {
	"distance_m": [5.0, 200.0],
	"radius_m": [0.05, 10.0],
	"thickness_m": [0.005, 1.0],
	"cone_degrees": [0.5, 30.0],
	"dim_alpha": [0.05, 1.0],
}
const COLOR_KEY: String = "color"

## Look used when the file is missing or rejected; matches the shipped file.
const FALLBACK: Dictionary = {
	"distance_m": 25.0,
	"radius_m": 0.5,
	"thickness_m": 0.04,
	"cone_degrees": 4.0,
	"dim_alpha": 0.35,
	"color": Color(0.4, 1.0, 0.55, 0.85),
}


## The look in `path`, or `FALLBACK` when it is missing or rejected.
static func load_file(path: String = DEFAULT_FILE) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("%s missing, using the built-in aim reticle look" % path)
		return FALLBACK
	var look: Dictionary = parse(file.get_as_text())
	if look.has("error"):
		push_warning("%s rejected: %s" % [path, look["error"]])
		return FALLBACK
	return look


## Returns the look with the colour as `Color` and numbers as floats, or a
## dictionary holding only `"error"`, which names the key.
static func parse(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not FALLBACK.has(key):
			return _rejected("unknown key \"%s\"" % str(key))
	for key: String in FALLBACK:
		if not data.has(key):
			return _rejected("missing key \"%s\"" % key)
	var look: Dictionary = {}
	for key: String in RANGES:
		var value: Variant = data[key]
		# A bool must not pass as 0 or 1.
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return _rejected("\"%s\" must be a number" % key)
		var bounds: Array = RANGES[key]
		if float(value) < float(bounds[0]) or float(value) > float(bounds[1]):
			return _rejected("\"%s\" is %s, must be within %s..%s" % [key, value, bounds[0], bounds[1]])
		look[key] = float(value)
	if float(look["thickness_m"]) >= float(look["radius_m"]):
		return _rejected("\"thickness_m\" must be less than \"radius_m\"")
	var parts: Variant = data[COLOR_KEY]
	if typeof(parts) != TYPE_ARRAY or (parts as Array).size() != 4:
		return _rejected("\"color\" must be [red, green, blue, alpha]")
	for part: Variant in parts:
		if typeof(part) != TYPE_FLOAT and typeof(part) != TYPE_INT:
			return _rejected("\"color\" must be [red, green, blue, alpha]")
		if float(part) < 0.0 or float(part) > 1.0:
			return _rejected("\"color\" has %s, must be within 0..1" % part)
	look[COLOR_KEY] = Color(float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3]))
	return look


static func _rejected(reason: String) -> Dictionary:
	return {"error": reason}
