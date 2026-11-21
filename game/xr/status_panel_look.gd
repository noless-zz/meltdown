class_name StatusPanelLook
extends RefCounted

## Parses the status panel's look file, `res://xr/status_panel_look.json`
## (ARC-4): the colour of the "ESCAPED" outcome row (#361), where the panel
## sits and how far it is tilted toward the eye, the steepest glance down any
## row may need, and how long a hold message stays up (#605):
##
##     {"escaped_color": [r, g, b], "position_m": [x, y, z], "tilt_deg": t,
##      "max_row_angle_deg": a, "message_seconds": s, "low_hull_fraction": f}
##
## `low_hull_fraction` may be left out: at or below it the hull row turns red
## and the low-hull pulse fires (#616). So may the level row's (#747) font
## size `level_font`, colour `level_color` and words `level_tunnel_text`,
## `level_seed_text` (with `{seed}`) and `level_file_text` (with `{name}`).
## So may `preset_swivel_text`, the tag after the preset's name while
## swivel-chair mode is on (#792).
##
## `position_m` is in the cockpit's space from the eye point (x right, y up,
## -z ahead). `tilt_deg` turns the panel's top away from the eye.
##
## `corners` may be left out (#752): the panel's centre for each of the four
## corners of the view the owner can choose, in the same space, as
## `{"top_left": [x, y, z], "top_right": ..., "bottom_left": ...,
## "bottom_right": ...}`. A panel in a corner is turned to face the eye with
## its rows level. `position_m` and `tilt_deg` stay the panel's place when no
## corner is chosen (`PanelCorner.CENTRE`).

const DEFAULT_FILE: String = "res://xr/status_panel_look.json"
const COLOR_KEYS: Array[String] = ["escaped_color"]
const VECTOR_KEYS: Array[String] = ["position_m"]
## Each number key with the range it must lie in.
const NUMBER_RANGES: Dictionary = {
	"tilt_deg": Vector2(0.0, 89.0),
	"max_row_angle_deg": Vector2(0.0, 89.0),
	"message_seconds": Vector2(0.0, 60.0),
}
## Number keys a file may leave out, with their ranges; `FALLBACK` gives the value.
const OPTIONAL_NUMBER_RANGES: Dictionary = {
	"low_hull_fraction": Vector2(0.0, 1.0),
	"level_font": Vector2(8.0, 96.0),
}
## Colour and text keys a file may leave out; `FALLBACK` gives the value.
const OPTIONAL_COLOR_KEYS: Array[String] = ["level_color"]
const OPTIONAL_TEXT_KEYS: Array[String] = ["level_tunnel_text", "level_seed_text", "level_file_text",
	"preset_swivel_text"]
## The four corners a `corners` value must name, and nothing else.
const CORNER_NAMES: Array[String] = ["top_left", "top_right", "bottom_left", "bottom_right"]
## A corner nearer the eye than this would fill the view and could not be
## faced at the eye reliably.
const MIN_CORNER_DISTANCE_M: float = 0.2
## A corner must lie at least this far ahead (-z), so it can be faced at the eye.
const AHEAD_M: float = 0.1
## The panel must stay inside the ship's 1 m collision sphere, so no wall can
## come between it and the eyes.
const MAX_DISTANCE_M: float = 0.9
## Used when the file is missing or rejected. Green, so an escape never reads
## as the red of a lost ship or a failing hull. The panel 0.55 m out, 19
## degrees down and faced at the eye: its bottom row is under 30 degrees down.
const FALLBACK: Dictionary = {
	"escaped_color": Color(0.35, 1.0, 0.45),
	"position_m": Vector3(0.0, -0.179, -0.52),
	"tilt_deg": 19.0,
	"max_row_angle_deg": 30.0,
	"message_seconds": 2.0,
	"low_hull_fraction": 0.25,
	# Smaller than the rows' 32 and grey, so it never draws the eye from the bars.
	"level_font": 24.0,
	"level_color": Color(0.5, 0.56, 0.6),
	"level_tunnel_text": "Test tunnel",
	"level_seed_text": "Seed {seed}",
	"level_file_text": "{name}",
	# Short, so the preset row still fits beside the level row (#792).
	"preset_swivel_text": "Swivel",
	# About 17 degrees to the side and 13 up or down at 0.55 m, like the
	# default's distance: every row stays within 40 degrees of straight ahead.
	"corners": {
		"top_left": Vector3(-0.157, 0.124, -0.512),
		"top_right": Vector3(0.157, 0.124, -0.512),
		"bottom_left": Vector3(-0.157, -0.124, -0.512),
		"bottom_right": Vector3(0.157, -0.124, -0.512),
	},
}


## The shipped look file, read once for every panel.
static var _shared: Dictionary = {}


## The shipped look, read on first use.
static func shared() -> Dictionary:
	if _shared.is_empty():
		_shared = load_file()
	return _shared


