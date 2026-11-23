class_name ReactorMachineLook
extends RefCounted

## Parses the `"machine"` object of `res://view/reactor_look.json` (#1310,
## GFX-2, ARC-4): the reactor drawn as a machine built from primitives around
## its glowing core. Without the object the reactor keeps its earlier look, a
## bare glowing sphere. Inside it every key is optional and falls back to
## `DEFAULTS`, so a file written before a key existed still loads.
##
## Sizes ending in `_r` are fractions of the reactor's radius, so one look fits
## every reactor; `pipe_max_length_m` is in metres because pipes run to the
## walls, whose distance does not grow with the reactor.
##
##     {"core_scale_r": .., "housing_radius_r": .., "housing_height_r": ..,
##      "ribs": n, "rib_width_r": .., "rib_depth_r": .., "cap_radius_r": ..,
##      "cap_height_r": .., "pipes": n, "pipe_radius_r": .., "pipe_angle_deg": ..,
##      "pipe_height_r": .., "pipe_max_length_m": .., "breached_ribs": n,
##      "wreck_cap_tilt_deg": .., "flame_amount": n, "flame_lifetime": s,
##      "flame_height_r": .., "flame_size_r": .., "ember_amount": n,
##      "flame_hot_color": [r, g, b], "flame_cool_color": [r, g, b],
##      "housing_material": {"color": [r, g, b], "metallic": 0..1, "roughness": 0..1},
##      "pipe_material": {..}, "scorched_material": {..}}

## Inclusive ranges; a key listed in `WHOLE_KEYS` must also be a whole number.
const RANGES: Dictionary[String, Array] = {
	# Small enough that the core shows between the ribs, never larger than the
	# reactor's own sphere.
	"core_scale_r": [0.2, 1.0],
	"housing_radius_r": [0.5, 1.5],
	"housing_height_r": [0.5, 3.0],
	"ribs": [3, 16],
	"rib_width_r": [0.05, 0.6],
	"rib_depth_r": [0.02, 0.5],
	"cap_radius_r": [0.5, 1.8],
	"cap_height_r": [0.05, 0.8],
	"pipes": [0, 8],
	"pipe_radius_r": [0.02, 0.4],
	"pipe_angle_deg": [0.0, 360.0],
	"pipe_height_r": [-1.5, 1.5],
	"pipe_max_length_m": [1.0, 60.0],
	"breached_ribs": [0, 16],
	"wreck_cap_tilt_deg": [0.0, 60.0],
	"flame_amount": [0, 256],
	"flame_lifetime": [0.2, 3.0],
	"flame_height_r": [0.2, 4.0],
	"flame_size_r": [0.05, 1.5],
	"ember_amount": [0, 256],
}
const WHOLE_KEYS: Array[String] = ["ribs", "pipes", "breached_ribs", "flame_amount", "ember_amount"]
const COLOR_KEYS: Array[String] = ["flame_hot_color", "flame_cool_color"]
const MATERIAL_KEYS: Array[String] = ["housing_material", "pipe_material", "scorched_material"]
const MATERIAL_FIELDS: Array[String] = ["color", "metallic", "roughness"]

## The look used for every key the file leaves out; matches the shipped file.
const DEFAULTS: Dictionary = {
	"core_scale_r": 0.55,
	"housing_radius_r": 0.95,
	"housing_height_r": 1.8,
	"ribs": 8,
	"rib_width_r": 0.22,
	"rib_depth_r": 0.14,
	"cap_radius_r": 1.05,
	"cap_height_r": 0.22,
	"pipes": 4,
	"pipe_radius_r": 0.12,
	"pipe_angle_deg": 45.0,
	"pipe_height_r": -0.45,
	"pipe_max_length_m": 24.0,
	"breached_ribs": 3,
	"wreck_cap_tilt_deg": 22.0,
	"flame_amount": 48,
	"flame_lifetime": 0.9,
	"flame_height_r": 1.8,
	"flame_size_r": 0.35,
	"ember_amount": 24,
	"flame_hot_color": Color(1.0, 0.85, 0.4),
	"flame_cool_color": Color(0.9, 0.25, 0.05),
	"housing_material": {"color": Color(0.32, 0.34, 0.36), "metallic": 0.85, "roughness": 0.45},
	"pipe_material": {"color": Color(0.45, 0.38, 0.3), "metallic": 0.7, "roughness": 0.6},
	"scorched_material": {"color": Color(0.08, 0.07, 0.06), "metallic": 0.3, "roughness": 0.95},
}


