class_name DebrisLook
extends RefCounted

## Parses `res://view/debris_look.json`, the look of meltdown debris (RUN-4,
## ARC-4), so colours, glow and the warning time can be retuned without code.
## Kept apart from `DebrisView` so the node stays small.
##
##     {"solid_color": [r, g, b], "solid_energy": 0..16,
##      "warn_color": [r, g, b], "warn_energy": 0..16, "warn_alpha": 0..1,
##      "warn_seconds": 0.5..10,
##      "held_color": [r, g, b], "held_energy": 0..16, "held_alpha": 0..1,
##      "slab_color": [r, g, b], "slab_energy": 0..16,
##      "slab_warn_color": [r, g, b], "slab_warn_energy": 0..16,
##      "slab_warn_alpha": 0..1}
##
## Energies are emission multipliers. A held entry never became solid, so it
## is drawn see-through (`held_alpha`): an opaque rock there would show a
## sealed tunnel where the route is open. Debris carries a faint glow of its own
## because the mine is dark (LGT-1) and an unlit rock in a tunnel reads as
## nothing until the ship hits it.
##
## Box entries (blast doors, cave-in slabs, #459) have their own `slab_*`
## colours: a flat grey-metal slab and a hazard-yellow warning, so a door about
## to slam reads differently from a rock about to fall. They share
## `warn_seconds` with spheres, so both warn equally early.

const DEFAULT_FILE: String = "res://view/debris_look.json"

const COLOR_KEYS: Array[String] = ["solid_color", "warn_color", "held_color", "slab_color",
	"slab_warn_color"]
## Inclusive ranges of the number keys.
const RANGES: Dictionary[String, Array] = {
	"solid_energy": [0.0, 16.0],
	"warn_energy": [0.0, 16.0],
	"warn_alpha": [0.0, 1.0],
	# Under half a second the warning is gone before the player can react;
	# over ten it stops reading as "about to fall".
	"warn_seconds": [0.5, 10.0],
	"held_energy": [0.0, 16.0],
	"held_alpha": [0.0, 1.0],
	"slab_energy": [0.0, 16.0],
	"slab_warn_energy": [0.0, 16.0],
	"slab_warn_alpha": [0.0, 1.0],
}

## Look used when the file is missing or rejected; matches the shipped file.
const FALLBACK: Dictionary = {
	"solid_color": Color(0.32, 0.27, 0.22),
	"solid_energy": 0.15,
	"warn_color": Color(1.0, 0.45, 0.1),
	"warn_energy": 1.5,
	"warn_alpha": 0.35,
	"warn_seconds": 3.0,
	"held_color": Color(0.55, 0.5, 0.42),
	"held_energy": 0.3,
	"held_alpha": 0.3,
	"slab_color": Color(0.36, 0.36, 0.38),
	"slab_energy": 0.15,
	"slab_warn_color": Color(1.0, 0.8, 0.1),
	"slab_warn_energy": 1.5,
	"slab_warn_alpha": 0.3,
}


## Returns the look with colours as `Color` and numbers as floats, or a
## dictionary holding only `"error"`, which names the key.
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
	return look


static func _rejected(message: String) -> Dictionary:
	return {"error": message}
