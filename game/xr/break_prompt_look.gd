class_name BreakPromptLook
extends RefCounted

## Parses the break prompt's data file, `res://xr/break_prompt.json` (CMF-10,
## ARC-4): whether reminders are on, where the prompt sits, its sizes, colours
## and wording.
##
##     {"enabled": b, "position_m": [x, y, z], "tilt_deg": t, "pixel_size": p,
##      "title_font": n, "body_font": n, "title_color": [r, g, b],
##      "body_color": [r, g, b], "title_text": s, "flown_text": s,
##      "dismiss_xr": s, "dismiss_flat": s, "off_text": s}
##
## `enabled` holds the player's switch until a settings menu exists (M8).
## `position_m` is in the cockpit's space from the eye point (x right, y up,
## -z ahead), like the status panel's. `flown_text` must hold `{minutes}`.

const DEFAULT_FILE: String = "res://xr/break_prompt.json"
const BOOL_KEYS: Array[String] = ["enabled"]
const COLOR_KEYS: Array[String] = ["title_color", "body_color"]
const VECTOR_KEYS: Array[String] = ["position_m"]
const TEXT_KEYS: Array[String] = ["title_text", "flown_text", "dismiss_xr", "dismiss_flat", "off_text"]
## Each number key with the range it must lie in.
const NUMBER_RANGES: Dictionary = {
	"tilt_deg": Vector2(0.0, 89.0),
	"pixel_size": Vector2(0.0001, 0.005),
	"title_font": Vector2(8.0, 256.0),
	"body_font": Vector2(8.0, 256.0),
}
## Integer keys among the numbers: font sizes are whole pixels.
const INT_KEYS: Array[String] = ["title_font", "body_font"]
const MINUTES_TAG: String = "{minutes}"
## The prompt must stay inside the ship's 1 m collision sphere, so no wall can
## come between it and the eyes (the status panel's rule).
const MAX_DISTANCE_M: float = 0.9
## Used when the file is missing or rejected: reminders on, the prompt just
## below the line of sight and above the status panel.
const FALLBACK: Dictionary = {
	"enabled": true,
	"position_m": Vector3(0.0, -0.085, -0.55),
	"tilt_deg": 9.0,
	"pixel_size": 0.0004,
	"title_font": 40,
	"body_font": 28,
	"title_color": Color(1.0, 0.8, 0.45),
	"body_color": Color(0.85, 0.95, 1.0),
	"title_text": "Time for a break",
	"flown_text": "You have flown for {minutes} minutes.",
	"dismiss_xr": "Tap the menu button to dismiss",
	"dismiss_flat": "Tap Backspace to dismiss",
	"off_text": "These reminders can be switched off.",
}


static func keys() -> Array[String]:
	var all: Array[String] = []
	all.append_array(BOOL_KEYS)
	all.append_array(COLOR_KEYS)
	all.append_array(VECTOR_KEYS)
	all.append_array(TEXT_KEYS)
	for key: String in NUMBER_RANGES:
		all.append(key)
	return all


## Parses the text of a break prompt file. Returns the look with colours as
## `Color`, the position as `Vector3`, fonts as `int` and other numbers as
## `float`, or a dictionary holding only `"error"`, which names the field.
static func parse(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return {"error": "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]}
	if typeof(json.data) != TYPE_DICTIONARY:
		return {"error": "top level must be a JSON object"}
	var data: Dictionary = json.data
	var known: Array[String] = keys()
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not known.has(key):
			return {"error": "unknown key \"%s\"" % str(key)}
	for key: String in known:
		if not data.has(key):
			return {"error": "missing key \"%s\"" % key}
	var look: Dictionary = FALLBACK.duplicate()
	for key: String in BOOL_KEYS:
		if typeof(data[key]) != TYPE_BOOL:
			return {"error": "\"%s\" must be true or false" % key}
		look[key] = data[key]
	for key: String in COLOR_KEYS:
		var problem: String = _triple_problem(key, data[key], Vector2(0.0, 1.0))
		if problem != "":
			return {"error": problem}
		look[key] = Color(float(data[key][0]), float(data[key][1]), float(data[key][2]))
	for key: String in VECTOR_KEYS:
		var problem: String = _triple_problem(key, data[key], Vector2(-MAX_DISTANCE_M, MAX_DISTANCE_M))
		if problem != "":
			return {"error": problem}
		var at: Vector3 = Vector3(float(data[key][0]), float(data[key][1]), float(data[key][2]))
		if at.length() > MAX_DISTANCE_M:
			return {"error": "\"%s\" is %.2f m from the eye, more than %.2f" % [key, at.length(), MAX_DISTANCE_M]}
		# Below the line of sight and ahead of the eye, never above or behind it.
		if at.y >= 0.0 or at.z >= 0.0:
			return {"error": "\"%s\" must be below (y < 0) and ahead of (z < 0) the eye" % key}
		look[key] = at
	for key: String in TEXT_KEYS:
		if typeof(data[key]) != TYPE_STRING or (data[key] as String).strip_edges() == "":
			return {"error": "\"%s\" must be non-empty text" % key}
		look[key] = data[key]
	if not (look["flown_text"] as String).contains(MINUTES_TAG):
		return {"error": "\"flown_text\" must contain %s" % MINUTES_TAG}
	for key: String in NUMBER_RANGES:
		var value: Variant = data[key]
		var range_: Vector2 = NUMBER_RANGES[key]
		# A bool must not pass as 0 or 1.
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return {"error": "\"%s\" must be a number" % key}
		if float(value) < range_.x or float(value) > range_.y:
			return {"error": "\"%s\" is %s, must be within %s..%s" % [key, value, range_.x, range_.y]}
		if INT_KEYS.has(key):
			if float(value) != floorf(float(value)):
				return {"error": "\"%s\" must be a whole number" % key}
			look[key] = int(value)
		else:
			look[key] = float(value)
	return look


## Empty when `parts` is three numbers within `range_`, else what is wrong.
static func _triple_problem(key: String, parts: Variant, range_: Vector2) -> String:
	if typeof(parts) != TYPE_ARRAY or (parts as Array).size() != 3:
		return "\"%s\" must be three numbers" % key
	for part: Variant in parts:
		if typeof(part) != TYPE_FLOAT and typeof(part) != TYPE_INT:
			return "\"%s\" must hold numbers" % key
		if float(part) < range_.x or float(part) > range_.y:
			return "\"%s\" has %s, must be within %s..%s" % [key, part, range_.x, range_.y]
	return ""


## Reads the file at `path`. A missing or rejected file gives `FALLBACK` with
## `"error"` added, naming the field, and pushes a warning.
static func load_file(path: String = DEFAULT_FILE) -> Dictionary:
	var values: Dictionary = {"error": "file not found"}
	if FileAccess.file_exists(path):
		values = parse(FileAccess.get_file_as_string(path))
	if values.has("error"):
		var message: String = "%s: %s" % [path, values["error"]]
		push_warning("BreakPrompt uses the built-in look; " + message)
		var fallback: Dictionary = FALLBACK.duplicate()
		fallback["error"] = message
		return fallback
	return values
