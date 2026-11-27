class_name MeltdownWallRules
extends RefCounted

## Parses the optional `"meltdown"` section of `level_look.json` (#1454, GFX-6,
## CMF-8, ARC-4): how the mine's walls and guide strips look once the reactor
## has died. `MeltdownWalls` turns it into the wall shader's `meltdown` uniform.
##
##     "meltdown": {
##         "period_s": 1..20, "ramp_s": 0.5..30,
##         "low_emission": 0..MAX_EMISSION, "high_emission": 0..MAX_EMISSION,
##         "wall_color": [r, g, b], "ambient_color": [r, g, b],
##         "ambient_shift": 0..1, "strip_color": [r, g, b],
##         "strip_swing": 0..MAX_STRIP_SWING
##     }
##
## - The walls glow `wall_color`, their emission pulsing between `low_emission`
##   and `high_emission` once every `period_s`, a smooth rise and fall.
## - Their ambient turns `ambient_shift` of the way towards `ambient_color`,
##   keeping each box's brightness, so a dim tunnel stays dim.
## - The guide strips (#1463) turn `strip_color` and dim by up to `strip_swing`
##   of their brightness with the same pulse.
## - All of it ramps in over `ramp_s` from the reactor's death.
##
## Comfort (CMF-8): nothing may flash. A pulse shorter than a second, an
## emission above `MAX_EMISSION`, a swing above `MAX_EMISSION_SWING` or a strip
## swing above `MAX_STRIP_SWING` is refused, whatever the file says. The
## caps are code, not data, so retuning the look cannot lift them.
##
## Without the section nothing changes. A bad key names its field.

const KEY: String = "meltdown"
## The shortest pulse allowed. Flicker that bothers the eye starts around 3 a
## second; one a second is a slow breath, well clear of it.
const MIN_PERIOD_S: float = 1.0
## The brightest the walls may glow. The walls' own albedo is about 0.15 and
## the global ambient 0.12, so 0.25 is already a clear red cast, not a light.
const MAX_EMISSION: float = 0.25
## How far the emission may rise and fall within one pulse.
const MAX_EMISSION_SWING: float = 0.15
## How much of their brightness the strips may lose at the pulse's low point:
## at most half, so the route stays lit throughout.
const MAX_STRIP_SWING: float = 0.5
const COLOR_KEYS: Array[String] = ["wall_color", "ambient_color", "strip_color"]
## Inclusive ranges of the number keys.
const RANGES: Dictionary[String, Array] = {
	"period_s": [MIN_PERIOD_S, 20.0],
	"ramp_s": [0.5, 30.0],
	"low_emission": [0.0, MAX_EMISSION],
	"high_emission": [0.0, MAX_EMISSION],
	"ambient_shift": [0.0, 1.0],
	"strip_swing": [0.0, MAX_STRIP_SWING],
}


## All keys the section must hold, colours first.
static func keys() -> Array[String]:
	var all: Array[String] = COLOR_KEYS.duplicate()
	for key: String in RANGES:
		all.append(key)
	return all


## The rules in `value` (the section's parsed JSON), colours as `Color` and
## numbers as floats; or a dictionary holding only `"error"`, naming the field.
static func parse(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _rejected("%s must be a JSON object" % KEY)
	var data: Dictionary = value
	var all: Array[String] = keys()
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not all.has(key):
			return _rejected("%s has unknown key \"%s\"" % [KEY, str(key)])
	for key: String in all:
		if not data.has(key):
			return _rejected("%s is missing \"%s\"" % [KEY, key])
	var rules: Dictionary = {}
	for key: String in COLOR_KEYS:
		var problem: String = _color(data[key], "%s.%s" % [KEY, key], rules, key)
		if problem != "":
			return _rejected(problem)
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
	var low: float = rules["low_emission"]
	var high: float = rules["high_emission"]
	if low > high:
		return _rejected("%s.low_emission is %s, must be at most %s.high_emission (%s)" % [KEY, low, KEY, high])
	if high - low > MAX_EMISSION_SWING:
		return _rejected("%s.high_emission is %s, at most %s above %s.low_emission (%s): it would flash"
				% [KEY, high, MAX_EMISSION_SWING, KEY, low])
	return rules


static func _color(parts: Variant, field: String, into: Dictionary, key: String) -> String:
	if typeof(parts) != TYPE_ARRAY or (parts as Array).size() != 3:
		return "%s must be [red, green, blue]" % field
	for part: Variant in parts:
		if typeof(part) != TYPE_FLOAT and typeof(part) != TYPE_INT:
			return "%s must hold numbers" % field
		if float(part) < 0.0 or float(part) > 1.0:
			return "%s has %s, must be within 0..1" % [field, part]
	into[key] = Color(float(parts[0]), float(parts[1]), float(parts[2]))
	return ""


static func _rejected(message: String) -> Dictionary:
	return {"error": message}
