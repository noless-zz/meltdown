class_name EscapeScreenLook
extends RefCounted

## Parses `res://xr/escape_screen.json`, the words, colours, placement and
## times of the end screen an escape shows (#751, RUN-3, RUN-7, ARC-4), beside
## the destroyed ship's `destroyed_screen.json`:
##
##     {"fade_seconds": 0..10, "hold_seconds": 0..30,
##      "line_text": "...", "time_text": "... {time} ...",
##      "prompt_xr": "...", "prompt_flat": "...",
##      "line_color": [r, g, b], "time_color": [r, g, b], "prompt_color": [r, g, b],
##      "line_position_m": [x, y, z], "time_position_m": [x, y, z],
##      "prompt_position_m": [x, y, z],
##      "line_font_size": 16..256, "time_font_size": 16..256,
##      "prompt_font_size": 16..256, "pixel_size": 0.0001..0.002}
##
## `{time}` in `time_text` is replaced by the meltdown time left as `m:ss`.
## Positions are from the eye point, x right, y up and forward as -z, and must
## lie in front of the eye so a typo cannot put the words behind the head.

const DEFAULT_FILE: String = "res://xr/escape_screen.json"
const TIME_MARK: String = "{time}"

const COLOR_KEYS: Array[String] = ["line_color", "time_color", "prompt_color"]
const POSITION_KEYS: Array[String] = ["line_position_m", "time_position_m", "prompt_position_m"]
const TEXT_KEYS: Array[String] = ["line_text", "run_won_text", "time_text", "prompt_xr", "prompt_flat"]
## Inclusive ranges of the number keys. The two times share the destroyed
## screen's ranges (`DestroyedSequence.RANGES`), as they drive the same sequence.
const RANGES: Dictionary[String, Array] = {
	"fade_seconds": [0.0, 10.0],
	"hold_seconds": [0.0, 30.0],
	"line_font_size": [16.0, 256.0],
	"time_font_size": [16.0, 256.0],
	"prompt_font_size": [16.0, 256.0],
	"pixel_size": [0.0001, 0.002],
}
const SIDE_LIMIT_M: float = 0.5
const NEAR_M: float = 0.5
const FAR_M: float = 3.0

## Used when the file is missing or rejected; matches the shipped file.
const FALLBACK: Dictionary = {
	"fade_seconds": 1.0,
	"hold_seconds": 3.0,
	"line_text": "ESCAPED",
	## In place of `line_text` when the escape was a run's last level (#989).
	"run_won_text": "RUN WON",
	"time_text": "{time} left",
	"prompt_xr": "Press A to fly again",
	"prompt_flat": "Press Enter to fly again",
	"line_color": Color(0.35, 1.0, 0.45),
	"time_color": Color(0.85, 0.95, 1.0),
	"prompt_color": Color(0.85, 0.95, 1.0),
	"line_position_m": Vector3(0.0, 0.1, -1.5),
	"time_position_m": Vector3(0.0, -0.01, -1.5),
	"prompt_position_m": Vector3(0.0, -0.11, -1.5),
	"line_font_size": 96.0,
	"time_font_size": 64.0,
	"prompt_font_size": 48.0,
	"pixel_size": 0.001,
}


## The look in `path`, or `FALLBACK` when it is missing or rejected, with the
## reason pushed as a warning naming the field.
static func load_file(path: String = DEFAULT_FILE) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("The escape screen uses built-in words; %s: file not found" % path)
		return FALLBACK
	var look: Dictionary = parse(FileAccess.get_file_as_string(path))
	if look.has("error"):
		push_warning("The escape screen uses built-in words; %s: %s" % [path, look["error"]])
		return FALLBACK
	return look


## `seconds` of meltdown left as `m:ss`, whole seconds rounded down like the
## cockpit countdown (`MeltdownCue`), so the screen repeats the last second
## the pilot saw. Below zero reads as `0:00`.
static func clock_text(seconds: float) -> String:
	var whole: int = maxi(floori(seconds), 0)
	return "%d:%02d" % [floori(whole / 60.0), whole % 60]


## The time line for `seconds` left with `look`'s template.
static func time_line(look: Dictionary, seconds: float) -> String:
	return (look["time_text"] as String).replace(TIME_MARK, clock_text(seconds))


## The fade and hold times as `DestroyedSequence` takes them.
static func times(look: Dictionary) -> Dictionary:
	return {"fade_seconds": look["fade_seconds"], "hold_seconds": look["hold_seconds"]}


## Returns the look with colours as `Color`, positions as `Vector3` and
## numbers as floats, or a dictionary holding only `"error"`, which names the
## field.
static func parse(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return {"error": "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]}
	if typeof(json.data) != TYPE_DICTIONARY:
		return {"error": "top level must be a JSON object"}
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not FALLBACK.has(key):
			return {"error": "unknown key \"%s\"" % str(key)}
	for key: String in FALLBACK:
		if not data.has(key):
			return {"error": "missing key \"%s\"" % key}
	var look: Dictionary = {}
	for key: String in COLOR_KEYS:
		var parts: Array = _three_numbers(data[key])
		if parts.is_empty() or parts.min() < 0.0 or parts.max() > 1.0:
			return {"error": "\"%s\" must be [red, green, blue], each within 0..1" % key}
		look[key] = Color(parts[0], parts[1], parts[2])
	for key: String in POSITION_KEYS:
		var parts: Array = _three_numbers(data[key])
		if parts.is_empty() or absf(parts[0]) > SIDE_LIMIT_M or absf(parts[1]) > SIDE_LIMIT_M \
				or -parts[2] < NEAR_M or -parts[2] > FAR_M:
			return {"error": "\"%s\" must be [x, y, z] within %s m to the side and %s..%s m in front" % [
				key, SIDE_LIMIT_M, NEAR_M, FAR_M]}
		look[key] = Vector3(parts[0], parts[1], parts[2])
	for key: String in TEXT_KEYS:
		if typeof(data[key]) != TYPE_STRING or (data[key] as String).strip_edges() == "":
			return {"error": "\"%s\" must be a text that is not empty" % key}
		look[key] = data[key]
	if not (look["time_text"] as String).contains(TIME_MARK):
		return {"error": "\"time_text\" must contain %s" % TIME_MARK}
	for key: String in RANGES:
		var value: Variant = data[key]
		# A bool must not pass as 0 or 1.
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return {"error": "\"%s\" must be a number" % key}
		var bounds: Array = RANGES[key]
		if float(value) < float(bounds[0]) or float(value) > float(bounds[1]):
			return {"error": "\"%s\" is %s, must be within %s..%s" % [key, value, bounds[0], bounds[1]]}
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
