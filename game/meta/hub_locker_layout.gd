class_name HubLockerLayout
extends RefCounted

## How the Workbench's Parts Locker face draws (#1413, CRF-1, CRF-3, ARC-4),
## read from the `locker` section of `data/hub/hub.json`, so sizes change
## without code. Lengths are metres on the station screen's face, centred on
## its middle, +y up:
##
##     "locker": {"rows_visible": 3, "text_floor_m": -0.04, "top_y_m": -0.05,
##         "tile_columns": 4, "tile_height_m": 0.045, "icon_size_m": 0.026,
##         "uses_shown": 2}
##
## `rows_visible` rows of words show above `text_floor_m`; under them, from
## `top_y_m`, one line of `tile_columns` component tiles (icon and count),
## the line holding the selected one. A selected component lists at most
## `uses_shown` rows of the upgrades that spend it.

const KEY: String = "locker"
const NUMBERS: Dictionary[String, Array] = {
	"rows_visible": [1.0, 5.0],
	"text_floor_m": [-0.2, 0.2],
	"top_y_m": [-0.2, 0.2],
	"tile_columns": [1.0, 10.0],
	"tile_height_m": [0.01, 0.1],
	"icon_size_m": [0.005, 0.1],
	"uses_shown": [1.0, 4.0],
}
const WHOLE: Array[String] = ["rows_visible", "tile_columns", "uses_shown"]

var rows_visible: int = 3
var text_floor_m: float = -0.04
var top_y_m: float = -0.05
var tile_columns: int = 4
var tile_height_m: float = 0.045
var icon_size_m: float = 0.026
var uses_shown: int = 2
## Whether the file has the section; without it the Workbench has no Locker face.
var present: bool = false
## Why the section was refused; "" when it was read or absent.
var error: String = ""


## A layout from the section's value; `error` names the key at fault.
static func parse(value: Variant) -> HubLockerLayout:
	var layout: HubLockerLayout = HubLockerLayout.new()
	layout.error = layout._read(value)
	layout.present = layout.error == ""
	return layout


func has_locker() -> bool:
	return present and error == ""


func _read(value: Variant) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "key \"%s\" must be an object" % KEY
	var data: Dictionary = value
	for key: Variant in data:
		if not NUMBERS.has(str(key)):
			return "key \"%s\" has unknown key \"%s\"" % [KEY, str(key)]
	for key: String in NUMBERS:
		var number: Variant = data.get(key)
		var bounds: Array = NUMBERS[key]
		if not (typeof(number) in [TYPE_INT, TYPE_FLOAT]) or float(number) < float(bounds[0]) \
				or float(number) > float(bounds[1]):
			return "key \"%s.%s\" must be a number within %s..%s" % [KEY, key, bounds[0], bounds[1]]
		if WHOLE.has(key) and float(number) != floorf(float(number)):
			return "key \"%s.%s\" must be a whole number" % [KEY, key]
		set(key, int(number) if WHOLE.has(key) else float(number))
	return ""
