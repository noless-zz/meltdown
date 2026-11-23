class_name SlotPopupLook
extends RefCounted

## Parses the slot popup's data file, `res://xr/slot_popup.json` (#1263,
## decision record 0011, ARC-4): its wording, sizes, distances, colours and
## the stick thresholds that pick a choice.
##
##     {"left_text": s, "right_text": s, "down_text": s, "cancel_text": s,
##      "height_m": h, "spread_m": d, "pixel_size": p, "choice_font": n,
##      "cancel_font": n, "choice_color": [r, g, b], "cancel_color": [r, g, b],
##      "flick_threshold": f, "rest_threshold": r}
##
## `height_m` is how far above the stick the popup's centre floats, and
## `spread_m` how far each choice sits from that centre. A flick counts once
## the stick passes `flick_threshold` of full deflection; the stick must come
## back inside `rest_threshold` before the popup takes a flick, and before the
## stick turns the ship again once it has closed, so the stick that chose
## never jerks the ship round.

const DEFAULT_FILE: String = "res://xr/slot_popup.json"
const TEXT_KEYS: Array[String] = ["left_text", "right_text", "down_text", "cancel_text"]
const COLOR_KEYS: Array[String] = ["choice_color", "cancel_color"]
## Each number key with the range it must lie in. The distances keep the
## popup within a hand's width of the stick, so it reads as the stick's own.
const NUMBER_RANGES: Dictionary = {
	"height_m": Vector2(0.0, 0.2),
	"spread_m": Vector2(0.01, 0.15),
	"pixel_size": Vector2(0.0001, 0.002),
	"choice_font": Vector2(8.0, 128.0),
	"cancel_font": Vector2(8.0, 128.0),
	"flick_threshold": Vector2(0.3, 1.0),
	"rest_threshold": Vector2(0.05, 0.9),
}
const INT_KEYS: Array[String] = ["choice_font", "cancel_font"]
## Used when the file is missing or rejected.
const FALLBACK: Dictionary = {
	"left_text": "Replace left gun",
	"right_text": "Replace right gun",
	"down_text": "Dump",
	"cancel_text": "Click: cancel",
	"height_m": 0.06,
	"spread_m": 0.05,
	"pixel_size": 0.00025,
	"choice_font": 32,
	"cancel_font": 22,
	"choice_color": Color(1.0, 0.85, 0.4),
	"cancel_color": Color(0.75, 0.85, 0.95),
	"flick_threshold": 0.7,
	"rest_threshold": 0.3,
}


static func keys() -> Array[String]:
	var all: Array[String] = []
	all.append_array(TEXT_KEYS)
	all.append_array(COLOR_KEYS)
	for key: String in NUMBER_RANGES:
		all.append(key)
	return all


## Parses the text of a slot popup file. Returns the look with colours as
## `Color`, fonts as `int` and other numbers as `float`, or a dictionary
## holding only `"error"`, which names the field.
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
	for key: String in TEXT_KEYS:
		if typeof(data[key]) != TYPE_STRING or (data[key] as String).strip_edges() == "":
			return {"error": "\"%s\" must be non-empty text" % key}
		look[key] = data[key]
	for key: String in COLOR_KEYS:
		var problem: String = _color_problem(key, data[key])
		if problem != "":
			return {"error": problem}
		look[key] = Color(float(data[key][0]), float(data[key][1]), float(data[key][2]))
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
	# A rest above the flick would let a resting stick choose.
	if float(look["rest_threshold"]) >= float(look["flick_threshold"]):
		return {"error": "\"rest_threshold\" must be below \"flick_threshold\""}
	return look


## Empty when `parts` is three numbers within 0..1, else what is wrong.
static func _color_problem(key: String, parts: Variant) -> String:
	if typeof(parts) != TYPE_ARRAY or (parts as Array).size() != 3:
		return "\"%s\" must be three numbers" % key
	for part: Variant in parts:
		if typeof(part) != TYPE_FLOAT and typeof(part) != TYPE_INT:
			return "\"%s\" must hold numbers" % key
		if float(part) < 0.0 or float(part) > 1.0:
			return "\"%s\" has %s, must be within 0..1" % [key, part]
	return ""


## Reads the file at `path`. A missing or rejected file gives `FALLBACK` with
## `"error"` added, naming the field, and pushes a warning.
static func load_file(path: String = DEFAULT_FILE) -> Dictionary:
	var values: Dictionary = {"error": "file not found"}
	if FileAccess.file_exists(path):
		values = parse(FileAccess.get_file_as_string(path))
	if values.has("error"):
		var message: String = "%s: %s" % [path, values["error"]]
		push_warning("SlotPopup uses the built-in look; " + message)
		var fallback: Dictionary = FALLBACK.duplicate()
		fallback["error"] = message
		return fallback
	return values
