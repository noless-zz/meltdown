class_name HubScreenLook
extends RefCounted

## Parses `res://xr/hub_screen.json`, how the home base stations' screens are
## drawn and how large their words must be (#1359, CRW-2, CMF-8, ARC-4):
##
## - `screen_color`: the screen's face, drawn unshaded, so the contrast between
##   it and each text colour is the contrast the pilot sees whatever the room's
##   lights do. The owner found pale text on bright cyan straining to read.
## - `title_color`, `text_color`, `selected_color`, `reason_color`: the words.
## - `frame_color`, `frame_width_m`: the frame around the highlighted station
##   and the one in use, so the choice is marked by a shape, not only a glow.
## - `face_inset_m`: how far the face stops inside the screen box's edge, so
##   the box's own colour shows as a rim (the launch station's is orange).
## - `rows_shown`: rows on a screen at once (#1300: at most five).
## - `title_font_size` (a station not in use, title only),
##   `open_title_font_size` and `row_font_size` (the station in use), with
##   `pixel_size`, the size of a font pixel in metres; `cap_height_ratio` is the
##   font's capital height over its font size, for the size checks.
## - `title_y_m`, `first_row_y_m`, `row_step_m`: line heights on the screen.
## - `focus_scale`, `focus_forward_m`, `focus_seconds`: the station in use
##   comes this far towards the eye and grows by this factor over this time.
##   Only the screen moves; the camera never does (CMF-8).
## - `min_contrast`, `min_text_deg`, `min_text_px`, `max_screen_emission`,
##   `eye_width_px`, `eye_height_px`, `vertical_fov_deg`: the thresholds the
##   tests and the `hub_screens` acceptance check hold the screens to, and the
##   Quest 3's per-eye resolution and field of view they are measured at.

const DEFAULT_FILE: String = "res://xr/hub_screen.json"
const COLOR_KEYS: Array[String] = ["screen_color", "title_color", "text_color", "selected_color", "reason_color",
	"frame_color"]
const RANGES: Dictionary[String, Array] = {
	"frame_width_m": [0.002, 0.05],
	"face_inset_m": [0.0, 0.05],
	"rows_shown": [1.0, 12.0],
	"title_font_size": [16.0, 256.0],
	"open_title_font_size": [16.0, 256.0],
	"row_font_size": [16.0, 256.0],
	"pixel_size": [0.0001, 0.002],
	"cap_height_ratio": [0.4, 1.0],
	"title_y_m": [-0.12, 0.12],
	"first_row_y_m": [-0.12, 0.12],
	"row_step_m": [0.01, 0.1],
	"focus_scale": [1.0, 3.0],
	## Under a fifth of a second the screen would jump at the face.
	"focus_seconds": [0.2, 2.0],
	## Kept short of the eye: nearer than half a metre is hard to focus on.
	"focus_forward_m": [0.0, 0.8],
	"min_contrast": [3.0, 21.0],
	"min_text_deg": [0.2, 3.0],
	"min_text_px": [4.0, 100.0],
	"max_screen_emission": [0.0, 2.0],
	"eye_width_px": [320.0, 8192.0],
	"eye_height_px": [320.0, 8192.0],
	"vertical_fov_deg": [30.0, 140.0],
}
const WHOLE_KEYS: Array[String] = ["rows_shown", "title_font_size", "open_title_font_size", "row_font_size"]

## Used when the file is missing or rejected; matches the shipped file.
const FALLBACK: Dictionary = {
	"screen_color": Color(0.02, 0.035, 0.05),
	"title_color": Color(0.93, 0.97, 1.0),
	"text_color": Color(0.8, 0.87, 0.93),
	"selected_color": Color(1.0, 0.85, 0.4),
	"reason_color": Color(1.0, 0.64, 0.52),
	"frame_color": Color(0.85, 0.66, 0.28),
	"frame_width_m": 0.012,
	"face_inset_m": 0.008,
	"rows_shown": 5.0,
	"title_font_size": 72.0,
	"open_title_font_size": 52.0,
	"row_font_size": 32.0,
	"pixel_size": 0.0005,
	"cap_height_ratio": 0.7,
	"title_y_m": 0.085,
	"first_row_y_m": 0.045,
	"row_step_m": 0.03,
	"focus_scale": 1.8,
	"focus_forward_m": 0.45,
	"focus_seconds": 0.4,
	"min_contrast": 7.0,
	"min_text_deg": 0.9,
	"min_text_px": 15.0,
	"max_screen_emission": 0.35,
	"eye_width_px": 2064.0,
	"eye_height_px": 2208.0,
	"vertical_fov_deg": 96.0,
}


## The look in `path`, or `FALLBACK` with a warning naming the key.
static func load_file(path: String = DEFAULT_FILE) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("The hub screens use their built-in look; %s: file not found" % path)
		return FALLBACK
	var look: Dictionary = parse(FileAccess.get_file_as_string(path))
	if look.has("error"):
		push_warning("The hub screens use their built-in look; %s: %s" % [path, look["error"]])
		return FALLBACK
	return look


## The look with colours as `Color` and numbers as floats, or a dictionary
## holding only `"error"`, naming the key.
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
	for key: String in RANGES:
		var value: Variant = data[key]
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:  # A bool must not pass as 0 or 1.
			return {"error": "\"%s\" must be a number" % key}
		var bounds: Array = RANGES[key]
		if float(value) < float(bounds[0]) or float(value) > float(bounds[1]):
			return {"error": "\"%s\" is %s, must be within %s..%s" % [key, value, bounds[0], bounds[1]]}
		if WHOLE_KEYS.has(key) and float(value) != floorf(float(value)):
			return {"error": "\"%s\" must be a whole number" % key}
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
