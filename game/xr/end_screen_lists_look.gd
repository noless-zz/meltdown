class_name EndScreenListsLook
extends RefCounted

## Parses `res://xr/end_screen_lists.json`, the words and placement of what the
## end screens list (#1376, CRF-2, RUN-7, SLV-3, ARC-4): the escape screen's
## banked components and miners brought out, the destroyed screen's components
## kept from earlier escapes and lost on this level, and the prompt both show
## when the press ends the run and the pilot goes to the base:
##
##     {"banked_text": "... {items} ...", "brought_out_text": "... {miners} ...",
##      "kept_text": "... {items} ...", "lost_text": "... {items} ... {miners} ...",
##      "none_text": "...", "base_prompt_xr": "...", "base_prompt_flat": "...",
##      "color": [r, g, b], "font_size": 16..256,
##      "escape_position_m": [x, y, z], "destroyed_position_m": [x, y, z]}
##
## Positions are from the eye point like the screens' own lines
## (`EscapeScreenLook`), and must lie in front of the eye.

const DEFAULT_FILE: String = "res://xr/end_screen_lists.json"
const ITEMS_TAG: String = StatusPanelTally.ITEMS_TAG
const MINERS_TAG: String = StatusPanelTally.MINERS_TAG

const TEXT_KEYS: Array[String] = ["banked_text", "brought_out_text", "kept_text", "lost_text", "none_text",
	"base_prompt_xr", "base_prompt_flat"]
const POSITION_KEYS: Array[String] = ["escape_position_m", "destroyed_position_m"]
## The tags each text must carry, so a typo cannot drop a count from the screen.
const TAGS: Dictionary[String, Array] = {
	"banked_text": [ITEMS_TAG],
	"brought_out_text": [MINERS_TAG],
	"kept_text": [ITEMS_TAG],
	"lost_text": [ITEMS_TAG, MINERS_TAG],
}
const FONT_RANGE: Vector2 = Vector2(16.0, 256.0)

## Used when the file is missing or rejected; matches the shipped file.
const FALLBACK: Dictionary = {
	"banked_text": "Banked: {items}",
	"brought_out_text": "Miners brought out: {miners}",
	"kept_text": "Kept from earlier escapes: {items}",
	"lost_text": "Lost on this level: {items} | Miners {miners}",
	"none_text": "nothing",
	"base_prompt_xr": "Press A: return to base",
	"base_prompt_flat": "Press Enter: return to base",
	"color": Color(0.85, 0.95, 1.0),
	"font_size": 40.0,
	"escape_position_m": Vector3(0.0, -0.17, -1.5),
	"destroyed_position_m": Vector3(0.0, -0.14, -1.5),
}


## The look in `path`, or `FALLBACK` when it is missing or rejected, with the
## reason pushed as a warning naming the field.
static func load_file(path: String = DEFAULT_FILE) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("The end screens' lists use built-in words; %s: file not found" % path)
		return FALLBACK
	var look: Dictionary = parse(FileAccess.get_file_as_string(path))
	if look.has("error"):
		push_warning("The end screens' lists use built-in words; %s: %s" % [path, look["error"]])
		return FALLBACK
	return look


## The look with the colour as `Color`, positions as `Vector3` and the font
## size as a float, or a dictionary holding only `"error"`, naming the field.
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
	for key: String in TEXT_KEYS:
		if typeof(data[key]) != TYPE_STRING or (data[key] as String).strip_edges() == "":
			return {"error": "\"%s\" must be a text that is not empty" % key}
		for tag: String in TAGS.get(key, []):
			if not (data[key] as String).contains(tag):
				return {"error": "\"%s\" must contain %s" % [key, tag]}
		look[key] = data[key]
	var color: Array = _three_numbers(data["color"])
	if color.is_empty() or color.min() < 0.0 or color.max() > 1.0:
		return {"error": "\"color\" must be [red, green, blue], each within 0..1"}
	look["color"] = Color(color[0], color[1], color[2])
	for key: String in POSITION_KEYS:
		var at: Array = _three_numbers(data[key])
		if at.is_empty() or absf(at[0]) > EscapeScreenLook.SIDE_LIMIT_M or absf(at[1]) > EscapeScreenLook.SIDE_LIMIT_M \
				or -at[2] < EscapeScreenLook.NEAR_M or -at[2] > EscapeScreenLook.FAR_M:
			return {"error": "\"%s\" must be [x, y, z] within %s m to the side and %s..%s m in front" % [
				key, EscapeScreenLook.SIDE_LIMIT_M, EscapeScreenLook.NEAR_M, EscapeScreenLook.FAR_M]}
		look[key] = Vector3(at[0], at[1], at[2])
	var size: Variant = data["font_size"]
	# A bool must not pass as 0 or 1.
	if typeof(size) != TYPE_FLOAT and typeof(size) != TYPE_INT:
		return {"error": "\"font_size\" must be a number"}
	if float(size) < FONT_RANGE.x or float(size) > FONT_RANGE.y:
		return {"error": "\"font_size\" is %s, must be within %s..%s" % [size, FONT_RANGE.x, FONT_RANGE.y]}
	look["font_size"] = float(size)
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
