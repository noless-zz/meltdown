class_name AmbientRules
extends RefCounted

## Parses the optional `"ambient_rules"` section of `level_look.json` (#1400,
## GFX-5, ARC-4): how each box of a mine picks its own ambient light from its
## size and its distance to the reactor. `AmbientBake` applies them.
##
##     "ambient_rules": {
##         "blend_m": 1..20, "piece_m": 0.5..10,
##         "sizes": [{"name": "tunnel", "up_to_width_m": 13, "color": [r, g, b], "energy": 0..2}, ...],
##         "reactor": {"color": [r, g, b], "energy": 0..2, "reach_m": 1..200, "strength": 0..1}
##     }
##
## - A box's width is its middle side, so a long tunnel and a short one are
##   both tunnels and a flat hall is still a room. The first size whose
##   `up_to_width_m` holds the width is the box's; wider than all takes the last.
## - A box whose centre is within `reach_m` of the reactor has its ambient
##   pulled towards the reactor's, by up to `strength` at the reactor itself. `reactor` may be
##   left out, and is ignored for a level without a reactor.
## - Across an opening the two boxes' ambients blend over `blend_m`; walls near
##   an opening are cut into pieces at most `piece_m` across so the blend shows.
## Energies go higher than the global ambient's 0.3: the walls' albedo is so
## dark that ambient at 0.3 changes them by under 1/255, so no room would differ
## in mood (#1400). At 2 a grey wall lit by ambient alone still reads near
## 10/255, so the mine stays dark until lit (LGT-1); `test_ambient_bake` holds both.

const KEY: String = "ambient_rules"
const RANGES: Dictionary[String, Array] = {
	"blend_m": [1.0, 20.0],
	"piece_m": [0.5, 10.0],
	"up_to_width_m": [0.5, 1000.0],
	"energy": [0.0, 2.0],
	"reach_m": [1.0, 200.0],
	"strength": [0.0, 1.0],
}
const TOP_KEYS: Array[String] = ["blend_m", "piece_m", "sizes", "reactor"]
const SIZE_KEYS: Array[String] = ["name", "up_to_width_m", "color", "energy"]
const REACTOR_KEYS: Array[String] = ["color", "energy", "reach_m", "strength"]
const TOP_OPTIONAL: Array[String] = ["reactor"]
const NONE_OPTIONAL: Array[String] = []


## The rules in `value` (the section's parsed JSON), with colours as `Color`;
## or a dictionary holding only `"error"`, which names the field.
static func parse(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _rejected("%s must be a JSON object" % KEY)
	var data: Dictionary = value
	var problem: String = _keys(data, TOP_KEYS, TOP_OPTIONAL, KEY)
	if problem != "":
		return _rejected(problem)
	var rules: Dictionary = {}
	for key: String in ["blend_m", "piece_m"]:
		problem = _number(data, key, "%s.%s" % [KEY, key], rules)
		if problem != "":
			return _rejected(problem)
	if typeof(data["sizes"]) != TYPE_ARRAY or (data["sizes"] as Array).is_empty():
		return _rejected("%s.sizes must be a non-empty list" % KEY)
	var sizes: Array[Dictionary] = []
	for index: int in (data["sizes"] as Array).size():
		var field: String = "%s.sizes[%d]" % [KEY, index]
		var size: Variant = data["sizes"][index]
		if typeof(size) != TYPE_DICTIONARY:
			return _rejected("%s must be a JSON object" % field)
		var parsed: Dictionary = {}
		problem = _keys(size, SIZE_KEYS, NONE_OPTIONAL, field)
		if problem == "" and typeof(size["name"]) != TYPE_STRING:
			problem = "%s.name must be a string" % field
		if problem == "":
			parsed["name"] = size["name"]
			problem = _number(size, "up_to_width_m", field + ".up_to_width_m", parsed)
		if problem == "":
			problem = _number(size, "energy", field + ".energy", parsed)
		if problem == "":
			problem = _color(size, field + ".color", parsed)
		if problem == "" and not sizes.is_empty() \
				and float(parsed["up_to_width_m"]) <= float(sizes[sizes.size() - 1]["up_to_width_m"]):
			problem = "%s.up_to_width_m must be larger than the size before it" % field
		if problem != "":
			return _rejected(problem)
		sizes.append(parsed)
	rules["sizes"] = sizes
	rules["reactor"] = {}
	if data.has("reactor"):
		var field: String = "%s.reactor" % KEY
		if typeof(data["reactor"]) != TYPE_DICTIONARY:
			return _rejected("%s must be a JSON object" % field)
		var reactor: Dictionary = {}
		problem = _keys(data["reactor"], REACTOR_KEYS, NONE_OPTIONAL, field)
		for key: String in ["energy", "reach_m", "strength"]:
			if problem == "":
				problem = _number(data["reactor"], key, "%s.%s" % [field, key], reactor)
		if problem == "":
			problem = _color(data["reactor"], field + ".color", reactor)
		if problem != "":
			return _rejected(problem)
		rules["reactor"] = reactor
	return rules


## The size rule for a box whose sides are `size`.
static func size_for(rules: Dictionary, size: Vector3) -> Dictionary:
	var sides: Array[float] = [size.x, size.y, size.z]
	sides.sort()
	var sizes: Array = rules["sizes"]
	for rule: Dictionary in sizes:
		if sides[1] <= float(rule["up_to_width_m"]):
			return rule
	return sizes[sizes.size() - 1]


## Every key of `data` must be in `allowed`, and every one not in `optional` present.
static func _keys(data: Dictionary, allowed: Array[String], optional: Array[String], field: String) -> String:
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not allowed.has(key):
			return "%s has unknown key \"%s\"" % [field, str(key)]
	for key: String in allowed:
		if not optional.has(key) and not data.has(key):
			return "%s is missing \"%s\"" % [field, key]
	return ""


static func _number(data: Dictionary, key: String, field: String, into: Dictionary) -> String:
	var value: Variant = data[key]
	# A bool must not pass as 0 or 1.
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return "%s must be a number" % field
	var bounds: Array = RANGES[key]
	if float(value) < float(bounds[0]) or float(value) > float(bounds[1]):
		return "%s is %s, must be within %s..%s" % [field, value, bounds[0], bounds[1]]
	into[key] = float(value)
	return ""


static func _color(data: Dictionary, field: String, into: Dictionary) -> String:
	var parts: Variant = data["color"]
	if typeof(parts) != TYPE_ARRAY or (parts as Array).size() != 3:
		return "%s must be [red, green, blue]" % field
	for part: Variant in parts:
		if typeof(part) != TYPE_FLOAT and typeof(part) != TYPE_INT:
			return "%s must hold numbers" % field
		if float(part) < 0.0 or float(part) > 1.0:
			return "%s has %s, must be within 0..1" % [field, part]
	into["color"] = Color(float(parts[0]), float(parts[1]), float(parts[2]))
	return ""


static func _rejected(message: String) -> Dictionary:
	return {"error": message}
