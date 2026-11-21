class_name GrippedControlsLook
extends RefCounted

## Parses the look of the gripped stick and throttle models (#740, PLT-5,
## ARC-4), `res://xr/gripped_controls_look.json`:
##
##     {"color": [r, g, b], "alpha": 0.05..1, "dimmed_alpha": 0..1,
##      "stick_length_m": 0.03..0.3, "stick_radius_m": 0.002..0.03,
##      "knob_radius_m": 0.005..0.05, "throttle_base_m": 0.01..0.2,
##      "throttle_handle_m": 0.01..0.1}
##
## Every key is required. `dimmed_alpha` is the alpha of a released control and
## must be below `alpha`, or letting go would not show.

const DEFAULT_FILE: String = "res://xr/gripped_controls_look.json"
const RANGES: Dictionary[String, Array] = {
	# Below 0.05 a held control vanishes in a dark mine.
	"alpha": [0.05, 1.0],
	"dimmed_alpha": [0.0, 1.0],
	"stick_length_m": [0.03, 0.3],
	"stick_radius_m": [0.002, 0.03],
	"knob_radius_m": [0.005, 0.05],
	"throttle_base_m": [0.01, 0.2],
	"throttle_handle_m": [0.01, 0.1],
}
const KEYS: Array[String] = ["color", "alpha", "dimmed_alpha", "stick_length_m", "stick_radius_m",
		"knob_radius_m", "throttle_base_m", "throttle_handle_m"]
## A muted grey-blue, half see-through, like the controller labels it sits
## beside: it must read without lighting yet not pull the eye from the tunnel.
const FALLBACK: Dictionary = {
	"color": Color(0.55, 0.6, 0.65),
	"alpha": 0.6,
	"dimmed_alpha": 0.25,
	"stick_length_m": 0.12,
	"stick_radius_m": 0.008,
	"knob_radius_m": 0.02,
	"throttle_base_m": 0.06,
	"throttle_handle_m": 0.035,
}


## The look with the colour as `Color` and numbers as floats, or a dictionary
## holding only `"error"`, which names the field.
static func parse(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not KEYS.has(key):
			return _rejected("unknown key \"%s\"" % str(key))
	for key: String in KEYS:
		if not data.has(key):
			return _rejected("missing key \"%s\"" % key)
	var look: Dictionary = {}
	var parts: Variant = data["color"]
	if typeof(parts) != TYPE_ARRAY or (parts as Array).size() != 3:
		return _rejected("\"color\" must be [red, green, blue]")
	for part: Variant in parts:
		if (typeof(part) != TYPE_FLOAT and typeof(part) != TYPE_INT) or float(part) < 0.0 or float(part) > 1.0:
			return _rejected("\"color\" must hold numbers within 0..1")
	look["color"] = Color(float(parts[0]), float(parts[1]), float(parts[2]))
	for key: String in RANGES:
		var value: Variant = data[key]
		# A bool must not pass as 0 or 1.
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return _rejected("\"%s\" must be a number" % key)
		var bounds: Array = RANGES[key]
		if float(value) < float(bounds[0]) or float(value) > float(bounds[1]):
			return _rejected("\"%s\" is %s, must be within %s..%s" % [key, value, bounds[0], bounds[1]])
		look[key] = float(value)
	if float(look["dimmed_alpha"]) >= float(look["alpha"]):
		return _rejected("\"dimmed_alpha\" %s must be below \"alpha\" %s" % [look["dimmed_alpha"], look["alpha"]])
	return look


## `{"look", "error"}`: the parsed look and "", or `FALLBACK` and an error
## naming the path and field, after pushing a warning.
static func load_file(path: String = DEFAULT_FILE) -> Dictionary:
	var values: Dictionary = {"error": "file not found"}
	if FileAccess.file_exists(path):
		values = parse(FileAccess.get_file_as_string(path))
	if not values.has("error"):
		return {"look": values, "error": ""}
	var error: String = "%s: %s" % [path, values["error"]]
	push_warning("GrippedControlsModel uses the built-in look; %s" % error)
	return {"look": FALLBACK, "error": error}


static func _rejected(message: String) -> Dictionary:
	return {"error": message}
