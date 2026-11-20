class_name CockpitLook
extends RefCounted

## How the cockpit frame's surfaces look (#659, GFX-2, GFX-4, ARC-4): the
## edge highlight, the frame's own dim light, the self-light that keeps it
## from reading black on black, and the procedural panel pattern. Read from
## the `"look"` object of each cockpit data file in `res://xr/cockpits/`, so
## every preset sets its own; the base colours stay `CockpitSpec`'s
## `interior_color` and `structure_color`.
##
## Like the rest of the frame this is the view only (ARC-3, CMF-6).

## Every number key with its allowed range, inclusive: [minimum, maximum].
const RANGES: Dictionary[String, Array] = {
	# Fraction of a surface's own colour it gives off with no light at all.
	"glow": [0.0, 1.0],
	# Width of the highlight on the long edges of the ledge, pillars and rim.
	"edge_width_m": [0.0, 0.03],
	# The frame's own point light, above the eye. Its range stays inside the
	# ship's 1 m collision sphere (with `LIGHT_OFFSET`), so it never lights a wall.
	"light_energy": [0.0, 2.0],
	"light_range_m": [0.2, 0.75],
	# Panel size and how much darker its lines (and lighter its rivets) are.
	"pattern_scale_m": [0.04, 0.5],
	"pattern_contrast": [0.0, 0.3],
	# Rivet diameter as a fraction of a panel; 0 draws none.
	"rivet_size": [0.0, 0.3],
	# The floor `lit_brightness` of every surface must reach, display 0..1.
	"min_lit_brightness": [0.05, 0.5],
}
const COLOR_KEYS: Array[String] = ["edge_color", "light_color"]
## Where the frame's own light sits, metres from the eye point.
const LIGHT_OFFSET: Vector3 = Vector3(0.0, 0.2, 0.0)
## Presets 1 and 2 keep peripheral vision calm (#659): each panel spans at
## least this angle where the frame is farthest from the eye, the contrast is
## at most this, and there are no rivets.
const CALM_MIN_PANEL_DEG: float = 10.0
const CALM_MAX_CONTRAST: float = 0.12

var edge_color: Color = Color(0.6, 0.7, 0.8)
var light_color: Color = Color(0.75, 0.85, 1.0)
var glow: float = 0.45
var edge_width_m: float = 0.006
var light_energy: float = 0.4
var light_range_m: float = 0.6
var pattern_scale_m: float = 0.12
var pattern_contrast: float = 0.08
var rivet_size: float = 0.0
var min_lit_brightness: float = 0.12

## Set when the data was rejected; empty otherwise.
var error: String = ""


static func keys() -> Array[String]:
	var all: Array[String] = []
	all.assign(RANGES.keys())
	all.append_array(COLOR_KEYS)
	return all


## Parses the `"look"` object of a cockpit data file: every key, nothing
## else, each in range. On failure `error` names the field.
static func parse(value: Variant) -> CockpitLook:
	if typeof(value) != TYPE_DICTIONARY:
		return _rejected("must be a JSON object")
	var data: Dictionary = value
	var known: Array[String] = keys()
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not known.has(key):
			return _rejected("unknown key \"%s\"" % str(key))
	var look: CockpitLook = CockpitLook.new()
	for key: String in RANGES:
		if not data.has(key):
			return _rejected("missing key \"%s\"" % key)
		var number: Variant = data[key]
		if typeof(number) != TYPE_FLOAT and typeof(number) != TYPE_INT:
			return _rejected("key \"%s\" must be a number" % key)
		var low: float = RANGES[key][0]
		var high: float = RANGES[key][1]
		if float(number) < low or float(number) > high:
			return _rejected("key \"%s\" is %s, must be within %s..%s" % [key, number, low, high])
		look.set(key, float(number))
	for key: String in COLOR_KEYS:
		if not data.has(key):
			return _rejected("missing key \"%s\"" % key)
		var color_error: String = CockpitSpec._color_error(data[key])
		if color_error != "":
			return _rejected("key \"%s\" %s" % [key, color_error])
		var parts: Array = data[key]
		look.set(key, Color(float(parts[0]), float(parts[1]), float(parts[2])))
	return look


## How bright a surface of colour `base` shows with only `ambient` light (the
## scene's ambient colour times its energy) and none of the headlight, flares,
## weapons or the frame's own light: its darkest pattern tone lit by the
## ambient plus its own glow, as a display value 0..1. The shader gives
## `albedo * ambient + albedo * glow` in linear light, as computed here.
func lit_brightness(base: Color, ambient: Color) -> float:
	var darkest: Color = (base * (1.0 - pattern_contrast)).srgb_to_linear()
	var ambient_linear: Color = ambient.srgb_to_linear()
	var lit: Color = Color(darkest.r * (glow + ambient_linear.r), darkest.g * (glow + ambient_linear.g),
		darkest.b * (glow + ambient_linear.b))
	return lit.linear_to_srgb().get_luminance()


## Why a surface of colour `base` could read black on black even in a mine
## with no ambient light at all, or empty when it is bright enough.
func floor_error(base: Color, name: String) -> String:
	var brightness: float = lit_brightness(base, Color.BLACK)
	if brightness < min_lit_brightness:
		return "%s %s with glow %s shows %.3f, below min_lit_brightness %s" % [
			name, base, glow, brightness, min_lit_brightness]
	return ""


## The angle one panel spans `distance_m` from the eye, degrees.
func panel_angle_deg(distance_m: float) -> float:
	return rad_to_deg(2.0 * atan(pattern_scale_m * 0.5 / distance_m))


## True when the pattern is calm enough for peripheral vision on presets 1
## and 2: large panels, low contrast, no rivets, with the frame's farthest
## surface `distance_m` from the eye.
func is_calm(distance_m: float) -> bool:
	return panel_angle_deg(distance_m) >= CALM_MIN_PANEL_DEG and pattern_contrast <= CALM_MAX_CONTRAST \
		and rivet_size == 0.0


static func _rejected(message: String) -> CockpitLook:
	var look: CockpitLook = CockpitLook.new()
	look.error = message
	return look
