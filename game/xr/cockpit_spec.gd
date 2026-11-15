class_name CockpitSpec
extends RefCounted

## The shape of one cockpit frame, read from a JSON data file in
## `res://xr/cockpits/` (CMF-1, ARC-4). Each comfort preset names its file
## through `ComfortPreset.cockpit_file`.
##
## A frame is a fixed visual reference around the eye point that reduces
## vection. It belongs to the view only: nothing here is read by the
## simulation (ARC-3, CMF-6). The numbers are guesses for the G1 headset
## session and live in the data files so the owner can change them.
##
## Angles are measured from straight ahead: a window half-angle of 90 degrees
## opens the whole forward half of the view along that axis.

## Half the window's width, degrees from straight ahead, 10..90.
var window_half_angle_h_deg: float = 90.0
## Half the window's height, degrees from straight ahead, 10..90.
var window_half_angle_v_deg: float = 90.0
## Width and depth of the struts around the window, metres, 0.005..0.05.
var strut_width_m: float = 0.01
## Distance of the frame's shell from the eye point, metres, 0.3..0.95. With
## the widest strut the nearest surface stays beyond 0.25 m, so the camera's
## near plane never cuts it (#102), and the shell stays inside the ship's 1 m
## collision radius.
var frame_distance_m: float = 0.6
## Opacity of the canopy glass inside the window, 0..1; 0 leaves no glass.
var glass_tint_alpha: float = 0.05

## Every key of the data file, with the same name as the field it sets.
const KEYS: Array[String] = [
	"window_half_angle_h_deg", "window_half_angle_v_deg", "strut_width_m",
	"frame_distance_m", "glass_tint_alpha",
]

## Allowed range of each key, inclusive: [minimum, maximum]. Keep these in
## step with the ranges written on the fields above.
const RANGES: Dictionary[String, Array] = {
	"window_half_angle_h_deg": [10.0, 90.0],
	"window_half_angle_v_deg": [10.0, 90.0],
	"strut_width_m": [0.005, 0.05],
	"frame_distance_m": [0.3, 0.95],
	"glass_tint_alpha": [0.0, 1.0],
}

## Set when the text was rejected; empty otherwise.
var error: String = ""


## Parses the text of a cockpit data file: one JSON object holding every key
## in `KEYS` as a number in its range, and nothing else. A missing or unknown
## key is an error, so a typo cannot leave a value silently at its default.
## On failure the returned spec has `error` set, naming the field, and
## default values.
static func parse_json(text: String) -> CockpitSpec:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not KEYS.has(key):
			return _rejected("unknown key \"%s\"" % str(key))
	var spec: CockpitSpec = CockpitSpec.new()
	for key: String in KEYS:
		if not data.has(key):
			return _rejected("missing key \"%s\"" % key)
		var value: Variant = data[key]
		# A bool must not pass as 0 or 1.
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return _rejected("key \"%s\" must be a number" % key)
		var low: float = RANGES[key][0]
		var high: float = RANGES[key][1]
		if float(value) < low or float(value) > high:
			return _rejected("key \"%s\" is %s, must be within %s..%s" % [key, value, low, high])
		spec.set(key, float(value))
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


static func _rejected(message: String) -> CockpitSpec:
	var spec: CockpitSpec = CockpitSpec.new()
	spec.error = message
	return spec