static func keys() -> Array[String]:
	var all: Array[String] = []
	all.append_array(COLOR_KEYS)
	all.append_array(VECTOR_KEYS)
	for key: String in NUMBER_RANGES:
		all.append(key)
	return all


## Parses the text of a look file. Returns the look with colours as `Color`,
## the position as `Vector3` and numbers as `float`, or a dictionary holding
## only `"error"`, which names the field.
static func parse(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return {"error": "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]}
	if typeof(json.data) != TYPE_DICTIONARY:
		return {"error": "top level must be a JSON object"}
	var data: Dictionary = json.data
	var known: Array[String] = keys()
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not (known.has(key) or OPTIONAL_NUMBER_RANGES.has(key) \
				or OPTIONAL_COLOR_KEYS.has(key) or OPTIONAL_TEXT_KEYS.has(key) or key == "corners"):
			return {"error": "unknown key \"%s\"" % str(key)}
	for key: String in known:
		if not data.has(key):
			return {"error": "missing key \"%s\"" % key}
	var look: Dictionary = FALLBACK.duplicate()
	for key: String in COLOR_KEYS + OPTIONAL_COLOR_KEYS:
		if not data.has(key):
			continue  # Only an optional key can be missing here.
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
		look[key] = at
	if data.has("corners"):
		var corners: Variant = _corners(data["corners"])
		if corners is String:
			return {"error": corners}
		look["corners"] = corners
	for key: String in OPTIONAL_TEXT_KEYS:
		if data.has(key):
			if typeof(data[key]) != TYPE_STRING or (data[key] as String).strip_edges() == "":
				return {"error": "\"%s\" must be a non-empty string" % key}
			look[key] = data[key]
	var ranges: Dictionary = NUMBER_RANGES.merged(OPTIONAL_NUMBER_RANGES)
	for key: String in ranges:
		if not data.has(key):
			continue  # Only an optional key can be missing here.
		var value: Variant = data[key]
		var range_: Vector2 = ranges[key]
		# A bool must not pass as 0 or 1.
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return {"error": "\"%s\" must be a number" % key}
		if float(value) < range_.x or float(value) > range_.y:
			return {"error": "\"%s\" is %s, must be within %s..%s" % [key, value, range_.x, range_.y]}
		look[key] = float(value)
	return look


## The panel's transform in the cockpit's space from the eye point, for
## `corner` (one of `CORNER_NAMES`) or, for any other name, the look's own
## `position_m` and `tilt_deg`: the place it had before corners (#752).
static func placement(look: Dictionary, corner: String) -> Transform3D:
	var corners: Dictionary = look.get("corners", {})
	if corners.has(corner):
		var at: Vector3 = corners[corner]
		# -z away from the eye, so the panel's face (+z) looks back at it.
		return Transform3D(Basis.looking_at(at, Vector3.UP), at)
	var tilt: float = deg_to_rad(float(look["tilt_deg"]))
	return Transform3D(Basis(Vector3.RIGHT, -tilt), look["position_m"] as Vector3)


## The `corners` value as names to `Vector3`, or a message naming what is wrong.
static func _corners(value: Variant) -> Variant:
	if typeof(value) != TYPE_DICTIONARY:
		return "\"corners\" must be an object"
	var given: Dictionary = value
	for corner_name: Variant in given:
		if not CORNER_NAMES.has(str(corner_name)):
			return "unknown corner \"%s\"" % str(corner_name)
	var corners: Dictionary = {}
	for corner_name: String in CORNER_NAMES:
		var key: String = "corners.%s" % corner_name
		if not given.has(corner_name):
			return "missing corner \"%s\"" % corner_name
		var problem: String = _triple_problem(key, given[corner_name], Vector2(-MAX_DISTANCE_M, MAX_DISTANCE_M))
		if problem != "":
			return problem
		var at: Vector3 = Vector3(float(given[corner_name][0]), float(given[corner_name][1]), float(given[corner_name][2]))
		if at.length() > MAX_DISTANCE_M or at.length() < MIN_CORNER_DISTANCE_M:
			return "\"%s\" is %.2f m from the eye, must be %.2f..%.2f" % [
				key, at.length(), MIN_CORNER_DISTANCE_M, MAX_DISTANCE_M]
		if at.z > -AHEAD_M:
			return "\"%s\" must lie at least %.2f m ahead of the eye" % [key, AHEAD_M]
		corners[corner_name] = at
	return corners


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


## Reads the look file at `path`. A missing or rejected file gives `FALLBACK`
## and pushes a warning naming the field.
static func load_file(path: String = DEFAULT_FILE) -> Dictionary:
	var values: Dictionary = {"error": "file not found"}
	if FileAccess.file_exists(path):
		values = parse(FileAccess.get_file_as_string(path))
	if values.has("error"):
		push_warning("StatusPanel uses the built-in look; %s: %s" % [path, values["error"]])
		return FALLBACK
	return values
