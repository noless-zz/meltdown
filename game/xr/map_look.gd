class_name MapLook
extends RefCounted

## Parses the map hologram's look file, `res://xr/map_look.json` (ARC-4). Split
## out of `MapHologram` so the node stays small once it drew the exit and
## reactor markers (#338).
##
##     {"line_color": [r, g, b], "line_energy": 0..8, "size_m": 0.05..0.6,
##      "marker_color": [r, g, b], "marker_radius_m": 0.002..0.05,
##      "exit_color": [r, g, b], "exit_radius_m": 0.002..0.05,
##      "reactor_color": [r, g, b], "reactor_radius_m": 0.002..0.05,
##      "route_color": [r, g, b], "route_width_m": 0.0005..0.01,
##      "blocked_color": [r, g, b], "blocked_size_m": 0.002..0.05,
##      "distance_color": [r, g, b], "distance_height_m": 0.003..0.03,
##      "distance_offset_m": 0..0.05,
##      "fire_color": [r, g, b], "fire_size_m": 0.002..0.05}
##
## `exit_radius_m` is half the edge of the exit cube; `blocked_size_m` is the
## length of each bar of a blocked opening's cross. `distance_height_m` is the
## height of the route's distance label (#442) and `distance_offset_m` how far
## above the ship's end of the route it sits, both in the hologram whatever its
## scale. `fire_size_m` is the smallest tip-to-tip span of a fire marker
## (#519). The exit, reactor, route, blocked, distance and fire keys are
## optional, so a file written before #338, #400, #442 or #519 still loads and
## keeps the built-in values for them.

const REQUIRED_KEYS: Array[String] = ["line_color", "line_energy", "size_m", "marker_color", "marker_radius_m"]
const OPTIONAL_KEYS: Array[String] = ["exit_color", "exit_radius_m", "reactor_color", "reactor_radius_m",
		"route_color", "route_width_m", "blocked_color", "blocked_size_m", "distance_color", "distance_height_m",
		"distance_offset_m", "fire_color", "fire_size_m"]
const COLOR_KEYS: Array[String] = ["line_color", "marker_color", "exit_color", "reactor_color", "route_color",
		"blocked_color", "distance_color", "fire_color"]
## Inclusive ranges of the number keys.
const RANGES: Dictionary[String, Array] = {
	"line_energy": [0.0, 8.0],
	"size_m": [0.05, 0.6],
	"marker_radius_m": [0.002, 0.05],
	"exit_radius_m": [0.002, 0.05],
	"reactor_radius_m": [0.002, 0.05],
	# Thinner than half a millimetre vanishes at arm's length on the Quest 3
	# panel; thicker than a centimetre hides the wireframe under it.
	"route_width_m": [0.0005, 0.01],
	"blocked_size_m": [0.002, 0.05],
	# Under 3 mm the digits blur at arm's length; over 3 cm the label covers
	# the part of the map the route runs through.
	"distance_height_m": [0.003, 0.03],
	"distance_offset_m": [0.0, 0.05],
	"fire_size_m": [0.002, 0.05],
}
## Look used when the file is missing or rejected, and for optional keys a
## file leaves out. The exit is green and the reactor magenta so neither reads
## as the orange ship marker or the cyan lines. The route is white, thicker
## than the wireframe, and the blocked crosses red (MAP-2, #400). The distance
## label is the route's white, so it reads as belonging to the route (#442).
## Fires are yellow (#519): hazard, yet apart from the red blocked crosses and
## the orange ship marker, since fire is passable and must not read as blocked.
const FALLBACK: Dictionary = {
	"line_color": Color(0.3, 0.85, 1.0),
	"line_energy": 1.5,
	"size_m": 0.25,
	"marker_color": Color(1.0, 0.6, 0.15),
	"marker_radius_m": 0.008,
	"exit_color": Color(0.35, 1.0, 0.45),
	"exit_radius_m": 0.01,
	"reactor_color": Color(1.0, 0.25, 0.75),
	"reactor_radius_m": 0.01,
	"route_color": Color(0.95, 0.95, 0.95),
	"route_width_m": 0.0015,
	"blocked_color": Color(1.0, 0.1, 0.1),
	"blocked_size_m": 0.012,
	"distance_color": Color(0.95, 0.95, 0.95),
	"distance_height_m": 0.008,
	"distance_offset_m": 0.012,
	"fire_color": Color(1.0, 1.0, 0.0),
	"fire_size_m": 0.012,
}


## Parses the text of a look file. Returns the look with colours as `Color`
## and numbers as floats, every key filled, or a dictionary holding only
## `"error"`, which names the field.
static func parse(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not (REQUIRED_KEYS.has(key) or OPTIONAL_KEYS.has(key)):
			return _rejected("unknown key \"%s\"" % str(key))
	for key: String in REQUIRED_KEYS:
		if not data.has(key):
			return _rejected("missing key \"%s\"" % key)
	var look: Dictionary = FALLBACK.duplicate()
	for key: String in COLOR_KEYS:
		if not data.has(key):
			continue
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
		if not data.has(key):
			continue
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
