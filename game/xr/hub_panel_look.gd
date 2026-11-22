class_name HubPanelLook
extends RefCounted

## Parses `res://xr/hub_panel.json`, the size, colours and placement of the hub
## panel (#1071, CRW-2, ARC-4):
##
##     {"mark_text": "...",
##      "title_color": [r, g, b], "text_color": [r, g, b],
##      "selected_color": [r, g, b], "reason_color": [r, g, b],
##      "title_position_m": [x, y, z], "line_step_m": 0.03..0.3,
##      "title_font_size": 16..256, "line_font_size": 16..256,
##      "reason_font_size": 16..256, "pixel_size": 0.0001..0.002}
##
## The page title sits at `title_position_m` (from the eye point, forward as
## -z); each row, and then a refused press's reason, sits `line_step_m` lower
## than the line above. `mark_text` goes before the selected row. Every other
## word on the panel comes from the hub's own data file through the hub text.

const DEFAULT_FILE: String = "res://xr/hub_panel.json"
const COLOR_KEYS: Array[String] = ["title_color", "text_color", "selected_color", "reason_color"]
const RANGES: Dictionary[String, Array] = {
	"line_step_m": [0.03, 0.3],
	"title_font_size": [16.0, 256.0],
	"line_font_size": [16.0, 256.0],
	"reason_font_size": [16.0, 256.0],
	"pixel_size": [0.0001, 0.002],
}
const SIDE_LIMIT_M: float = 0.5
## Nearer than half a metre is hard to focus on; farther than three is hard to read.
const NEAR_M: float = 0.5
const FAR_M: float = 3.0

## Used when the file is missing or rejected; matches the shipped file.
const FALLBACK: Dictionary = {
	"mark_text": "> ",
	"title_color": Color(0.85, 0.95, 1.0),
	"text_color": Color(0.6, 0.7, 0.8),
	"selected_color": Color(1.0, 0.85, 0.3),
	"reason_color": Color(1.0, 0.45, 0.35),
	"title_position_m": Vector3(0.0, 0.3, -1.2),
	"line_step_m": 0.07,
	"title_font_size": 64.0,
	"line_font_size": 44.0,
	"reason_font_size": 40.0,
	"pixel_size": 0.0008,
}


## The look in `path`, or `FALLBACK` with a warning naming the key.
static func load_file(path: String = DEFAULT_FILE) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("The hub panel uses its built-in look; %s: file not found" % path)
		return FALLBACK
	var look: Dictionary = parse(FileAccess.get_file_as_string(path))
	if look.has("error"):
		push_warning("The hub panel uses its built-in look; %s: %s" % [path, look["error"]])
		return FALLBACK
	return look


## The look with colours as `Color`, the title place as `Vector3` and numbers
## as floats, or a dictionary holding only `"error"`, naming the key.
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
	if typeof(data["mark_text"]) != TYPE_STRING or (data["mark_text"] as String).strip_edges() == "":
		return {"error": "\"mark_text\" must be a text that is not empty"}
	look["mark_text"] = data["mark_text"]
	for key: String in COLOR_KEYS:
		var parts: Array = _three_numbers(data[key])
		if parts.is_empty() or parts.min() < 0.0 or parts.max() > 1.0:
			return {"error": "\"%s\" must be [red, green, blue], each within 0..1" % key}
		look[key] = Color(parts[0], parts[1], parts[2])
	var at: Array = _three_numbers(data["title_position_m"])
	if at.is_empty() or absf(at[0]) > SIDE_LIMIT_M or absf(at[1]) > SIDE_LIMIT_M or -at[2] < NEAR_M \
			or -at[2] > FAR_M:
		return {"error": "\"title_position_m\" must be [x, y, z] within %s m to the side and %s..%s m in front" % [
			SIDE_LIMIT_M, NEAR_M, FAR_M]}
	look["title_position_m"] = Vector3(at[0], at[1], at[2])
	for key: String in RANGES:
		var value: Variant = data[key]
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:  # A bool must not pass as 0 or 1.
			return {"error": "\"%s\" must be a number" % key}
		var bounds: Array = RANGES[key]
		if float(value) < float(bounds[0]) or float(value) > float(bounds[1]):
			return {"error": "\"%s\" is %s, must be within %s..%s" % [key, value, bounds[0], bounds[1]]}
		look[key] = float(value)
	return look


static func _three_numbers(value: Variant) -> Array:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 3:
		return []
	var result: Array = []
	for part: Variant in value:
		if typeof(part) != TYPE_FLOAT and typeof(part) != TYPE_INT:
			return []
		result.append(float(part))
	return result
