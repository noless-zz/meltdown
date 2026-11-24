class_name ControlLabelLayout
extends RefCounted

## Where each control label floats beside its controller (PLT-5, CMF-8, ARC-4,
## #1316), read from `res://xr/control_label_layout.json`.
##
## Twice the labels were placed in the hand's own frame: first round the
## controller head (#147), then beside each part (#1212). In a resting grip the
## hand is tilted, so rows that were apart on the hand fell on top of each other
## and inside the controller in the eye's view (#1316). Now every label of a
## hand sits in one column in a plane square to the eye's view, as the
## billboarded text is, beside a sphere that holds the whole controller: rows stack top to bottom in the order of
## `CONTROLS`, each as tall as its text (at least `row_height_m`) and
## `row_gap_m` apart, the column `gap_m` outside the sphere's outline on
## `column_side`. All rows share one depth, so however the hand turns rows
## that are apart stay apart in the view and none covers the controller.
##
## Keys, right hand, hand-local metres (-z ahead, +y up, +x right):
## - `controller_centre_m`, `controller_radius_m`: the sphere round the model;
## - `gap_m`, `row_height_m`, `row_gap_m`, `column_rise_m` (the column's middle
##   above the sphere's centre), `column_side` (`"outer"` or `"inner"`);
## - `leader_width_m`: the leader line's width;
## - `text_deg`, `arm_length_m`: the letters' height (the em) as an angle at
##   arm's length; sets the text's size in the world;
## - `max_leader_m`, `held_hand_m`, `held_pitch_deg`, `close_apart_m`: the
##   longest leader and the two poses the overlap check holds the hands in, the
##   resting grip (right hand from the eye, nose up by the pitch, the left
##   mirrored) and the same grip with the hands that far apart.

const DEFAULT_FILE: String = "res://xr/control_label_layout.json"
## Rows from the top of the column down, roughly as the parts sit on the hand.
const CONTROLS: Array[String] = ["stick", "stick_click", "button_upper", "button_lower", "menu", "trigger", "grip"]
const SIDES: Array[String] = ["outer", "inner"]
const RANGES: Dictionary = {
	"controller_radius_m": [0.02, 0.15],
	"gap_m": [0.0, 0.05],
	"row_height_m": [0.0, 0.05],
	"row_gap_m": [0.0, 0.02],
	"column_rise_m": [-0.15, 0.15],
	"leader_width_m": [0.0003, 0.005],
	"text_deg": [0.5, 3.0],
	"arm_length_m": [0.3, 1.0],
	"max_leader_m": [0.02, 0.3],
	"held_pitch_deg": [-90.0, 90.0],
	"close_apart_m": [0.05, 0.6],
}
## Three-number keys and how far each number may be from zero.
const VECTORS: Dictionary = {"controller_centre_m": 0.1, "held_hand_m": 0.6}
const SIDE_KEY: String = "column_side"

## Used when the file is missing or rejected; matches the shipped file.
const FALLBACK: Dictionary = {
	"controller_centre_m": Vector3(0.005, -0.015, 0.02),
	"controller_radius_m": 0.065,
	"gap_m": 0.008,
	"row_height_m": 0.012,
	"row_gap_m": 0.003,
	"column_side": "outer",
	"column_rise_m": 0.04,
	"leader_width_m": 0.0012,
	"text_deg": 0.9,
	"arm_length_m": 0.6,
	"max_leader_m": 0.16,
	"held_hand_m": Vector3(0.18, -0.32, -0.34),
	"held_pitch_deg": 20.0,
	"close_apart_m": 0.2,
}


## The layout in `path`, or `FALLBACK` when it is missing or rejected.
static func load_file(path: String = DEFAULT_FILE) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("%s missing, using the built-in label layout" % path)
		return FALLBACK
	var layout: Dictionary = parse(FileAccess.get_file_as_string(path))
	if layout.has("error"):
		push_warning("%s rejected: %s" % [path, layout["error"]])
		return FALLBACK
	return layout


