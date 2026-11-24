class_name DebrisEffectsLook
extends RefCounted

## Parses `res://view/debris_effects_look.json`, the meltdown fire and debris
## look on top of `DebrisLook` (#1331, GFX-2, GFX-6, ARC-4): particle flames on
## burning fire, dust when debris lands, and rock and metal surfaces taken from
## the theme's walls (#1292). Every section is optional; a missing section
## leaves that part as it was before this file, so a missing key falls back to
## today's look. A rejected file gives no section at all.
##
##     {"fire_flames": {"amount": 0..64, "ember_amount": 0..32,
##        "lifetime": 0.2..3, "height_r": 0.2..4, "size_r": 0.05..2,
##        "hot_color": [r, g, b], "cool_color": [r, g, b]},
##      "dust": {"amount": 0..64, "lifetime": 0.2..4, "size_r": 0.05..2,
##        "spread_r": 0.1..4, "color": [r, g, b], "alpha": 0..1},
##      "rock": {"wall_mix": 0..1},
##      "metal": {"wall_mix": 0..1}}
##
## Sizes ending `_r` are in units of the entry's radius (a box's half width).
## - `fire_flames`: flames rise `height_r` over `lifetime`, fading from
##   `hot_color` to `cool_color`; `ember_amount` embers rise higher. Both stay
##   in the fire's cold blue (`test_look_hues`, #1208).
## - `dust`: one puff of `amount` motes, thrown `spread_r` outwards as a rock
##   or slab comes down, settling over `lifetime`.
## - `rock` (spheres) and `metal` (slabs): the solid colour moves `wall_mix`
##   of the way to the theme's wall tint; rock takes the walls' roughness,
##   metal the theme's `metallic` and `metal_roughness`.

const DEFAULT_FILE: String = "res://view/debris_effects_look.json"

## Every key of every section, with its inclusive range; colours are
## listed in `COLOR_KEYS` instead. Integer keys are in `INT_KEYS`.
const RANGES: Dictionary[String, Dictionary] = {
	"fire_flames": {"amount": [0.0, 64.0], "ember_amount": [0.0, 32.0],
		"lifetime": [0.2, 3.0], "height_r": [0.2, 4.0], "size_r": [0.05, 2.0]},
	"dust": {"amount": [0.0, 64.0], "lifetime": [0.2, 4.0], "size_r": [0.05, 2.0],
		"spread_r": [0.1, 4.0], "alpha": [0.0, 1.0]},
	"rock": {"wall_mix": [0.0, 1.0]},
	"metal": {"wall_mix": [0.0, 1.0]},
}
const COLOR_KEYS: Dictionary[String, Array] = {
	"fire_flames": ["hot_color", "cool_color"],
	"dust": ["color"],
	"rock": [],
	"metal": [],
}
const INT_KEYS: Array[String] = ["amount", "ember_amount"]


## The sections present, each with colours as `Color` and numbers as float
## (int for counts), or a dictionary holding only `"error"` naming the key.
static func parse(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	var look: Dictionary = {}
	for section: Variant in data:
		if typeof(section) != TYPE_STRING or not RANGES.has(section):
			return _rejected("unknown section \"%s\"" % str(section))
		if typeof(data[section]) != TYPE_DICTIONARY:
			return _rejected("\"%s\" must be an object" % section)
		var parsed: Variant = _parse_section(section, data[section])
		if typeof(parsed) == TYPE_STRING:
			return _rejected(parsed)
		look[section] = parsed
	return look


## The look in the file at `path`; empty (today's look) after a warning
## when the file is missing or rejected.
static func load_or_empty(path: String = DEFAULT_FILE) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("debris effects off: %s: file not found" % path)
		return {}
	var look: Dictionary = parse(FileAccess.get_file_as_string(path))
	if look.has("error"):
		push_warning("debris effects off: %s: %s" % [path, look["error"]])
		return {}
	return look


## The parsed section, or a String naming the bad key.
static func _parse_section(section: String, raw: Dictionary) -> Variant:
	var ranges: Dictionary = RANGES[section]
	var colors: Array = COLOR_KEYS[section]
	for key: Variant in raw:
		if not ranges.has(key) and not colors.has(key):
			return "unknown key \"%s.%s\"" % [section, str(key)]
	var values: Dictionary = {}
	for key: String in colors:
		var parts: Variant = raw.get(key)
		if typeof(parts) != TYPE_ARRAY or (parts as Array).size() != 3:
			return "\"%s.%s\" must be [red, green, blue]" % [section, key]
		for part: Variant in parts:
			if (typeof(part) != TYPE_FLOAT and typeof(part) != TYPE_INT) or float(part) < 0.0 or float(part) > 1.0:
				return "\"%s.%s\" must hold numbers within 0..1" % [section, key]
		values[key] = Color(float(parts[0]), float(parts[1]), float(parts[2]))
	for key: String in ranges:
		var value: Variant = raw.get(key)
		# A bool must not pass as 0 or 1.
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return "\"%s.%s\" must be a number" % [section, key]
		var bounds: Array = ranges[key]
		if float(value) < float(bounds[0]) or float(value) > float(bounds[1]):
			return "\"%s.%s\" is %s, must be within %s..%s" % [section, key, value, bounds[0], bounds[1]]
		if INT_KEYS.has(key):
			if float(value) != floorf(float(value)):
				return "\"%s.%s\" must be a whole number" % [section, key]
			values[key] = int(value)
		else:
			values[key] = float(value)
	return values


static func _rejected(message: String) -> Dictionary:
	return {"error": message}
