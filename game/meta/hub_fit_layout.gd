class_name HubFitLayout
extends RefCounted

## The ship the Fitting Bay draws from above (#1366, CRF-4, CRW-2, ARC-4): a
## flat outline and where each slot sits on it, read from the `fit_ship`
## section of `data/hub/hub.json`, so the drawing changes without code. It is a
## picture for choosing slots, not the 3D model (#1362). Lengths are metres on
## the screen's face, nose to +x, centred on the drawing's origin:
##
##     "fit_ship": {"center_y_m": -0.05, "slot_size_m": 0.026, "pick_radius_m": 0.02,
##         "slot_rows_visible": 1, "hull_color": [r, g, b],
##         "outline": [[x, y], ..],
##         "slots": {"primary": [[x, y], [x, y]], .., "engine": [[x, y]]}}
##
## `slots` gives one position per slot of each kind in slot order; a slot the
## ship has but the file places nowhere is still offered by the stick, only not
## drawn. `slot_rows_visible` is how many rows the screen shows under the
## title while the pilot chooses a slot, so the drawing has the face.

const KEY: String = "fit_ship"
const NUMBERS: Dictionary[String, Array] = {
	"center_y_m": [-0.2, 0.2],
	"slot_size_m": [0.005, 0.1],
	"pick_radius_m": [0.005, 0.1],
	"slot_rows_visible": [1.0, 10.0],
}
const KEYS: Array[String] = ["center_y_m", "slot_size_m", "pick_radius_m", "slot_rows_visible", "hull_color",
	"outline", "slots"]
## No point may be further than this from the drawing's origin.
const MAX_REACH_M: float = 0.3

var center_y_m: float = 0.0
var slot_size_m: float = 0.026
var pick_radius_m: float = 0.02
var slot_rows_visible: int = 1
var hull_color: Color = Color(0.2, 0.26, 0.32)
var outline: Array[Vector2] = []
## Slot kind to its positions, in slot order.
var slots: Dictionary[String, Array] = {}
## Why the section was refused; "" when it was read or absent.
var error: String = ""


## A layout from the section's value; `error` names the key at fault.
static func parse(value: Variant) -> HubFitLayout:
	var layout: HubFitLayout = HubFitLayout.new()
	layout.error = layout._read(value)
	return layout


## Whether the file drew a ship; without one the bay keeps its rows only.
func has_ship() -> bool:
	return error == "" and outline.size() >= 3


## Where slot `index` of `kind` sits, or null when the file places it nowhere.
func position_of(kind: String, index: int) -> Variant:
	var spots: Array = slots.get(kind, [])
	return spots[index] if index >= 0 and index < spots.size() else null


func _read(value: Variant) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "key \"%s\" must be an object" % KEY
	var data: Dictionary = value
	for key: Variant in data:
		if not KEYS.has(str(key)):
			return "key \"%s\" has unknown key \"%s\"" % [KEY, str(key)]
	for key: String in KEYS:
		if not data.has(key):
			return "key \"%s\" is missing \"%s\"" % [KEY, key]
	for key: String in NUMBERS:
		var number: Variant = data[key]
		var bounds: Array = NUMBERS[key]
		if not (typeof(number) in [TYPE_INT, TYPE_FLOAT]) or float(number) < float(bounds[0]) \
				or float(number) > float(bounds[1]):
			return "key \"%s.%s\" must be a number within %s..%s" % [KEY, key, bounds[0], bounds[1]]
	center_y_m = float(data["center_y_m"])
	slot_size_m = float(data["slot_size_m"])
	pick_radius_m = float(data["pick_radius_m"])
	slot_rows_visible = int(data["slot_rows_visible"])
	var color: Variant = _color(data["hull_color"])
	if color == null:
		return "key \"%s.hull_color\" must be [red, green, blue], each within 0..1" % KEY
	hull_color = color
	var problem: String = _points("outline", data["outline"], outline)
	if problem == "" and outline.size() < 3:
		problem = "key \"%s.outline\" needs at least 3 points" % KEY
	if problem == "" and Geometry2D.triangulate_polygon(PackedVector2Array(outline)).is_empty():
		problem = "key \"%s.outline\" is not a simple polygon" % KEY
	if problem != "":
		return problem
	if typeof(data["slots"]) != TYPE_DICTIONARY:
		return "key \"%s.slots\" must be an object of slot kind to positions" % KEY
	for kind: Variant in data["slots"]:
		if not HubWords.SLOT_KINDS.has(str(kind)):
			return "key \"%s.slots.%s\" is not one of %s" % [KEY, str(kind), HubWords.SLOT_KINDS]
		var spots: Array[Vector2] = []
		problem = _points("slots.%s" % kind, data["slots"][kind], spots)
		if problem != "":
			return problem
		slots[str(kind)] = spots
	return ""


static func _points(field: String, value: Variant, into: Array[Vector2]) -> String:
	if typeof(value) != TYPE_ARRAY:
		return "key \"%s.%s\" must be a list of [x, y]" % [KEY, field]
	for point: Variant in value:
		if typeof(point) != TYPE_ARRAY or (point as Array).size() != 2 \
				or not (typeof(point[0]) in [TYPE_INT, TYPE_FLOAT]) or not (typeof(point[1]) in [TYPE_INT, TYPE_FLOAT]):
			return "key \"%s.%s\" must be a list of [x, y]" % [KEY, field]
		var at: Vector2 = Vector2(float(point[0]), float(point[1]))
		if at.length() > MAX_REACH_M:
			return "key \"%s.%s\" has a point further than %s m out" % [KEY, field, MAX_REACH_M]
		into.append(at)
	return ""


static func _color(value: Variant) -> Variant:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 3:
		return null
	for channel: Variant in value:
		if not (typeof(channel) in [TYPE_INT, TYPE_FLOAT]) or float(channel) < 0.0 or float(channel) > 1.0:
			return null
	return Color(float(value[0]), float(value[1]), float(value[2]))
