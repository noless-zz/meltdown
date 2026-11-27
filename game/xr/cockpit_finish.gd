class_name CockpitFinish
extends RefCounted

## The physically based finish of a cockpit's surfaces (#1306, GFX-2, ARC-4):
## how rough and how metallic each surface is, how deep its panel seams and
## how high its bolts stand in the shading normal, and how worn it is; and the
## faint edge reflection of the canopy glass. Read from the optional
## `"finish"` object of each cockpit data file in `res://xr/cockpits/`.
##
## Every key is optional. A missing key, surface or `"finish"` object takes
## its `NEUTRAL` value, and `NEUTRAL` draws the cockpit exactly as before
## #1306: rough, not metallic, flat, unworn, and glass without a reflection.
## The base colours stay `CockpitSpec`'s, the panel pattern `CockpitLook`'s.
##
## View only, like the rest of the frame (ARC-3, CMF-6).

## The surfaces with a finish of their own: the shell round the window, the
## dashboard ledge (and the dash pieces on it), the pillars and the rim.
const SURFACES: Array[String] = ["frame", "ledge", "pillars", "rim"]
## Which surface finishes each built part (`CockpitFrame.PARTS`).
const PART_SURFACE: Dictionary[String, String] = {
	"Solid": "frame", "Ledge": "ledge", "Pillars": "pillars", "Rim": "rim",
	"Dash": "ledge", "Knobs": "ledge",
}

## Each surface's keys, today's look, and allowed range [minimum, maximum].
const SURFACE_NEUTRAL: Dictionary[String, float] = {
	"roughness": 0.75,
	"metallic": 0.0,
	# Depth of the panel seams in the shading normal, metres; 0 is flat.
	"seam_depth_m": 0.0,
	# Height of the bolts (`CockpitLook.rivet_size`) in the shading normal, metres.
	"bolt_height_m": 0.0,
	# Share of the surface rubbed to bare metal: lighter, smoother, more metallic.
	"wear": 0.0,
}
const SURFACE_RANGES: Dictionary[String, Array] = {
	"roughness": [0.05, 1.0],
	"metallic": [0.0, 1.0],
	"seam_depth_m": [0.0, 0.004],
	"bolt_height_m": [0.0, 0.004],
	"wear": [0.0, 1.0],
}
## The keys beside the surfaces, today's look and their ranges.
const NEUTRAL: Dictionary[String, float] = {
	# Size of a worn patch, metres.
	"wear_scale_m": 0.05,
	# Opacity the glass's reflection adds at the window's edge, 0 for none. It
	# fades to nothing at the centre, so `1 - glass_transmission` stays the opacity
	# straight ahead. At most 0.3, so the glass never hides the view.
	"glass_fresnel": 0.0,
	# How fast the reflection fades toward the centre: higher keeps it nearer the edge.
	"glass_fresnel_power": 3.0,
}
const RANGES: Dictionary[String, Array] = {
	"wear_scale_m": [0.01, 0.3],
	"glass_fresnel": [0.0, 0.3],
	"glass_fresnel_power": [1.0, 8.0],
}
const COLOR_KEY: String = "glass_fresnel_color"
const NEUTRAL_COLOR: Color = Color(0.75, 0.85, 1.0)

## Every surface's values by surface name, then key.
var surfaces: Dictionary[String, Dictionary] = {}
var wear_scale_m: float = NEUTRAL["wear_scale_m"]
var glass_fresnel: float = NEUTRAL["glass_fresnel"]
var glass_fresnel_power: float = NEUTRAL["glass_fresnel_power"]
var glass_fresnel_color: Color = NEUTRAL_COLOR

## Set when the data was rejected; empty otherwise.
var error: String = ""


func _init() -> void:
	for surface: String in SURFACES:
		surfaces[surface] = SURFACE_NEUTRAL.duplicate()


## Value `key` (a key of `SURFACE_NEUTRAL`) of the surface that finishes part
## `part_name`; the neutral value for a part with no surface.
func value(part_name: String, key: String) -> float:
	var surface: String = PART_SURFACE.get(part_name, "")
	if surface == "":
		return SURFACE_NEUTRAL[key]
	return surfaces[surface][key]


## Parses the `"finish"` object of a cockpit data file: any of the keys, each
## in range, and nothing unknown. On failure `error` names the field.
static func parse(data_value: Variant) -> CockpitFinish:
	if typeof(data_value) != TYPE_DICTIONARY:
		return _rejected("must be a JSON object")
	var data: Dictionary = data_value
	var finish: CockpitFinish = CockpitFinish.new()
	for key: Variant in data:
		if typeof(key) != TYPE_STRING:
			return _rejected("unknown key \"%s\"" % str(key))
		var problem: String = ""
		if SURFACES.has(key):
			var surface_error: String = finish._parse_surface(key, data[key])
			if surface_error != "":
				return _rejected(surface_error)
		elif RANGES.has(key):
			problem = _number_error(data[key], RANGES[key])
			if problem == "":
				finish.set(key, float(data[key]))
		elif key == COLOR_KEY:
			problem = CockpitSpec._color_error(data[key])
			if problem == "":
				var parts: Array = data[key]
				finish.glass_fresnel_color = Color(float(parts[0]), float(parts[1]), float(parts[2]))
		else:
			problem = "is not a key of the finish"
		if problem != "":
			return _rejected("key \"%s\" %s" % [key, problem])
	return finish


func _parse_surface(surface: String, raw: Variant) -> String:
	if typeof(raw) != TYPE_DICTIONARY:
		return "key \"%s\" must be a JSON object" % surface
	var data: Dictionary = raw
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not SURFACE_RANGES.has(key):
			return "key \"%s\" has unknown key \"%s\"" % [surface, str(key)]
		var problem: String = _number_error(data[key], SURFACE_RANGES[key])
		if problem != "":
			return "key \"%s.%s\" %s" % [surface, key, problem]
		surfaces[surface][key] = float(data[key])
	return ""


## Why `number` is not a number within `bounds` [minimum, maximum], or "".
static func _number_error(number: Variant, bounds: Array) -> String:
	# A bool must not pass as 0 or 1.
	if typeof(number) != TYPE_FLOAT and typeof(number) != TYPE_INT:
		return "must be a number"
	if float(number) < float(bounds[0]) or float(number) > float(bounds[1]):
		return "is %s, must be within %s..%s" % [number, bounds[0], bounds[1]]
	return ""


static func _rejected(message: String) -> CockpitFinish:
	var finish: CockpitFinish = CockpitFinish.new()
	finish.error = message
	return finish
