class_name HubFitBars
extends RefCounted

## How the Fitting Bay draws a mount's before and after as bars (#1385, CRF-4,
## CRW-2, ARC-4), read from the optional `fit_bars` section of
## `data/hub/hub.json`, so sizes and colours change without code. Lengths are
## metres on the station screen's face, centred on its middle, +y up:
##
##     "fit_bars": {"compare_rows_visible": 2, "text_floor_m": 0.0, "top_y_m": -0.002,
##         "strip_height_m": 0.02, "strips_visible": 5, "pair_bar_length_m": 0.11,
##         "pair_bar_height_m": 0.0055, "before_color": [r, g, b], "after_color": [r, g, b]}
##
## While a slot is chosen the screen shows `compare_rows_visible` rows above
## `text_floor_m`, and under them, from `top_y_m`, one strip per attribute the
## selected item would change: two bars on one scale, the before over the
## after, with the stock mark across both. The ship summary's own bars, shown
## while a summary row is selected, take the `boards` section's sizes
## (`HubBoardLayout`), so the bay and the Crew Quarters draw them alike.

const KEY: String = "fit_bars"
const NUMBERS: Dictionary[String, Array] = {
	"compare_rows_visible": [1.0, 10.0],
	"text_floor_m": [-0.2, 0.2],
	"top_y_m": [-0.2, 0.2],
	"strip_height_m": [0.01, 0.1],
	"strips_visible": [1.0, 10.0],
	"pair_bar_length_m": [0.02, 0.3],
	"pair_bar_height_m": [0.002, 0.05],
}
const WHOLE: Array[String] = ["compare_rows_visible", "strips_visible"]
const COLORS: Array[String] = ["before_color", "after_color"]

var compare_rows_visible: int = 2
var text_floor_m: float = 0.0
var top_y_m: float = -0.002
var strip_height_m: float = 0.02
var strips_visible: int = 5
var pair_bar_length_m: float = 0.11
var pair_bar_height_m: float = 0.0055
var before_color: Color = Color(0.45, 0.5, 0.56)
var after_color: Color = Color(0.8, 0.87, 0.93)
## Whether the file has the section; without it the bay keeps its words.
var present: bool = false
## Why the section was refused; "" when it was read or absent.
var error: String = ""


## A layout from the section's value; `error` names the key at fault.
static func parse(value: Variant) -> HubFitBars:
	var bars: HubFitBars = HubFitBars.new()
	bars.error = bars._read(value)
	bars.present = bars.error == ""
	return bars


func has_bars() -> bool:
	return present and error == ""


func _read(value: Variant) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "key \"%s\" must be an object" % KEY
	var data: Dictionary = value
	for key: Variant in data:
		if not (NUMBERS.has(str(key)) or COLORS.has(str(key))):
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
	for key: String in COLORS:
		var color: Variant = HubFitLayout._color(data.get(key))
		if color == null:
			return "key \"%s.%s\" must be [red, green, blue], each within 0..1" % [KEY, key]
		set(key, color)
	return ""
