class_name EscapeCueLook
extends RefCounted

## Parses `res://view/escape_cue_look.json`, the look and timing of the
## meltdown's escape cues (#617, RUN-2, RUN-5, MAP-2, ARC-4): the large
## countdown and its line in the cockpit, the arrow toward the next waypoint
## and the sign at the exit.
##
##     {"first_show_seconds": 1..30, "warning_seconds": 5..600,
##      "line_text": "...", "countdown_position_m": [x, y, z],
##      "line_position_m": [x, y, z], "arrow_position_m": [x, y, z],
##      "countdown_font_size": 48..256, "line_font_size": 16..128,
##      "pixel_size": 0.0001..0.002, "arrow_length_m": 0.02..0.2,
##      "text_color": [r, g, b], "warning_color": [r, g, b],
##      "arrow_color": [r, g, b], "exit_text": "...", "exit_color": [r, g, b],
##      "exit_ring_radius_m": 0.5..10, "exit_ring_thickness_m": 0.02..1,
##      "exit_text_height_m": 0.2..3}
##
## Positions are in the cockpit's space from the eye point: x right, y up and
## z forward as -z. Each must sit in front of the eye, within reach of the
## cockpit, so a typo cannot put a cue behind the head or inside it.

const DEFAULT_FILE: String = "res://view/escape_cue_look.json"

const COLOR_KEYS: Array[String] = ["text_color", "warning_color", "arrow_color", "exit_color"]
const POSITION_KEYS: Array[String] = ["countdown_position_m", "line_position_m", "arrow_position_m"]
const TEXT_KEYS: Array[String] = ["line_text", "exit_text"]
## Inclusive ranges of the number keys.
const RANGES: Dictionary[String, Array] = {
	"first_show_seconds": [1.0, 30.0],
	"warning_seconds": [5.0, 600.0],
	"countdown_font_size": [48.0, 256.0],
	"line_font_size": [16.0, 128.0],
	"pixel_size": [0.0001, 0.002],
	"arrow_length_m": [0.02, 0.2],
	"exit_ring_radius_m": [0.5, 10.0],
	"exit_ring_thickness_m": [0.02, 1.0],
	"exit_text_height_m": [0.2, 3.0],
}
## Sideways and up or down, a cue stays within this of the eye.
const SIDE_LIMIT_M: float = 0.5
## Forward, a cue sits between these distances: nearer is uncomfortable to
## focus on, farther passes through the cockpit's glass.
const NEAR_M: float = 0.3
const FAR_M: float = 1.5

## Look used when the file is missing or rejected; matches the shipped file.
const FALLBACK: Dictionary = {
	"first_show_seconds": 5.0,
	"warning_seconds": 30.0,
	"line_text": "Escape through the entrance",
	"countdown_position_m": Vector3(0.0, 0.12, -0.75),
	"line_position_m": Vector3(0.0, 0.065, -0.75),
	"arrow_position_m": Vector3(0.0, -0.06, -0.55),
	"countdown_font_size": 160.0,
	"line_font_size": 48.0,
	"pixel_size": 0.0004,
	"arrow_length_m": 0.07,
	"text_color": Color(0.85, 0.95, 1.0),
	"warning_color": Color(1.0, 0.2, 0.15),
	"arrow_color": Color(0.35, 1.0, 0.45),
	"exit_text": "EXIT",
	"exit_color": Color(0.35, 1.0, 0.45),
	"exit_ring_radius_m": 2.0,
	"exit_ring_thickness_m": 0.08,
	"exit_text_height_m": 0.8,
}

static var _shared: Dictionary = {}


## The shipped look, read once; the fallback when the file is missing or
## rejected, with the reason pushed as a warning.
static func shared() -> Dictionary:
	if _shared.is_empty():
		_shared = load_file(DEFAULT_FILE)
	return _shared


## The look in `path`, or `FALLBACK` when it is missing or rejected.
static func load_file(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("%s missing, using the built-in escape cue look" % path)
		return FALLBACK
	var look: Dictionary = parse(file.get_as_text())
	if look.has("error"):
		push_warning("%s rejected: %s" % [path, look["error"]])
		return FALLBACK
	return look


## Returns the look with colours as `Color`, positions as `Vector3` and
## numbers as floats, or a dictionary holding only `"error"`, which names the
## field.
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
	for key: String in COLOR_KEYS:
		var parts: Array = _three_numbers(data[key])
		if parts.is_empty():
			return _rejected("\"%s\" must be [red, green, blue]" % key)
		for part: float in parts:
			if part < 0.0 or part > 1.0:
				return _rejected("\"%s\" has %s, must be within 0..1" % [key, part])
		look[key] = Color(parts[0], parts[1], parts[2])
	for key: String in POSITION_KEYS:
		var parts: Array = _three_numbers(data[key])
		if parts.is_empty():
			return _rejected("\"%s\" must be [x, y, z]" % key)
		if absf(parts[0]) > SIDE_LIMIT_M or absf(parts[1]) > SIDE_LIMIT_M \
				or -parts[2] < NEAR_M or -parts[2] > FAR_M:
			return _rejected("\"%s\" must be within %s m to the side and %s..%s m in front" % [
				key, SIDE_LIMIT_M, NEAR_M, FAR_M])
		look[key] = Vector3(parts[0], parts[1], parts[2])
	for key: String in TEXT_KEYS:
		if typeof(data[key]) != TYPE_STRING or (data[key] as String).strip_edges() == "":
			return _rejected("\"%s\" must be a text that is not empty" % key)
		look[key] = data[key]
	for key: String in RANGES:
		var value: Variant = data[key]
		# A bool must not pass as 0 or 1.
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return _rejected("\"%s\" must be a number" % key)
		var bounds: Array = RANGES[key]
		if float(value) < float(bounds[0]) or float(value) > float(bounds[1]):
			return _rejected("\"%s\" is %s, must be within %s..%s" % [key, value, bounds[0], bounds[1]])
		look[key] = float(value)
	return look


## `value` as three floats, or empty when it is not an array of three numbers.
static func _three_numbers(value: Variant) -> Array:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 3:
		return []
	var result: Array = []
	for part: Variant in value:
		if typeof(part) != TYPE_FLOAT and typeof(part) != TYPE_INT:
			return []
		result.append(float(part))
	return result


static func _rejected(message: String) -> Dictionary:
	return {"error": message}
