class_name CockpitSpec
extends RefCounted

## The shape of one cockpit frame, read from a JSON data file in
## `res://xr/cockpits/` (CMF-1, ARC-4). Each comfort preset names its file
## through `ComfortPreset.cockpit_file`.
##
## A frame is a fixed visual reference around the eye point that reduces
## vection. It belongs to the view only: nothing here is read by the
## simulation (ARC-3, CMF-6). The numbers are guesses for the headset
## sessions and live in the data files so the owner can change them.
##
## Angles are measured from straight ahead: a window half-angle of 90 degrees
## opens the whole forward half of the view along that axis. Since #607 the
## frame is a shell plus a few large shapes (a dashboard ledge, two canopy
## pillars, a rim); a shape with zero size is not built.

## Half the window's width, degrees from straight ahead, 10..90.
var window_half_angle_h_deg: float = 90.0
## Half the window's height, degrees from straight ahead, 10..90.
var window_half_angle_v_deg: float = 90.0
## Distance of the frame's shell from the eye point, metres, 0.32..0.95. The
## shapes sit inside the shell, at least 0.3 m from the eye, so every file
## that validates keeps its geometry beyond 0.25 m, well clear of the camera's
## 0.05 m near plane (#102), and inside the ship's 1 m collision radius.
var frame_distance_m: float = 0.6
## Opacity of the canopy glass inside the window, 0..1; 0 leaves no glass.
var glass_tint_alpha: float = 0.05
## Where the ledge's top edge sits, degrees below straight ahead, 10..90. It
## never rises above the window's lower edge. The look value that moves the
## ledge with the status panel (#605).
var ledge_top_deg: float = 90.0
## Height of the dashboard ledge, degrees, 0..30; 0 builds no ledge.
var ledge_height_deg: float = 0.0
## Half the ledge's width, degrees from straight ahead, 10..90.
var ledge_half_width_deg: float = 60.0
## Distance of the ledge's front face from the eye, metres, 0.3..0.85.
var ledge_distance_m: float = 0.4
## Width of each canopy pillar beside the window, degrees, 0..20; 0 builds none.
var pillar_width_deg: float = 0.0
## Distance of the pillars' front faces from the eye, metres, 0.3..0.85.
var pillar_distance_m: float = 0.45
## Height of the rim above the window, degrees, 0..30; 0 builds no rim.
var rim_height_deg: float = 0.0
## Distance of the rim's front face from the eye, metres, 0.3..0.85.
var rim_distance_m: float = 0.45
## Thickness of the ledge, pillars and rim, metres, 0.01..0.08.
var part_depth_m: float = 0.03
## Colour of the shell around the window: an interior tone kept apart from
## the tunnel's walls so the cockpit does not read as more tunnel, and light
## enough that it is never black on black (#659, `CockpitLook.floor_error`).
var interior_color: Color = Color(0.3, 0.33, 0.38)
## Colour of the ledge, pillars and rim.
var structure_color: Color = Color(0.44, 0.47, 0.52)
## How far past the window's edge the head may look before the view guard
## counts it as lost, degrees, 10..90 (#651, `ViewGuard`).
var guard_margin_deg: float = 40.0
## How long the head may stay lost before the guard re-places the frame
## around it, seconds, 0.5..10. Long enough that a glance aside never does.
var guard_after_s: float = 3.0
## How far the eye may be from the frame's centre before it counts as lost,
## metres, 0.2..0.9. Beyond a seated lean (`HeadRecentre.HEAD_REACH`).
var guard_distance_m: float = 0.45

## Every number key of the data file, with the same name as the field it sets.
const KEYS: Array[String] = [
	"window_half_angle_h_deg", "window_half_angle_v_deg", "frame_distance_m",
	"glass_tint_alpha", "ledge_top_deg", "ledge_height_deg", "ledge_half_width_deg",
	"ledge_distance_m", "pillar_width_deg", "pillar_distance_m", "rim_height_deg",
	"rim_distance_m", "part_depth_m", "guard_margin_deg", "guard_after_s", "guard_distance_m",
]