## The machine look with every key filled, colours as `Color`, or a dictionary
## holding only `"error"`, which names the key.
static func parse(data: Variant) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY:
		return _rejected("\"machine\" must be a JSON object")
	var given: Dictionary = data
	for key: Variant in given:
		if typeof(key) != TYPE_STRING or not DEFAULTS.has(key):
			return _rejected("machine: unknown key \"%s\"" % str(key))
	var look: Dictionary = DEFAULTS.duplicate(true)
	for key: String in RANGES:
		if not given.has(key):
			continue
		var value: Variant = given[key]
		# A bool must not pass as 0 or 1.
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return _rejected("machine: \"%s\" must be a number" % key)
		var bounds: Array = RANGES[key]
		if float(value) < float(bounds[0]) or float(value) > float(bounds[1]):
			return _rejected("machine: \"%s\" is %s, must be within %s..%s" % [key, value, bounds[0], bounds[1]])
		if WHOLE_KEYS.has(key):
			if float(value) != floorf(float(value)):
				return _rejected("machine: \"%s\" must be a whole number" % key)
			look[key] = int(value)
		else:
			look[key] = float(value)
	for key: String in COLOR_KEYS:
		if given.has(key):
			var color: Variant = _color(given[key])
			if color == null:
				return _rejected("machine: \"%s\" must be [red, green, blue] within 0..1" % key)
			look[key] = color
	for key: String in MATERIAL_KEYS:
		if given.has(key):
			var material: Variant = _material(given[key], DEFAULTS[key])
			if material is String:
				return _rejected("machine: \"%s\" %s" % [key, material])
			look[key] = material
	if int(look["breached_ribs"]) >= int(look["ribs"]):
		return _rejected("machine: \"breached_ribs\" is %d, must leave at least one of %d ribs" % [look["breached_ribs"], look["ribs"]])
	return look


## `[r, g, b]` within 0..1 as a `Color`, or null.
static func _color(parts: Variant) -> Variant:
	if typeof(parts) != TYPE_ARRAY or (parts as Array).size() != 3:
		return null
	for part: Variant in parts:
		if typeof(part) != TYPE_FLOAT and typeof(part) != TYPE_INT:
			return null
		if float(part) < 0.0 or float(part) > 1.0:
			return null
	return Color(float(parts[0]), float(parts[1]), float(parts[2]))


## A material object with missing fields from `fallback`, or a String saying
## what is wrong.
static func _material(data: Variant, fallback: Dictionary) -> Variant:
	if typeof(data) != TYPE_DICTIONARY:
		return "must be an object"
	var given: Dictionary = data
	for field: Variant in given:
		if not MATERIAL_FIELDS.has(field):
			return "has an unknown field \"%s\"" % str(field)
	var material: Dictionary = fallback.duplicate()
	if given.has("color"):
		var color: Variant = _color(given["color"])
		if color == null:
			return "colour must be [red, green, blue] within 0..1"
		material["color"] = color
	for field: String in ["metallic", "roughness"]:
		if given.has(field):
			var value: Variant = given[field]
			if (typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT) or float(value) < 0.0 or float(value) > 1.0:
				return "%s must be a number within 0..1" % field
			material[field] = float(value)
	return material


static func _rejected(message: String) -> Dictionary:
	return {"error": message}
