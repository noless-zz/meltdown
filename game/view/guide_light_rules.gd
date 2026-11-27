class_name GuideLightRules
extends RefCounted

## Parses the optional `"guide_lights"` section of `level_look.json` (#1463,
## GFX-2, GFX-5, ARC-4): the emissive strips that run along the walls and
## corners of a mine and frame its openings, so the tunnel's shape and the next
## opening read at flying speed. `GuideLights` places them.
##
##     "guide_lights": {
##         "spacing_m": 0.5..50, "length_m": 0.25..50 (at most spacing_m),
##         "width_m": 0.02..0.5, "inset_m": 0..3, "margin_m": 0..2,
##         "energy": 0..4, "tunnel_up_to_width_m": 0.5..1000,
##         "junction_openings": 3..12,
##         "colors": {"tunnel": [r, g, b], "room": [r, g, b],
##                    "junction": [r, g, b], "reactor": [r, g, b]}
##     }
##
## - Corner strips run `inset_m` in from a box's edges, clear of the bevels,
##   in dashes `length_m` long every `spacing_m`; equal lengths draw a solid line.
## - Every opening is framed by a solid strip `margin_m` outside its edge.
## - Strips are `width_m` across and glow their box kind's colour at `energy`.
## - A box's kind: `reactor` when it holds the reactor, `junction` when it opens
##   into at least `junction_openings` other boxes, `tunnel` when its middle
##   side is at most `tunnel_up_to_width_m` (the rule `AmbientRules` uses for
##   width), and `room` otherwise. Rooms are outlined on every edge; tunnels
##   only along their length, so the run of the tunnel is what the eye follows.
##
## Without the section nothing is drawn. A bad key names its field.

const KEY: String = "guide_lights"
const KIND_TUNNEL: String = "tunnel"
const KIND_ROOM: String = "room"
const KIND_JUNCTION: String = "junction"
const KIND_REACTOR: String = "reactor"
const KINDS: Array[String] = [KIND_TUNNEL, KIND_ROOM, KIND_JUNCTION, KIND_REACTOR]
const COLORS_KEY: String = "colors"
## Inclusive ranges of the number keys.
const RANGES: Dictionary[String, Array] = {
	"spacing_m": [0.5, 50.0],
	"length_m": [0.25, 50.0],
	"width_m": [0.02, 0.5],
	"inset_m": [0.0, 3.0],
	"margin_m": [0.0, 2.0],
	# Above 4 a strip outshines the station screens' cap and starts to glare.
	"energy": [0.0, 4.0],
	"tunnel_up_to_width_m": [0.5, 1000.0],
	"junction_openings": [3.0, 12.0],
}


## The rules in `value` (the section's parsed JSON), with colours as `Color`
## by kind; or a dictionary holding only `"error"`, which names the field.
static func parse(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _rejected("%s must be a JSON object" % KEY)
	var data: Dictionary = value
	var allowed: Array[String] = [COLORS_KEY]
	for key: String in RANGES:
		allowed.append(key)
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not allowed.has(key):
			return _rejected("%s has unknown key \"%s\"" % [KEY, str(key)])
	for key: String in allowed:
		if not data.has(key):
			return _rejected("%s is missing \"%s\"" % [KEY, key])
	var rules: Dictionary = {}
	for key: String in RANGES:
		var field: String = "%s.%s" % [KEY, key]
		var number: Variant = data[key]
		# A bool must not pass as 0 or 1.
		if typeof(number) != TYPE_FLOAT and typeof(number) != TYPE_INT:
			return _rejected("%s must be a number" % field)
		var bounds: Array = RANGES[key]
		if float(number) < float(bounds[0]) or float(number) > float(bounds[1]):
			return _rejected("%s is %s, must be within %s..%s" % [field, number, bounds[0], bounds[1]])
		rules[key] = float(number)
	if float(rules["junction_openings"]) != floorf(float(rules["junction_openings"])):
		return _rejected("%s.junction_openings must be a whole number" % KEY)
	if float(rules["length_m"]) > float(rules["spacing_m"]):
		return _rejected("%s.length_m is %s, must be at most %s.spacing_m (%s)"
				% [KEY, rules["length_m"], KEY, rules["spacing_m"]])
	var colors: Variant = data[COLORS_KEY]
	if typeof(colors) != TYPE_DICTIONARY:
		return _rejected("%s.%s must be a JSON object" % [KEY, COLORS_KEY])
	var by_kind: Dictionary = {}
	for kind: Variant in colors:
		if typeof(kind) != TYPE_STRING or not KINDS.has(kind):
			return _rejected("%s.%s has unknown kind \"%s\"" % [KEY, COLORS_KEY, str(kind)])
	for kind: String in KINDS:
		var field: String = "%s.%s.%s" % [KEY, COLORS_KEY, kind]
		if not (colors as Dictionary).has(kind):
			return _rejected("%s is missing" % field)
		var problem: String = _color(colors[kind], field, by_kind, kind)
		if problem != "":
			return _rejected(problem)
	rules[COLORS_KEY] = by_kind
	return rules


static func _color(parts: Variant, field: String, into: Dictionary, kind: String) -> String:
	if typeof(parts) != TYPE_ARRAY or (parts as Array).size() != 3:
		return "%s must be [red, green, blue]" % field
	for part: Variant in parts:
		if typeof(part) != TYPE_FLOAT and typeof(part) != TYPE_INT:
			return "%s must hold numbers" % field
		if float(part) < 0.0 or float(part) > 1.0:
			return "%s has %s, must be within 0..1" % [field, part]
	into[kind] = Color(float(parts[0]), float(parts[1]), float(parts[2]))
	return ""


static func _rejected(message: String) -> Dictionary:
	return {"error": message}
