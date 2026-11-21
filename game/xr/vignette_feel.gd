class_name VignetteFeel
extends RefCounted

## How the comfort vignette eases towards the strength the comfort table asks
## for (CMF-1, #931). `ComfortVignette.strength` answers from one frame's
## motion, which steps whenever a tick lands; shown raw it would flicker and
## could go from nothing to full in one frame. This eases it with a time
## constant instead.
##
## View only: it turns one number into another and never reads input or ship
## state (ARC-3, CMF-6). The time constant is a guess for the headset session
## and lives in `res://xr/vignette_feel.json` so the owner can tune it.

const DEFAULT_FILE: String = "res://xr/vignette_feel.json"

## Seconds for the shown strength to cover about 63% of the way to the asked
## strength, 0.01..2.
var smooth_seconds: float = 0.15

## Every key of the data file, with the same name as the field it sets.
const KEYS: Array[String] = ["smooth_seconds"]

## Allowed range of each key, inclusive: [minimum, maximum].
const RANGES: Dictionary[String, Array] = {
	"smooth_seconds": [0.01, 2.0],
}

## Set when the text was rejected; empty otherwise.
var error: String = ""


## The strength shown after `delta` seconds of easing from `shown` towards
## `target`. Exponential, so a frame at any refresh rate covers the same share
## of the way per second, and it never overshoots.
func step(shown: float, target: float, delta: float) -> float:
	if delta <= 0.0:
		return shown
	return lerpf(shown, target, 1.0 - exp(-delta / smooth_seconds))


## Parses a vignette-feel data file: one JSON object holding every key in
## `KEYS` as a number in its range, and nothing else. On failure the returned
## feel has `error` set, naming the field, and the default values.
static func parse_json(text: String) -> VignetteFeel:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not KEYS.has(key):
			return _rejected("unknown key \"%s\"" % str(key))
	var feel: VignetteFeel = VignetteFeel.new()
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
		feel.set(key, float(value))
	return feel


## Reads and parses the file at `path`. A missing file is rejected like bad text.
static func load_file(path: String = DEFAULT_FILE) -> VignetteFeel:
	if not FileAccess.file_exists(path):
		return _rejected("file %s not found" % path)
	var feel: VignetteFeel = parse_json(FileAccess.get_file_as_string(path))
	if feel.error != "":
		feel.error = "%s: %s" % [path, feel.error]
	return feel


static func _rejected(message: String) -> VignetteFeel:
	var feel: VignetteFeel = VignetteFeel.new()
	feel.error = message
	return feel