## Every colour key: an array of three numbers, red, green and blue, 0..1.
const COLOR_KEYS: Array[String] = ["interior_color", "structure_color"]

## Allowed range of each number key, inclusive: [minimum, maximum]. Keep these
## in step with the ranges written on the fields above.
const RANGES: Dictionary[String, Array] = {
	"window_half_angle_h_deg": [10.0, 90.0],
	"window_half_angle_v_deg": [10.0, 90.0],
	"frame_distance_m": [0.32, 0.95],
	"glass_tint_alpha": [0.0, 1.0],
	"ledge_top_deg": [10.0, 90.0],
	"ledge_height_deg": [0.0, 30.0],
	"ledge_half_width_deg": [10.0, 90.0],
	"ledge_distance_m": [0.3, 0.85],
	"pillar_width_deg": [0.0, 20.0],
	"pillar_distance_m": [0.3, 0.85],
	"rim_height_deg": [0.0, 30.0],
	"rim_distance_m": [0.3, 0.85],
	"part_depth_m": [0.01, 0.08],
	"guard_margin_deg": [10.0, 90.0],
	"guard_after_s": [0.5, 10.0],
	"guard_distance_m": [0.2, 0.9],
}

## The key of the surfaces' look object (`CockpitLook`).
const LOOK_KEY: String = "look"
## The key of the surfaces' finish object (`CockpitFinish`), optional.
const FINISH_KEY: String = "finish"

## The shapes' distance keys: each shape must lie wholly in front of the shell.
const SHAPE_DISTANCE_KEYS: Array[String] = ["ledge_distance_m", "pillar_distance_m", "rim_distance_m"]

## The surfaces' pattern, edge highlight and light: the file's `"look"`
## object (#659).
var look: CockpitLook = CockpitLook.new()
## The instruments the file declares (#1216); its optional `"instruments"`
## list, empty without one. None is drawn yet (M6).
var instruments: Array[CockpitInstrument] = []

## The surfaces' physically based finish and the glass's edge reflection:
## the file's optional `"finish"` object (#1306); neutral without one.
var finish: CockpitFinish = CockpitFinish.new()
## The modelled dash pieces: the file's optional `"dash"` list (#1306).
var dash: Array[CockpitDashPiece] = []
## Where the map hangs in the cockpit place: the optional `"map_mount"` (#1321).
var map_mount: CockpitMapMount = CockpitMapMount.new()

## Set when the text was rejected; empty otherwise.
var error: String = ""


## Parses the text of a cockpit data file: one JSON object holding every key
## in `KEYS` as a number in its range, every key in `COLOR_KEYS` as a colour
## and a `"look"` object for `CockpitLook`, optionally an `"instruments"`
## list (`CockpitInstrument`), an optional `"finish"` object
## (`CockpitFinish`) and `"dash"` list (`CockpitDashPiece`), and nothing
## else. A missing or unknown required key is an error, so a typo cannot
## leave a value silently at its default. On failure the returned spec
## has `error` set, naming the field, and default values.
static func parse_json(text: String) -> CockpitSpec:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not (KEYS.has(key) or COLOR_KEYS.has(key) or key == LOOK_KEY
				or key == CockpitInstrument.LIST_KEY or key == FINISH_KEY or key == CockpitDashPiece.LIST_KEY
				or key == CockpitMapMount.KEY):
			return _rejected("unknown key \"%s\"" % str(key))
	var spec: CockpitSpec = CockpitSpec.new()
	for key: String in KEYS:
		if not data.has(key):
			return _rejected("missing key \"%s\"" % key)
		var value: Variant = data[key]
		# A bool must not pass as 0 or 1.
		if not _is_number(value):
			return _rejected("key \"%s\" must be a number" % key)
		var low: float = RANGES[key][0]
		var high: float = RANGES[key][1]
		if float(value) < low or float(value) > high:
			return _rejected("key \"%s\" is %s, must be within %s..%s" % [key, value, low, high])
		spec.set(key, float(value))
	for key: String in COLOR_KEYS:
		if not data.has(key):
			return _rejected("missing key \"%s\"" % key)
		var color_error: String = _color_error(data[key])
		if color_error != "":
			return _rejected("key \"%s\" %s" % [key, color_error])
		var parts: Array = data[key]
		spec.set(key, Color(float(parts[0]), float(parts[1]), float(parts[2])))
	if not data.has(LOOK_KEY):
		return _rejected("missing key \"%s\"" % LOOK_KEY)
	spec.look = CockpitLook.parse(data[LOOK_KEY])
	if spec.look.error != "":
		return _rejected("key \"%s\": %s" % [LOOK_KEY, spec.look.error])
	for key: String in COLOR_KEYS:
		var too_dark: String = spec.look.floor_error(spec.get(key), key)
		if too_dark != "":
			return _rejected(too_dark)
	for key: String in SHAPE_DISTANCE_KEYS:
		if spec.get(key) + spec.part_depth_m > spec.frame_distance_m:
			return _rejected("key \"%s\" is %s; with part_depth_m %s it reaches past frame_distance_m %s" % [
				key, spec.get(key), spec.part_depth_m, spec.frame_distance_m])
	if data.has(CockpitInstrument.LIST_KEY):
		var parsed: Variant = CockpitInstrument.parse_list(data[CockpitInstrument.LIST_KEY])
		if parsed is String:
			return _rejected(parsed)
		spec.instruments = parsed
	if data.has(CockpitMapMount.KEY):
		var mount: Variant = CockpitMapMount.parse(data[CockpitMapMount.KEY])
		if mount is String:
			return _rejected(mount)
		spec.map_mount = mount
	return _parse_finish_and_dash(data, spec)


