class_name HubBoardLayout
extends RefCounted

## How the Crew Quarters and the Logbook draw their boards (#1368, CRW-1,
## CRW-2, ARC-4), read from the `boards` section of `data/hub/hub.json`, so
## sizes, the attribute icons and the Logbook's captions change without code.
## Lengths are metres on the station screen's face, centred on its middle, +y up:
##
##     "boards": {"rows_visible": 1, "text_floor_m": 0.0, "top_y_m": -0.004,
##         "strip_height_m": 0.024, "strips_visible": 4, "icon_size_m": 0.02,
##         "bar_length_m": 0.15, "bar_height_m": 0.009, "bar_headroom": 1.5,
##         "tile_columns": 4, "tile_height_m": 0.048,
##         "attribute_icons": {"<summary stat>": "<attribute icon id>", ..},
##         "log_captions": {"<ProfileStats key>": "<short word>", ..},
##         "log_bars": {"<ProfileStats key>": "<ProfileStats key it is part of>", ..}}
##
## The board starts at `top_y_m` and fills down in strips (a crew card or an
## attribute bar, `strips_visible` at once, scrolled to the selection) or in
## tiles (the Logbook's figures, `tile_columns` to a line). A bar's full length
## stands for `bar_headroom` times the stock value, or more when the current
## value or the crew's cap is higher, so a raise is seen against the stock mark.
## `rows_visible` rows of words show above the board, none below `text_floor_m`.

const KEY: String = "boards"
const NUMBERS: Dictionary[String, Array] = {
	"rows_visible": [1.0, 10.0],
	"text_floor_m": [-0.2, 0.2],
	"top_y_m": [-0.2, 0.2],
	"strip_height_m": [0.01, 0.1],
	"strips_visible": [1.0, 10.0],
	"icon_size_m": [0.005, 0.1],
	"bar_length_m": [0.02, 0.3],
	"bar_height_m": [0.002, 0.05],
	"bar_headroom": [1.0, 10.0],
	"tile_columns": [1.0, 10.0],
	"tile_height_m": [0.01, 0.1],
}
const WHOLE: Array[String] = ["rows_visible", "strips_visible", "tile_columns"]
const KEY_ATTRIBUTE_ICONS: String = "attribute_icons"
const KEY_LOG_CAPTIONS: String = "log_captions"
const KEY_LOG_BARS: String = "log_bars"
const MAX_CAPTION: int = 10

var rows_visible: int = 1
var text_floor_m: float = 0.0
var top_y_m: float = -0.004
var strip_height_m: float = 0.024
var strips_visible: int = 4
var icon_size_m: float = 0.02
var bar_length_m: float = 0.15
var bar_height_m: float = 0.009
var bar_headroom: float = 1.5
var tile_columns: int = 4
var tile_height_m: float = 0.048
## Summary stat (`ShipSummary.attributes`) to the `attribute` icon it shows.
var attribute_icons: Dictionary[String, String] = {}
## Logbook counter to the short word under its figure.
var log_captions: Dictionary[String, String] = {}
## Logbook counter to the counter it is a part of, drawn as a bar of that whole.
var log_bars: Dictionary[String, String] = {}
## Whether the file has the section; without it both stations keep their rows.
var present: bool = false
## Why the section was refused; "" when it was read or absent.
var error: String = ""


## A layout from the section's value; `error` names the key at fault.
static func parse(value: Variant) -> HubBoardLayout:
	var layout: HubBoardLayout = HubBoardLayout.new()
	layout.error = layout._read(value)
	layout.present = layout.error == ""
	return layout


func has_boards() -> bool:
	return present and error == ""


## The icon id of summary stat `stat`, or "" when the file gives none.
func attribute_icon(stat: String) -> String:
	return attribute_icons.get(stat, "")


func _read(value: Variant) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "key \"%s\" must be an object" % KEY
	var data: Dictionary = value
	for key: Variant in data:
		if not (NUMBERS.has(str(key)) or str(key) in [KEY_ATTRIBUTE_ICONS, KEY_LOG_CAPTIONS, KEY_LOG_BARS]):
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
	var message: String = _strings(data.get(KEY_ATTRIBUTE_ICONS, {}), KEY_ATTRIBUTE_ICONS, attribute_icons, 64)
	if message == "":
		message = _strings(data.get(KEY_LOG_CAPTIONS), KEY_LOG_CAPTIONS, log_captions, MAX_CAPTION)
	if message == "":
		message = _strings(data.get(KEY_LOG_BARS, {}), KEY_LOG_BARS, log_bars, 64)
	if message != "":
		return message
	for key: String in ProfileStats.KEYS:
		if not log_captions.has(key):
			return "key \"%s.%s\" is missing counter \"%s\"" % [KEY, KEY_LOG_CAPTIONS, key]
	for key: String in log_bars:
		if not ProfileStats.KEYS.has(key) or not ProfileStats.KEYS.has(log_bars[key]) or key == log_bars[key]:
			return "key \"%s.%s.%s\" must name two different counters" % [KEY, KEY_LOG_BARS, key]
	return ""


## Reads an object of non-empty strings of at most `longest` characters into `into`.
static func _strings(value: Variant, key: String, into: Dictionary[String, String], longest: int) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "key \"%s.%s\" must be an object of strings" % [KEY, key]
	for each: Variant in value:
		var text: Variant = value[each]
		if typeof(text) != TYPE_STRING or str(text).strip_edges() == "" or str(text).length() > longest:
			return "key \"%s.%s.%s\" must be a string of 1..%d characters" % [KEY, key, str(each), longest]
		into[str(each)] = str(text)
	return ""
