class_name ShaftPanelShapes
extends RefCounted

## Parses `res://xr/shaft_panel_shapes.json`, how the shaft panel draws each
## shaft as a thing with gauges beside the others (#1320, RUN-2, GFX-2, ARC-4,
## ARC-5, decision record 0012):
##
##     {"label_max_chars": 8..64, "card_step_m": ..., "object_drop_m": ...,
##      "label_drop_m": ..., "gauge_drop_m": ..., "gauge_step_m": ...,
##      "gauge_length_m": ..., "gauge_height_m": ..., "gauge_x_m": ..., "plate_size_m": [w, h],
##      "plate_drop_m": ..., "suspend_gap_m": ..., "point_radius_m": ...,
##      "plate_color": [r, g, b], "plate_lit_color": [..], "gauge_back_color": [..],
##      "mark_color": [..],
##      "gauges": [{"source": "robots"|"alarm"|"finds", "label": "...", "min": n,
##                  "max": n, "mark": n, "color": [r, g, b]}, ...],
##      "shafts": {"<shaft kind>": "<look key>", ...},
##      "looks": {"<look key>": {"label": "...", "parts": [{"shape": "box"|...,
##                "size": [x, y, z], "at": [x, y, z], "turn_deg": [x, y, z] (optional),
##                "color": [r, g, b]}, ...]}, ...}}
##
## Each look is a small object of primitives, drawn in file order so a later
## part shows over an earlier one; a new look is a data entry, not code (ARC-4).
## Every gauge draws all shafts on its own `min`..`max`, so they compare at a
## glance. Every word shown is at most `label_max_chars` long. A shaft kind
## with no entry in `shafts` keeps today's text row.

const DEFAULT_FILE: String = "res://xr/shaft_panel_shapes.json"
const SOURCES: Array[String] = ["robots", "alarm", "finds"]
const SHAPES: Array[String] = ["box", "cylinder", "sphere", "prism"]
const LENGTH_KEYS: Dictionary[String, Array] = {
	"card_step_m": [0.2, 0.8], "object_drop_m": [0.0, 0.5], "label_drop_m": [0.0, 0.5],
	"gauge_drop_m": [0.0, 0.6], "gauge_step_m": [0.02, 0.2], "gauge_length_m": [0.05, 0.4],
	"gauge_height_m": [0.005, 0.06], "gauge_x_m": [-0.3, 0.3], "plate_drop_m": [0.0, 0.6], "suspend_gap_m": [0.05, 0.5],
	"point_radius_m": [0.05, 0.5],
}
const COLOR_KEYS: Array[String] = ["plate_color", "plate_lit_color", "gauge_back_color", "mark_color"]
const LABEL_LIMITS: Array[int] = [8, 64]
## Half the cube a look's parts must stay within, from its centre.
const OBJECT_HALF_M: float = 0.15
const MAX_PARTS: int = 24

var label_max_chars: int = 24
## Lengths in metres, keyed as in the file.
var lengths: Dictionary[String, float] = {}
var plate_size_m: Vector2 = Vector2.ZERO
var colors: Dictionary[String, Color] = {}
## [{"source", "label", "min", "max", "mark", "color": Color}], in file order.
var gauges: Array[Dictionary] = []
## Shaft kind to look key.
var shafts: Dictionary[String, String] = {}
## Look key to {"label": String, "parts": [{"shape", "size": Vector3, "at": Transform3D, "color": Color}]}.
var looks: Dictionary[String, Dictionary] = {}
## Why the text was refused; "" when it was read.
var error: String = ""


## The shipped file, or an empty set naming its problem in `error`.
static func load_file(path: String = DEFAULT_FILE) -> ShaftPanelShapes:
	if not FileAccess.file_exists(path):
		var missing: ShaftPanelShapes = ShaftPanelShapes.new()
		missing.error = "%s: file not found" % path
		return missing
	var shapes: ShaftPanelShapes = parse(FileAccess.get_file_as_string(path))
	if shapes.error != "":
		push_warning("The shaft panel shows text rows; %s: %s" % [path, shapes.error])
	return shapes


static func parse(text: String) -> ShaftPanelShapes:
	var shapes: ShaftPanelShapes = ShaftPanelShapes.new()
	var json: JSON = JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		shapes.error = "not a JSON object"
		return shapes
	shapes.error = shapes._read(json.data)
	if shapes.error != "":
		shapes.gauges.clear()
		shapes.shafts.clear()
		shapes.looks.clear()
	return shapes


## The look key of shaft `kind`, or "" for a text row.
func look_of(kind: String) -> String:
	return shafts.get(kind, "")


func _read(data: Dictionary) -> String:
	var known: Array = ["label_max_chars", "plate_size_m", "gauges", "shafts", "looks"]
	known.append_array(LENGTH_KEYS.keys())
	known.append_array(COLOR_KEYS)
	for key: Variant in data:
		if not known.has(key):
			return "unknown key \"%s\"" % str(key)
	for key: Variant in known:
		if not data.has(key):
			return "missing key \"%s\"" % key
	var limit: Variant = data["label_max_chars"]
	if not _is_number(limit) or float(limit) != floorf(float(limit)) or int(limit) < LABEL_LIMITS[0] \
			or int(limit) > LABEL_LIMITS[1]:
		return "\"label_max_chars\" must be a whole number within %d..%d" % [LABEL_LIMITS[0], LABEL_LIMITS[1]]
	label_max_chars = int(limit)
	for key: String in LENGTH_KEYS:
		var bounds: Array = LENGTH_KEYS[key]
		if not _is_number(data[key]) or float(data[key]) < float(bounds[0]) or float(data[key]) > float(bounds[1]):
			return "\"%s\" must be a number within %s..%s" % [key, bounds[0], bounds[1]]
		lengths[key] = float(data[key])
	var plate: Array = _numbers(data["plate_size_m"], 2)
	if plate.is_empty() or plate.min() <= 0.0 or plate.max() > 1.0:
		return "\"plate_size_m\" must be [width, height], each within 0..1 m"
	plate_size_m = Vector2(plate[0], plate[1])
	for key: String in COLOR_KEYS:
		var color: Variant = _color(data[key])
		if color == null:
			return "\"%s\" must be [red, green, blue], each within 0..1" % key
		colors[key] = color
	var problem: String = _read_gauges(data["gauges"])
	if problem == "":
		problem = _read_looks(data["looks"])
	if problem == "":
		problem = _read_shafts(data["shafts"])
	return problem


