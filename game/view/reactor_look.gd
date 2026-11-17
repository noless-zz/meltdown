class_name ReactorLook
extends RefCounted

## Parses `res://view/reactor_look.json`, the look of the reactor (ARC-4), so
## colours, energies, pulse rates and the light's reach can be retuned
## without code. Kept apart from `ReactorView` so the node stays small.
##
##     {"core_color": [r, g, b], "core_energy": 0..16,
##      "wreck_color": [r, g, b], "wreck_energy": 0..16,
##      "light_color": [r, g, b], "meltdown_light_color": [r, g, b],
##      "light_energy": 0..16, "light_range": 0.5..30, "pulse_depth": 0..1,
##      "pulse_period_full_hull": s, "pulse_period_no_hull": s,
##      "flicker_period_slow": s, "flicker_period_fast": s,
##      "flicker_ramp_seconds": 1..600}
##
## Periods are seconds per full pulse or flicker. The faster one of each pair
## must not be slower than the other.

const DEFAULT_FILE: String = "res://view/reactor_look.json"

const COLOR_KEYS: Array[String] = ["core_color", "wreck_color", "light_color", "meltdown_light_color"]
## Inclusive ranges of the number keys.
const RANGES: Dictionary[String, Array] = {
	"core_energy": [0.0, 16.0],
	"wreck_energy": [0.0, 16.0],
	"light_energy": [0.0, 16.0],
	"light_range": [0.5, 30.0],
	"pulse_depth": [0.0, 1.0],
	# The shortest period is 0.34 s, under three flashes a second: faster
	# flashing over a large part of the view is a known photosensitivity
	# trigger, and the flicker must stay comfortable at preset 1 (CMF-3).
	"pulse_period_full_hull": [0.34, 10.0],
	"pulse_period_no_hull": [0.34, 10.0],
	"flicker_period_slow": [0.34, 10.0],
	"flicker_period_fast": [0.34, 10.0],
	"flicker_ramp_seconds": [1.0, 600.0],
}
## Pairs of `[fast, slow]` periods; the fast one must be the shorter or equal.
const ORDERED_PAIRS: Array[Array] = [
	["pulse_period_no_hull", "pulse_period_full_hull"],
	["flicker_period_fast", "flicker_period_slow"],
]

## Look used when the file is missing or rejected; matches the shipped file.
const FALLBACK: Dictionary = {
	"core_color": Color(1.0, 0.55, 0.15),
	"core_energy": 3.0,
	"wreck_color": Color(0.35, 0.08, 0.05),
	"wreck_energy": 0.8,
	"light_color": Color(1.0, 0.6, 0.25),
	"meltdown_light_color": Color(1.0, 0.2, 0.1),
	"light_energy": 2.0,
	"light_range": 14.0,
	"pulse_depth": 0.5,
	"pulse_period_full_hull": 3.0,
	"pulse_period_no_hull": 0.8,
	"flicker_period_slow": 1.2,
	"flicker_period_fast": 0.4,
	"flicker_ramp_seconds": 60.0,
}


## Returns the look with colours as `Color` and numbers as floats, or a
## dictionary holding only `"error"`, which names the field.
static func parse(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not FALLBACK.has(key):
			return _rejected("unknown key \"%s\"" % str(key))
	for key: String in FALLBACK:
		if not data.has(key):
			return _rejected("missing key \"%s\"" % key)
	var look: Dictionary = {}
	for key: String in COLOR_KEYS:
		var parts: Variant = data[key]
		if typeof(parts) != TYPE_ARRAY or (parts as Array).size() != 3:
			return _rejected("\"%s\" must be [red, green, blue]" % key)
		for part: Variant in parts:
			if typeof(part) != TYPE_FLOAT and typeof(part) != TYPE_INT:
				return _rejected("\"%s\" must hold numbers" % key)
			if float(part) < 0.0 or float(part) > 1.0:
				return _rejected("\"%s\" has %s, must be within 0..1" % [key, part])
		look[key] = Color(float(parts[0]), float(parts[1]), float(parts[2]))
	for key: String in RANGES:
		var value: Variant = data[key]
		# A bool must not pass as 0 or 1.
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return _rejected("\"%s\" must be a number" % key)
		var bounds: Array = RANGES[key]
		if float(value) < float(bounds[0]) or float(value) > float(bounds[1]):
			return _rejected("\"%s\" is %s, must be within %s..%s" % [key, value, bounds[0], bounds[1]])
		look[key] = float(value)
	for pair: Array in ORDERED_PAIRS:
		if float(look[pair[0]]) > float(look[pair[1]]):
			return _rejected("\"%s\" is %s, must not be longer than \"%s\" (%s)" % [pair[0], look[pair[0]], pair[1], look[pair[1]]])
	return look


static func _rejected(message: String) -> Dictionary:
	return {"error": message}
