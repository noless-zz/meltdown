class_name LabelFade
extends RefCounted

## When one hand's control labels fade (issue #147, PLT-5, CMF-4). The labels
## teach the controls, but while flying they cover the tunnel ahead, so they
## fade out once the hand has stayed away from the centre of view for a while
## and come back as soon as the player brings the hand up to look at it.
##
## A hand counts as away when it is more than `away_angle_deg` off the view
## axis. It is view only: the answer is an opacity for the labels, and nothing
## here reads or writes input or ship state (ARC-3).
##
## The numbers are guesses for the G1 headset session and live in
## `res://xr/label_fade.json` so the owner can change them.

const DEFAULT_FILE: String = "res://xr/label_fade.json"

## Seconds the hand must stay away before the labels start to fade, 0.5..60.
var hide_after_s: float = 5.0
## Angle off the view axis, degrees, beyond which the hand is away, 5..90.
var away_angle_deg: float = 25.0
## Seconds a full fade out or in takes, 0.05..5. Short, but not a pop.
var fade_s: float = 0.5

## Every key of the data file, with the same name as the field it sets.
const KEYS: Array[String] = ["hide_after_s", "away_angle_deg", "fade_s"]

## Allowed range of each key, inclusive: [minimum, maximum]. Keep these in
## step with the ranges written on the fields above.
const RANGES: Dictionary[String, Array] = {
	"hide_after_s": [0.5, 60.0],
	"away_angle_deg": [5.0, 90.0],
	"fade_s": [0.05, 5.0],
}

## Set when the text was rejected; empty otherwise.
var error: String = ""

## Seconds the hand has been away without a break.
var _away_s: float = 0.0
## Opacity of the labels now, 0..1. Labels start shown so a new player sees them.
var _alpha: float = 1.0


## Parses the text of a label-fade data file: one JSON object holding every
## key in `KEYS` as a number in its range, and nothing else. On failure the
## returned fade has `error` set, naming the field, and default values.
static func parse_json(text: String) -> LabelFade:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not KEYS.has(key):
			return _rejected("unknown key \"%s\"" % str(key))
	var fade: LabelFade = LabelFade.new()
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
		fade.set(key, float(value))
	return fade


## Reads and parses the file at `path`. A missing file is rejected like bad text.
static func load_file(path: String = DEFAULT_FILE) -> LabelFade:
	if not FileAccess.file_exists(path):
		return _rejected("file %s not found" % path)
	var fade: LabelFade = parse_json(FileAccess.get_file_as_string(path))
	if fade.error != "":
		fade.error = "%s: %s" % [path, fade.error]
	return fade


## Degrees between the view axis of `view` (looking along its -z) and the
## direction from the eye to `point`. A point at the eye counts as centred.
static func angle_off_view(view: Transform3D, point: Vector3) -> float:
	var to_point: Vector3 = point - view.origin
	if to_point.is_zero_approx():
		return 0.0
	var forward: Vector3 = -view.basis.z
	if forward.is_zero_approx():
		return 0.0
	return rad_to_deg(forward.angle_to(to_point))


## True when a hand `angle_deg` off the view axis counts as near the centre.
func is_near_centre(angle_deg: float) -> bool:
	return angle_deg <= away_angle_deg


## Advances by `delta` seconds with the hand `angle_deg` off the view axis and
## returns the labels' opacity for the frame.
func advance(delta: float, angle_deg: float) -> float:
	var step: float = maxf(delta, 0.0)
	if is_near_centre(angle_deg):
		_away_s = 0.0
	else:
		_away_s += step
	var target: float = 0.0 if _away_s >= hide_after_s else 1.0
	_alpha = move_toward(_alpha, target, step / fade_s)
	return _alpha


## The labels' opacity now, 0..1, without advancing time.
func alpha() -> float:
	return _alpha


static func _rejected(message: String) -> LabelFade:
	var fade: LabelFade = LabelFade.new()
	fade.error = message
	return fade
