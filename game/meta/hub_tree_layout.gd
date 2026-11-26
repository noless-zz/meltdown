class_name HubTreeLayout
extends RefCounted

## How the Workbench station draws the tech tree (#1367, CRF-3, CRF-6, CRW-2,
## CMF-8, ARC-4), read from the `craft_tree` section of `data/hub/hub.json`,
## so the drawing changes without code. Lengths are metres on the station
## screen's face, centred on its middle, +y up:
##
##     "craft_tree": {"rows_visible": 4, "text_floor_m": -0.05, "top_y_m": -0.06,
##         "tier_step_m": 0.02, "column_step_m": 0.024, "branch_gap_m": 0.012,
##         "window_m": 0.3, "node_size_m": 0.016, "pick_radius_m": 0.012,
##         "edge_width_m": 0.002, "effect_icons": {"<part file key>": "<attribute icon id>", ..}}
##
## Tier 1 is drawn at `top_y_m`, each deeper tier `tier_step_m` lower. Every
## upgrade that unlocks nothing is a leaf with a column of its own, in the order
## the stick walks the tree; a node that unlocks others sits over the middle
## of them, and branches are `branch_gap_m` apart. Only `window_m` of the
## tree's width shows at once, scrolled to the selected node, so a wide tree
## pans on the screen and the pilot's view never moves (CMF-8).
## `rows_visible` is how many rows of words show above it, and no word goes
## below `text_floor_m`.

const KEY: String = "craft_tree"
const NUMBERS: Dictionary[String, Array] = {
	"rows_visible": [1.0, 10.0],
	"text_floor_m": [-0.2, 0.2],
	"top_y_m": [-0.2, 0.2],
	"tier_step_m": [0.005, 0.1],
	"column_step_m": [0.005, 0.1],
	"branch_gap_m": [0.0, 0.1],
	"window_m": [0.05, 0.4],
	"node_size_m": [0.005, 0.1],
	"pick_radius_m": [0.002, 0.1],
	"edge_width_m": [0.0005, 0.02],
}
const KEY_EFFECT_ICONS: String = "effect_icons"

var rows_visible: int = 4
var text_floor_m: float = -0.05
var top_y_m: float = -0.06
var tier_step_m: float = 0.02
var column_step_m: float = 0.024
var branch_gap_m: float = 0.012
var window_m: float = 0.3
var node_size_m: float = 0.016
var pick_radius_m: float = 0.012
var edge_width_m: float = 0.002
## Part file number key to the `attribute` icon an effect line shows.
var effect_icons: Dictionary[String, String] = {}
## Whether the file has the section; without it the Workbench keeps its rows.
var present: bool = false
## Why the section was refused; "" when it was read or absent.
var error: String = ""


## A layout from the section's value; `error` names the key at fault.
static func parse(value: Variant) -> HubTreeLayout:
	var layout: HubTreeLayout = HubTreeLayout.new()
	layout.error = layout._read(value)
	layout.present = layout.error == ""
	return layout


func has_tree() -> bool:
	return present and error == ""


func _read(value: Variant) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "key \"%s\" must be an object" % KEY
	var data: Dictionary = value
	for key: Variant in data:
		if not (NUMBERS.has(str(key)) or str(key) == KEY_EFFECT_ICONS):
			return "key \"%s\" has unknown key \"%s\"" % [KEY, str(key)]
	for key: String in NUMBERS:
		var number: Variant = data.get(key)
		var bounds: Array = NUMBERS[key]
		if not (typeof(number) in [TYPE_INT, TYPE_FLOAT]) or float(number) < float(bounds[0]) \
				or float(number) > float(bounds[1]):
			return "key \"%s.%s\" must be a number within %s..%s" % [KEY, key, bounds[0], bounds[1]]
	if float(data["rows_visible"]) != floorf(float(data["rows_visible"])):
		return "key \"%s.rows_visible\" must be a whole number" % KEY
	rows_visible = int(data["rows_visible"])
	text_floor_m = float(data["text_floor_m"])
	top_y_m = float(data["top_y_m"])
	tier_step_m = float(data["tier_step_m"])
	column_step_m = float(data["column_step_m"])
	branch_gap_m = float(data["branch_gap_m"])
	window_m = float(data["window_m"])
	node_size_m = float(data["node_size_m"])
	pick_radius_m = float(data["pick_radius_m"])
	edge_width_m = float(data["edge_width_m"])
	var icons: Variant = data.get(KEY_EFFECT_ICONS, {})
	if typeof(icons) != TYPE_DICTIONARY:
		return "key \"%s.%s\" must be an object of part file key to icon id" % [KEY, KEY_EFFECT_ICONS]
	for key: Variant in icons:
		if typeof(icons[key]) != TYPE_STRING or str(icons[key]) == "":
			return "key \"%s.%s.%s\" must be an icon id" % [KEY, KEY_EFFECT_ICONS, str(key)]
		effect_icons[str(key)] = str(icons[key])
	return ""