## The optional `"finish"` object and `"dash"` list (#1306) of `data`, set on
## `spec`; a rejected spec when either is wrong or a piece leaves the frame.
static func _parse_finish_and_dash(data: Dictionary, spec: CockpitSpec) -> CockpitSpec:
	if data.has(FINISH_KEY):
		spec.finish = CockpitFinish.parse(data[FINISH_KEY])
		if spec.finish.error != "":
			return _rejected("key \"%s\": %s" % [FINISH_KEY, spec.finish.error])
	if data.has(CockpitDashPiece.LIST_KEY):
		var parsed: Variant = CockpitDashPiece.parse_list(data[CockpitDashPiece.LIST_KEY])
		if parsed is String:
			return _rejected(parsed)
		spec.dash = parsed
	var window: Vector2 = Vector2(spec.window_half_angle_h_deg, spec.window_half_angle_v_deg)
	for index: int in spec.dash.size():
		var misfit: String = spec.dash[index].fit_error(window, spec.frame_distance_m)
		if misfit != "":
			return _rejected("%s[%d] %s" % [CockpitDashPiece.LIST_KEY, index, misfit])
	return spec


## Reads and parses the file at `path`. A missing file is rejected like bad text.
static func load_file(path: String) -> CockpitSpec:
	if not FileAccess.file_exists(path):
		return _rejected("file %s not found" % path)
	var spec: CockpitSpec = parse_json(FileAccess.get_file_as_string(path))
	if spec.error != "":
		spec.error = "%s: %s" % [path, spec.error]
	return spec


## The cockpit named by `preset`.
static func for_preset(preset: ComfortPreset) -> CockpitSpec:
	return load_file(preset.cockpit_file)


## Solid angle of the window opening in steradians: the patch of the view
## between the two horizontal and the two vertical half-angles. Compares how
## open two cockpits are with a single number.
func window_solid_angle() -> float:
	return 2.0 * deg_to_rad(window_half_angle_h_deg) * 2.0 * sin(deg_to_rad(window_half_angle_v_deg))


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT


## Why `value` is not a colour, or empty when it is one.
static func _color_error(value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 3:
		return "must be an array of three numbers"
	for part: Variant in value:
		if not _is_number(part):
			return "must be an array of three numbers"
		if float(part) < 0.0 or float(part) > 1.0:
			return "has %s, each part must be within 0..1" % part
	return ""


static func _rejected(message: String) -> CockpitSpec:
	var spec: CockpitSpec = CockpitSpec.new()
	spec.error = message
	return spec
