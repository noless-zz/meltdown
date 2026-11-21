class_name GrippedFeelSpec
extends RefCounted

## The gripped stick and throttle's feel values as data (PLT-5, ARC-4): how far
## a grip is pulled to hold a control, and the dead zone and full deflection of
## the stick's tilt and twist and of the throttle's travel. They are first
## guesses waiting on a headset session (gate #56), so they live in
## `res://xr/layouts/gripped_default.json` and can be tuned without code
## (decision record 0003). Button names are not here (decision record 0004).
##
## The file holds degrees and metres; this class turns the angles into radians.
## A file with any value rejected is ignored as a whole and the built-in values
## below are used, so a half-applied file cannot hide which value broke.

const DEFAULT_FILE: String = "res://xr/layouts/gripped_default.json"

## Built-in values, used when the file is missing or rejected. The shipped
## file holds the same numbers, so flying is the same either way.
const DEFAULT_GRIP_HOLD_THRESHOLD: float = 0.5
const DEFAULT_STICK_TILT_DEAD_ZONE_DEG: float = 4.0
const DEFAULT_STICK_TILT_FULL_DEG: float = 30.0
const DEFAULT_STICK_TWIST_DEAD_ZONE_DEG: float = 5.0
const DEFAULT_STICK_TWIST_FULL_DEG: float = 25.0
const DEFAULT_THROTTLE_DEAD_ZONE_M: float = 0.02
const DEFAULT_THROTTLE_FULL_M: float = 0.10

const GRIP_HOLD_THRESHOLD: String = "grip_hold_threshold"
const STICK_TILT_DEAD_ZONE: String = "stick_tilt_dead_zone_deg"
const STICK_TILT_FULL: String = "stick_tilt_full_deg"
const STICK_TWIST_DEAD_ZONE: String = "stick_twist_dead_zone_deg"
const STICK_TWIST_FULL: String = "stick_twist_full_deg"
const THROTTLE_DEAD_ZONE: String = "throttle_dead_zone_m"
const THROTTLE_FULL: String = "throttle_full_m"

## Every key the file must hold, with its allowed range, inclusive. The ranges
## keep a typo from making the controls unusable: a grip that never or always
## holds, a stick that needs a broken wrist, a throttle beyond arm's reach.
const RANGES: Dictionary[String, Array] = {
	GRIP_HOLD_THRESHOLD: [0.1, 0.95],
	STICK_TILT_DEAD_ZONE: [0.0, 20.0],
	STICK_TILT_FULL: [5.0, 80.0],
	STICK_TWIST_DEAD_ZONE: [0.0, 20.0],
	STICK_TWIST_FULL: [5.0, 80.0],
	THROTTLE_DEAD_ZONE: [0.0, 0.1],
	THROTTLE_FULL: [0.02, 0.3],
}
## Each dead zone and the full deflection it must stay below.
const DEAD_ZONE_BELOW: Dictionary[String, String] = {
	STICK_TILT_DEAD_ZONE: STICK_TILT_FULL,
	STICK_TWIST_DEAD_ZONE: STICK_TWIST_FULL,
	THROTTLE_DEAD_ZONE: THROTTLE_FULL,
}

## The file the game reads, loaded once so a rejected file warns once.
static var _shipped: GrippedFeelSpec = null

## Set when the text was rejected; empty otherwise. A rejected spec holds the
## built-in values.
var error: String = ""
var grip_hold_threshold: float = DEFAULT_GRIP_HOLD_THRESHOLD
var stick_tilt_dead_zone_rad: float = deg_to_rad(DEFAULT_STICK_TILT_DEAD_ZONE_DEG)
var stick_tilt_full_rad: float = deg_to_rad(DEFAULT_STICK_TILT_FULL_DEG)
var stick_twist_dead_zone_rad: float = deg_to_rad(DEFAULT_STICK_TWIST_DEAD_ZONE_DEG)
var stick_twist_full_rad: float = deg_to_rad(DEFAULT_STICK_TWIST_FULL_DEG)
var throttle_dead_zone_m: float = DEFAULT_THROTTLE_DEAD_ZONE_M
var throttle_full_m: float = DEFAULT_THROTTLE_FULL_M


## Parses the text of a feel file: one JSON object holding every key in
## `RANGES` as a number in its range, each dead zone below its full deflection,
## and nothing else. On failure the returned spec has `error` set, naming the
## field, and holds the built-in values.
static func parse_json(text: String) -> GrippedFeelSpec:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not RANGES.has(key):
			return _rejected("unknown key \"%s\"" % str(key))
	var values: Dictionary = {}
	for key: String in RANGES:
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
		values[key] = float(value)
	for dead_zone: String in DEAD_ZONE_BELOW:
		var full: String = DEAD_ZONE_BELOW[dead_zone]
		if float(values[dead_zone]) >= float(values[full]):
			return _rejected("key \"%s\" must be below \"%s\"" % [dead_zone, full])
	var spec: GrippedFeelSpec = GrippedFeelSpec.new()
	spec.grip_hold_threshold = values[GRIP_HOLD_THRESHOLD]
	spec.stick_tilt_dead_zone_rad = deg_to_rad(float(values[STICK_TILT_DEAD_ZONE]))
	spec.stick_tilt_full_rad = deg_to_rad(float(values[STICK_TILT_FULL]))
	spec.stick_twist_dead_zone_rad = deg_to_rad(float(values[STICK_TWIST_DEAD_ZONE]))
	spec.stick_twist_full_rad = deg_to_rad(float(values[STICK_TWIST_FULL]))
	spec.throttle_dead_zone_m = values[THROTTLE_DEAD_ZONE]
	spec.throttle_full_m = values[THROTTLE_FULL]
	return spec


## Reads and parses the file at `path`. A missing file is rejected like bad
## text, with the path in `error`.
static func load_file(path: String = DEFAULT_FILE) -> GrippedFeelSpec:
	if not FileAccess.file_exists(path):
		return _rejected("%s: file not found" % path)
	var spec: GrippedFeelSpec = parse_json(FileAccess.get_file_as_string(path))
	if spec.error != "":
		spec.error = "%s: %s" % [path, spec.error]
	return spec


## The shipped file, read on first use. A rejected file is reported once, the
## way a rejected ship tuning file is, and the built-in values are used.
static func shipped() -> GrippedFeelSpec:
	if _shipped == null:
		_shipped = load_file(DEFAULT_FILE)
		if _shipped.error != "":
			print("Meltdown: gripped feel file rejected (%s); using the built-in values" % _shipped.error)
	return _shipped


static func _rejected(message: String) -> GrippedFeelSpec:
	var spec: GrippedFeelSpec = GrippedFeelSpec.new()
	spec.error = message
	return spec
