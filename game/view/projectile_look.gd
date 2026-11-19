class_name ProjectileLook
extends RefCounted

## Parses `res://view/projectile_look.json`, the look of bolts, their muzzles
## and their flashes (CMB-1, LGT-1, ARC-4), so it can be retuned without code.
## Kept apart from `ProjectileView` so the node stays small.
##
## Bolts leave from two muzzles, low left and low right ahead of the eye
## (#602): `muzzle_side_m` to each side, `muzzle_drop_m` down and
## `muzzle_forward_m` ahead, in the ship's own axes. The drawn bolt closes onto
## the simulated line, which starts at the ship's centre, within `converge_m`
## of flight. Flashes last `*_flash_s` seconds; 0 turns that flash off.

const DEFAULT_FILE: String = "res://view/projectile_look.json"

## Every key of the look file, with the same name as the view field it sets.
const KEYS: Array[String] = [
	"bolt_length_m", "bolt_radius_m", "emission_color", "max_lights", "light_range", "light_energy",
	"muzzle_side_m", "muzzle_drop_m", "muzzle_forward_m", "converge_m",
	"muzzle_flash_radius_m", "muzzle_flash_s",
	"impact_color", "impact_flash_radius_m", "impact_flash_s",
]
## Keys holding [red, green, blue].
const COLOR_KEYS: Array[String] = ["emission_color", "impact_color"]
## Keys that must hold a whole number.
const WHOLE_KEYS: Array[String] = ["max_lights"]

## Allowed range of each number, inclusive: [minimum, maximum]. For a colour
## the range holds for each of its red, green and blue parts.
const RANGES: Dictionary[String, Array] = {
	"bolt_length_m": [0.05, 5.0],
	"bolt_radius_m": [0.005, 0.5],
	"emission_color": [0.0, 1.0],
	# The mobile renderer the Quest uses lights a mesh with at most 8 omni
	# lights, so a larger budget would only cost time without lighting more.
	"max_lights": [0, 8],
	"light_range": [0.5, 30.0],
	"light_energy": [0.0, 16.0],
	"muzzle_side_m": [0.0, 1.0],
	"muzzle_drop_m": [0.0, 1.0],
	# At least this far ahead, so a bolt never starts at the pilot's eye.
	"muzzle_forward_m": [0.35, 2.0],
	"converge_m": [0.5, 20.0],
	"muzzle_flash_radius_m": [0.01, 0.5],
	"muzzle_flash_s": [0.0, 0.5],
	"impact_color": [0.0, 1.0],
	"impact_flash_radius_m": [0.01, 2.0],
	"impact_flash_s": [0.0, 1.0],
}

## The look used when the file is missing or rejected; the shipped file holds
## the same values.
const DEFAULTS: Dictionary[String, Variant] = {
	"bolt_length_m": 0.6,
	"bolt_radius_m": 0.03,
	"emission_color": Color(1.0, 0.55, 0.15),
	"max_lights": 4,
	"light_range": 6.0,
	"light_energy": 1.5,
	"muzzle_side_m": 0.3,
	"muzzle_drop_m": 0.25,
	"muzzle_forward_m": 0.6,
	"converge_m": 4.0,
	"muzzle_flash_radius_m": 0.08,
	"muzzle_flash_s": 0.06,
	"impact_color": Color(1.0, 0.85, 0.55),
	"impact_flash_radius_m": 0.3,
	"impact_flash_s": 0.15,
}


## Parses the text of a look file: one JSON object holding every key in
## `KEYS`, the numbers in their ranges and each colour as three numbers.
## Returns the values by key, or a dictionary holding only `"error"`, which
## names the field.
static func parse(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not KEYS.has(key):
			return _rejected("unknown key \"%s\"" % str(key))
	var values: Dictionary = {}
	for key: String in KEYS:
		if not data.has(key):
			return _rejected("missing key \"%s\"" % key)
		var parts: Array = [data[key]]
		if COLOR_KEYS.has(key):
			if typeof(data[key]) != TYPE_ARRAY or (data[key] as Array).size() != 3:
				return _rejected("key \"%s\" must be [red, green, blue]" % key)
			parts = data[key]
		for value: Variant in parts:
			# A bool must not pass as 0 or 1.
			if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
				return _rejected("key \"%s\" must hold numbers" % key)
			if WHOLE_KEYS.has(key) and float(value) != floorf(float(value)):
				return _rejected("key \"%s\" must be a whole number" % key)
			var low: float = RANGES[key][0]
			var high: float = RANGES[key][1]
			if float(value) < low or float(value) > high:
				return _rejected("key \"%s\" has %s, must be within %s..%s" % [key, value, low, high])
		if COLOR_KEYS.has(key):
			values[key] = Color(float(parts[0]), float(parts[1]), float(parts[2]))
		elif WHOLE_KEYS.has(key):
			values[key] = int(data[key])
		else:
			values[key] = float(data[key])
	return values


static func _rejected(message: String) -> Dictionary:
	return {"error": message}
