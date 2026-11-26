class_name RenderScaleTable
extends RefCounted

## The values dynamic resolution scaling runs on (#1417, GFX-7, ARC-4), read
## from `DEFAULT_FILE`:
##
##     {"enabled": true, "floor": 0.7, "ceiling": 1.0, "step": 0.1,
##      "high_water": 0.9, "low_water": 0.7, "frames_down": 5,
##      "frames_up": 45, "interval_frames": 30}
##
## `floor` and `ceiling` bound the render scale, a share of the full eye
## resolution; `step` is how far one change moves it. `high_water` and
## `low_water` are shares of the frame budget (one refresh interval): a frame
## longer than `high_water` of it counts as running long, one shorter than
## `low_water` as having headroom. `frames_down` long frames in a row lower
## the scale and `frames_up` frames with headroom in a row raise it, at most
## once per `interval_frames`. `enabled` false keeps the scale at 1.0.
##
## Every key is needed. A missing, mistyped or out-of-range value rejects the
## file with the field named (`error`); `load_file` then falls back to the
## built-in values with scaling off, so a broken file can never lower the
## picture.

const DEFAULT_FILE: String = "res://xr/render_scale.json"
## Each number with the range it must lie in, inclusive. The scale never goes
## above 1.0 (the full eye resolution) nor below half of it.
const RANGES: Dictionary[String, Vector2] = {
	"floor": Vector2(0.5, 1.0),
	"ceiling": Vector2(0.5, 1.0),
	"step": Vector2(0.01, 0.5),
	"high_water": Vector2(0.1, 2.0),
	"low_water": Vector2(0.1, 2.0),
}
## Each frame count with its range, inclusive; whole numbers only.
const COUNTS: Dictionary[String, Vector2i] = {
	"frames_down": Vector2i(1, 600),
	"frames_up": Vector2i(1, 600),
	"interval_frames": Vector2i(0, 600),
}
const ENABLED_KEY: String = "enabled"

var enabled: bool = false
var floor_scale: float = 0.7
var ceiling: float = 1.0
var step: float = 0.1
var high_water: float = 0.9
var low_water: float = 0.7
var frames_down: int = 5
var frames_up: int = 45
var interval_frames: int = 30
## Why the file was rejected, naming the field; "" when it was read.
var error: String = ""


## Parses the text of a render scale file; on a problem `error` names the field.
static func parse(text: String) -> RenderScaleTable:
	var table: RenderScaleTable = RenderScaleTable.new()
	table.error = table._read(text)
	return table


## The table at `path`. A missing or rejected file gives the built-in values
## with scaling off, `error` set, and a warning naming the field.
static func load_file(path: String = DEFAULT_FILE) -> RenderScaleTable:
	var table: RenderScaleTable = RenderScaleTable.new()
	table.error = "file not found"
	if FileAccess.file_exists(path):
		table = parse(FileAccess.get_file_as_string(path))
	if table.error != "":
		push_warning("Render scaling is off; %s: %s" % [path, table.error])
		var off: RenderScaleTable = RenderScaleTable.new()
		off.error = table.error
		return off
	return table


func _read(text: String) -> String:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]
	if typeof(json.data) != TYPE_DICTIONARY:
		return "top level must be a JSON object"
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not (RANGES.has(key) or COUNTS.has(key) or key == ENABLED_KEY):
			return "unknown key \"%s\"" % str(key)
	if not data.has(ENABLED_KEY):
		return "missing key \"%s\"" % ENABLED_KEY
	if typeof(data[ENABLED_KEY]) != TYPE_BOOL:
		return "\"%s\" must be true or false" % ENABLED_KEY
	for key: String in RANGES:
		var problem: String = _number(data, key)
		if problem != "":
			return problem
	for key: String in COUNTS:
		var problem: String = _count(data, key)
		if problem != "":
			return problem
	if float(data["floor"]) > float(data["ceiling"]):
		return "\"floor\" is %s, above \"ceiling\" %s" % [data["floor"], data["ceiling"]]
	if float(data["low_water"]) >= float(data["high_water"]):
		return "\"low_water\" is %s, must be below \"high_water\" %s" % [data["low_water"], data["high_water"]]
	enabled = data[ENABLED_KEY]
	floor_scale = float(data["floor"])
	ceiling = float(data["ceiling"])
	step = float(data["step"])
	high_water = float(data["high_water"])
	low_water = float(data["low_water"])
	frames_down = int(data["frames_down"])
	frames_up = int(data["frames_up"])
	interval_frames = int(data["interval_frames"])
	return ""


static func _number(data: Dictionary, key: String) -> String:
	if not data.has(key):
		return "missing key \"%s\"" % key
	var value: Variant = data[key]
	# A bool must not pass as 0 or 1.
	if (typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT) or not is_finite(float(value)):
		return "\"%s\" must be a number" % key
	var range_: Vector2 = RANGES[key]
	if float(value) < range_.x or float(value) > range_.y:
		return "\"%s\" is %s, must be within %s..%s" % [key, value, range_.x, range_.y]
	return ""


static func _count(data: Dictionary, key: String) -> String:
	if not data.has(key):
		return "missing key \"%s\"" % key
	var value: Variant = data[key]
	if (typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT) or not is_finite(float(value)) \
			or float(value) != floorf(float(value)):
		return "\"%s\" must be a whole number" % key
	var range_: Vector2i = COUNTS[key]
	if int(value) < range_.x or int(value) > range_.y:
		return "\"%s\" is %s, must be within %d..%d" % [key, value, range_.x, range_.y]
	return ""