## The layout with numbers as floats and three-number keys as `Vector3`, or a
## dictionary holding only `"error"`, which names the key.
static func parse(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if not FALLBACK.has(str(key)):
			return _rejected("unknown key \"%s\"" % str(key))
	for key: String in FALLBACK:
		if not data.has(key):
			return _rejected("missing key \"%s\"" % key)
	var layout: Dictionary = {}
	for key: String in RANGES:
		var problem: String = _number_problem(key, data[key], RANGES[key])
		if problem != "":
			return _rejected(problem)
		layout[key] = float(data[key])
	for key: String in VECTORS:
		var value: Variant = data[key]
		if typeof(value) != TYPE_ARRAY or (value as Array).size() != 3:
			return _rejected("\"%s\" must be three numbers" % key)
		var limit: float = float(VECTORS[key])
		for axis: Variant in value:
			var problem: String = _number_problem(key, axis, [-limit, limit])
			if problem != "":
				return _rejected(problem)
		layout[key] = Vector3(float(value[0]), float(value[1]), float(value[2]))
	if not SIDES.has(str(data[SIDE_KEY])) or typeof(data[SIDE_KEY]) != TYPE_STRING:
		return _rejected("\"%s\" must be one of %s" % [SIDE_KEY, SIDES])
	layout[SIDE_KEY] = str(data[SIDE_KEY])
	return layout


## +1 when `hand`'s column runs to the eye's right of its controller, -1 to
## the left: the outer side is away from the other hand.
static func side_sign(layout: Dictionary, hand: String) -> float:
	var outer: float = -1.0 if hand == "left" else 1.0
	return outer if str(layout.get(SIDE_KEY, "outer")) == "outer" else -outer


## Metres per texture pixel that make a `font_size` em subtend `text_deg` at
## `arm_length_m`.
static func pixel_size(layout: Dictionary, font_size: int) -> float:
	var em: float = tan(deg_to_rad(float(layout["text_deg"]))) * float(layout["arm_length_m"])
	return em / float(font_size)


## Control -> `Vector2(x, y)` in the plane facing the eye, from the sphere's
## centre: `x` the row's inner edge, `y` the middle of its row. `sizes` gives
## each control's text size (width, height) in metres; `side` is `side_sign`;
## `extent` how far the sphere's outline reaches on that side in this plane
## (`outline_extent`), the radius when not given.
static func place(layout: Dictionary, sizes: Dictionary, side: float, extent: float = -1.0) -> Dictionary:
	var order: Array[String] = []
	var total: float = 0.0
	for control: String in CONTROLS:
		if sizes.has(control):
			order.append(control)
			total += row_pitch(layout, sizes[control])
	total += float(layout["row_gap_m"]) * maxf(order.size() - 1, 0)
	var top: float = float(layout["column_rise_m"]) + 0.5 * total
	if extent < 0.0:
		extent = float(layout["controller_radius_m"])
	var x: float = side * (extent + float(layout["gap_m"]))
	var placed: Dictionary = {}
	for control: String in order:
		var pitch: float = row_pitch(layout, sizes[control])
		placed[control] = Vector2(x, top - 0.5 * pitch)
		top -= pitch + float(layout["row_gap_m"])
	return placed


## How far, in metres sideways in the plane through `centre` facing the eye,
## the outline of a sphere of `radius` at `centre` (eye frame, eye looking
## along -z) reaches on `side`. Off the middle of the view a sphere's outline
## is an ellipse stretched away from the middle, wider than the radius, so the
## column must clear the ellipse, not the radius (#1316). The two tangent
## planes through the eye give the outline's left and right edges.
static func outline_extent(centre: Vector3, radius: float, side: float) -> float:
	var a: float = centre.z * centre.z - radius * radius
	if a <= 0.0001:
		return radius
	var b: float = centre.x * centre.z
	var root: float = sqrt(maxf(b * b - a * (centre.x * centre.x - radius * radius), 0.0))
	# Tangents u = x / -z of the outline's edges; the plane is at depth -z.
	var edges: Array[float] = [(-b - root) / a, (-b + root) / a]
	var depth: float = -centre.z
	var reach: float = maxf(edges[0], edges[1]) * depth - centre.x if side > 0.0 \
		else centre.x - minf(edges[0], edges[1]) * depth
	return maxf(reach, radius)


## The height one row takes: its text, or `row_height_m` when that is taller.
static func row_pitch(layout: Dictionary, size: Vector2) -> float:
	return maxf(size.y, float(layout["row_height_m"]))


static func _number_problem(key: String, value: Variant, bounds: Array) -> String:
	# A bool must not pass as 0 or 1.
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return "\"%s\" must be a number" % key
	if float(value) < float(bounds[0]) or float(value) > float(bounds[1]):
		return "\"%s\" is %s, must be within %s..%s" % [key, value, bounds[0], bounds[1]]
	return ""


static func _rejected(reason: String) -> Dictionary:
	return {"error": reason}