func _read_gauges(value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY or (value as Array).is_empty():
		return "\"gauges\" must be a list that is not empty"
	for i: int in (value as Array).size():
		var gauge: Variant = value[i]
		var where: String = "gauges[%d]" % i
		if typeof(gauge) != TYPE_DICTIONARY or (gauge as Dictionary).size() != 6:
			return "%s must be {\"source\", \"label\", \"min\", \"max\", \"mark\", \"color\"}" % where
		if not SOURCES.has(gauge.get("source")):
			return "%s.source must be one of %s" % [where, SOURCES]
		var problem: String = _label_problem(gauge.get("label"), where + ".label")
		if problem != "":
			return problem
		for key: String in ["min", "max", "mark"]:
			if not _is_number(gauge.get(key)):
				return "%s.%s must be a number" % [where, key]
		if float(gauge["max"]) <= float(gauge["min"]):
			return "%s.max must be above its min" % where
		var color: Variant = _color(gauge.get("color"))
		if color == null:
			return "%s.color must be [red, green, blue], each within 0..1" % where
		gauges.append({"source": gauge["source"], "label": gauge["label"], "min": float(gauge["min"]),
			"max": float(gauge["max"]), "mark": float(gauge["mark"]), "color": color})
	return ""


func _read_looks(value: Variant) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "\"looks\" must be an object"
	for key: Variant in value:
		var look: Variant = value[key]
		var where: String = "looks.%s" % str(key)
		if typeof(look) != TYPE_DICTIONARY or (look as Dictionary).size() != 2 or not look.has("parts"):
			return "%s must be {\"label\", \"parts\"}" % where
		var problem: String = _label_problem(look.get("label"), where + ".label")
		if problem != "":
			return problem
		var parts: Variant = look["parts"]
		if typeof(parts) != TYPE_ARRAY or (parts as Array).is_empty() or (parts as Array).size() > MAX_PARTS:
			return "%s.parts must be a list of 1..%d parts" % [where, MAX_PARTS]
		var read: Array[Dictionary] = []
		for i: int in (parts as Array).size():
			var part: Variant = _part(parts[i])
			if typeof(part) == TYPE_STRING:
				return "%s.parts[%d] %s" % [where, i, part]
			read.append(part)
		looks[str(key)] = {"label": look["label"], "parts": read}
	return ""


func _read_shafts(value: Variant) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "\"shafts\" must be an object of shaft kind to look key"
	for kind: Variant in value:
		if typeof(value[kind]) != TYPE_STRING or not looks.has(value[kind]):
			return "shafts.%s must name one of the looks" % str(kind)
		shafts[str(kind)] = value[kind]
	return ""


## {"shape", "size", "at", "color"} with `at` a Transform3D, or the problem.
static func _part(value: Variant) -> Variant:
	if typeof(value) != TYPE_DICTIONARY:
		return "must be an object"
	var part: Dictionary = value
	for key: Variant in part:
		if not ["shape", "size", "at", "turn_deg", "color"].has(key):
			return "has an unknown key \"%s\"" % str(key)
	if not SHAPES.has(part.get("shape")):
		return "shape must be one of %s" % [SHAPES]
	var size: Array = _numbers(part.get("size"), 3)
	var at: Array = _numbers(part.get("at"), 3)
	var turn: Array = _numbers(part.get("turn_deg", [0.0, 0.0, 0.0]), 3)
	if size.is_empty() or size.min() <= 0.0 or at.is_empty() or turn.is_empty():
		return "needs size (each above 0), at and turn_deg as three numbers"
	for axis: int in 3:
		if absf(at[axis]) + float(size[axis]) * 0.5 > OBJECT_HALF_M:
			return "reaches past %s m from the look's centre" % OBJECT_HALF_M
	var color: Variant = _color(part.get("color"))
	if color == null:
		return "color must be [red, green, blue], each within 0..1"
	var basis: Basis = Basis.from_euler(Vector3(deg_to_rad(turn[0]), deg_to_rad(turn[1]), deg_to_rad(turn[2])))
	return {"shape": part["shape"], "size": Vector3(size[0], size[1], size[2]),
		"at": Transform3D(basis, Vector3(at[0], at[1], at[2])), "color": color}


func _label_problem(value: Variant, where: String) -> String:
	if typeof(value) != TYPE_STRING or (value as String).strip_edges() == "":
		return "%s must be a text that is not empty" % where
	if (value as String).length() > label_max_chars:
		return "%s \"%s\" is longer than %d characters" % [where, value, label_max_chars]
	return ""


static func _color(value: Variant) -> Variant:
	var parts: Array = _numbers(value, 3)
	if parts.is_empty() or parts.min() < 0.0 or parts.max() > 1.0:
		return null
	return Color(parts[0], parts[1], parts[2])


static func _numbers(value: Variant, count: int) -> Array:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != count:
		return []
	var result: Array = []
	for part: Variant in value:
		if not _is_number(part):
			return []
		result.append(float(part))
	return result


## A bool must not pass as 0 or 1.
static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
