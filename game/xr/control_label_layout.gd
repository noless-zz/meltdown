class_name ControlLabelLayout
extends RefCounted

## Where each control label floats beside its controller (PLT-5, ARC-4,
## #1212), read from `res://xr/control_label_layout.json`:
##
##     {"column_x_m": 0..0.1, "plane_shift_z_m": -0.05..0.05, "row_gap_m": 0..0.02,
##      "rise_m": {<control>: -0.05..0.08, ...}, "max_distance_m": 0.02..0.15,
##      "held_hand_m": [x, y, z]}
##
## The owner found the labels far from the Quest 3 controller, joined to it by
## long lines and over the status panel (#1212). Each label now starts at the
## height of the part it names (`rise_m` above it) instead of in a fixed
## column, so it sits beside that part. The stick's cross floats over the
## stick; every other label sits just outside the controller at `column_x_m`.
## Rows that would overlap are pushed down, top to bottom, `row_gap_m` apart.
## All labels share one depth, the mean depth of their parts moved by
## `plane_shift_z_m`, so rows that are apart on the hand stay apart in the
## eye's view whatever depth each part has, on any controller model.
##
## `max_distance_m` is the farthest a label may sit from its part, and
## `held_hand_m` the right hand's usual place from the eye (seated, hands low
## in front, the left mirrored), where no label may cover the status panel.
## Both are checked by the tests; neither changes where a label is drawn.
## Values are right-hand and hand-local: -z ahead, +y up, +x to the right.

const DEFAULT_FILE: String = "res://xr/control_label_layout.json"
const CONTROLS: Array[String] = ["stick", "stick_click", "button_upper", "button_lower", "menu", "trigger", "grip"]
const RANGES: Dictionary = {
	"column_x_m": [0.0, 0.1],
	"plane_shift_z_m": [-0.05, 0.05],
	"row_gap_m": [0.0, 0.02],
	"max_distance_m": [0.02, 0.15],
}
const RISE_RANGE: Array = [-0.05, 0.08]
const HELD_RANGE_M: float = 0.6

## Used when the file is missing or rejected; matches the shipped file.
const FALLBACK: Dictionary = {
	"column_x_m": 0.03,
	"plane_shift_z_m": 0.0,
	"row_gap_m": 0.0022,
	"rise_m": {"stick": 0.03, "stick_click": 0.0, "button_upper": 0.0, "button_lower": 0.0,
		"menu": 0.0, "trigger": 0.0, "grip": 0.0},
	"max_distance_m": 0.06,
	"held_hand_m": Vector3(0.18, -0.32, -0.34),
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


## The layout with numbers as floats and `held_hand_m` as a `Vector3`, or a
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
	if typeof(data["rise_m"]) != TYPE_DICTIONARY:
		return _rejected("\"rise_m\" must be an object")
	var rises: Dictionary = data["rise_m"]
	var rise: Dictionary = {}
	for control: String in CONTROLS:
		if not rises.has(control):
			return _rejected("rise_m is missing control \"%s\"" % control)
		var problem: String = _number_problem("rise_m.%s" % control, rises[control], RISE_RANGE)
		if problem != "":
			return _rejected(problem)
		rise[control] = float(rises[control])
	if rise.size() != rises.size():
		return _rejected("rise_m has an unknown control")
	layout["rise_m"] = rise
	var held: Variant = data["held_hand_m"]
	if typeof(held) != TYPE_ARRAY or (held as Array).size() != 3:
		return _rejected("\"held_hand_m\" must be three numbers")
	for axis: Variant in held:
		var problem: String = _number_problem("held_hand_m", axis, [-HELD_RANGE_M, HELD_RANGE_M])
		if problem != "":
			return _rejected(problem)
	layout["held_hand_m"] = Vector3(float(held[0]), float(held[1]), float(held[2]))
	return layout


## Control -> where its label sits on the right hand, for the controls in
## `heights` (control -> text height in metres). `points` gives each
## control's part, right hand (a missing one counts as the hand's origin).
## Controls in `over` are centred over their part; the rest sit in the column.
## Rows are taken from the highest wanted spot down; each sits at its part's
## height plus its rise, or lower when the row above needs the room.
static func place(layout: Dictionary, heights: Dictionary, points: Dictionary,
		over: Array[String]) -> Dictionary:
	var order: Array[String] = []
	for control: String in CONTROLS:
		if heights.has(control):
			order.append(control)
	var wanted: Dictionary = {}
	for control: String in order:
		var point: Vector3 = points.get(control, Vector3.ZERO)
		wanted[control] = point.y + float((layout["rise_m"] as Dictionary).get(control, 0.0))
	# Stable: equal heights keep the controller's top-to-bottom order.
	order.sort_custom(func(a: String, b: String) -> bool:
		return float(wanted[a]) > float(wanted[b]) \
			or (is_equal_approx(float(wanted[a]), float(wanted[b])) and CONTROLS.find(a) < CONTROLS.find(b)))
	var depth: float = float(layout["plane_shift_z_m"])
	for control: String in order:
		depth += (points.get(control, Vector3.ZERO) as Vector3).z / float(order.size())
	var placed: Dictionary = {}
	var previous: String = ""
	for control: String in order:
		var y: float = float(wanted[control])
		if previous != "":
			var room: float = 0.5 * (float(heights[previous]) + float(heights[control])) + float(layout["row_gap_m"])
			y = minf(y, (placed[previous] as Vector3).y - room)
		var x: float = (points.get(control, Vector3.ZERO) as Vector3).x if over.has(control) \
			else float(layout["column_x_m"])
		placed[control] = Vector3(x, y, depth)
		previous = control
	return placed


static func _number_problem(key: String, value: Variant, bounds: Array) -> String:
	# A bool must not pass as 0 or 1.
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return "\"%s\" must be a number" % key
	if float(value) < float(bounds[0]) or float(value) > float(bounds[1]):
		return "\"%s\" is %s, must be within %s..%s" % [key, value, bounds[0], bounds[1]]
	return ""


static func _rejected(reason: String) -> Dictionary:
	return {"error": reason}
