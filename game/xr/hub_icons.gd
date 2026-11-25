class_name HubIcons
extends RefCounted

## The home base's icon set (#1365, CRW-2, CRF-1, CRF-3, GFX-2, ARC-4, NAM-3,
## decision record 0012): one small drawn picture for every component kind,
## weapon, ship part family, utility module, crew role and ship attribute, so
## the stations can show things instead of listing names (#1359). Parsed from
## `res://data/hub/icons.json`:
##
##     {"size_m": .., "count_font_size": .., "pixel_size": .., "count_gap_m": ..,
##      "count_color": [r, g, b], "short_color": [r, g, b],
##      "backdrop_color": [r, g, b], "min_contrast": .., "min_color_distance": ..,
##      "fallback": <icon>,
##      "groups": {"component": {"<id>": <icon>, ..}, "weapon": {..}, ..}}
##
## An icon is described in `HubIconParts`. Icons are looked up by the id the
## data files use (ARC-4): an id with no icon draws `fallback` and warns once,
## so a new weapon or component file shows a plain marker until it is drawn,
## and nothing breaks. `backdrop_color` is the screens' face (#1359): every
## icon's colour must stand out from it by `min_contrast`, and the icons of a
## group must differ from one another by `min_color_distance` (RGB distance),
## so they can be told apart without their labels.

const DEFAULT_FILE: String = "res://data/hub/icons.json"
const GROUPS: Array[String] = ["component", "weapon", "part_family", "utility", "crew", "attribute"]
const RANGES: Dictionary[String, Array] = {
	"size_m": [0.01, 0.2],
	"count_font_size": [16.0, 256.0],
	"pixel_size": [0.0001, 0.002],
	"count_gap_m": [0.0, 0.05],
	"min_contrast": [1.5, 21.0],
	"min_color_distance": [0.05, 1.0],
}
const COLOR_KEYS: Array[String] = ["count_color", "short_color", "backdrop_color"]

## Lengths, sizes and limits keyed as in the file.
var numbers: Dictionary[String, float] = {}
var colors: Dictionary[String, Color] = {}
var fallback: Dictionary = {}
## Group to id to parsed icon.
var groups: Dictionary[String, Dictionary] = {}
## "group/id" of every lookup that fell back, in the order they happened.
var fell_back: Array[String] = []
## Why the file was refused; "" when it was read.
var error: String = ""


## The shipped file, or a set that draws only the fallback, naming its problem.
static func load_file(path: String = DEFAULT_FILE) -> HubIcons:
	if not FileAccess.file_exists(path):
		var missing: HubIcons = parse("")
		missing.error = "%s: file not found" % path
		push_warning("The home base draws plain markers; %s" % missing.error)
		return missing
	var icons: HubIcons = parse(FileAccess.get_file_as_string(path))
	if icons.error != "":
		push_warning("The home base draws plain markers; %s: %s" % [path, icons.error])
	return icons


## Never null: a refused text gives a set whose every lookup is the built-in
## marker, with `error` saying why.
static func parse(text: String) -> HubIcons:
	var icons: HubIcons = HubIcons.new()
	var json: JSON = JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		icons.error = "not a JSON object"
	else:
		icons.error = icons._read(json.data)
	if icons.error != "":
		icons._defaults()
	return icons


## The icon of `id` in `group`; the fallback, with a warning the first time,
## when there is none.
func icon(group: String, id: String) -> Dictionary:
	if groups.has(group) and groups[group].has(id):
		return groups[group][id]
	var key: String = "%s/%s" % [group, id]
	if not fell_back.has(key):
		push_warning("No home base icon for %s; drawing the plain marker" % key)
	fell_back.append(key)
	return fallback


func has_icon(group: String, id: String) -> bool:
	return groups.has(group) and groups[group].has(id)


## The ids drawn in `group`, sorted.
func ids(group: String) -> Array[String]:
	var found: Array[String] = []
	for id: Variant in groups.get(group, {}):
		found.append(str(id))
	found.sort()
	return found


## WCAG contrast ratio of two colours, 1..21.
static func contrast(a: Color, b: Color) -> float:
	var la: float = _luminance(a)
	var lb: float = _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func color_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


static func _luminance(c: Color) -> float:
	var channels: Array[float] = []
	for value: float in [c.r, c.g, c.b]:
		channels.append(value / 12.92 if value <= 0.03928 else pow((value + 0.055) / 1.055, 2.4))
	return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]


func _read(data: Dictionary) -> String:
	var known: Array = ["fallback", "groups"]
	known.append_array(RANGES.keys())
	known.append_array(COLOR_KEYS)
	for key: Variant in data:
		if not known.has(key):
			return "unknown key \"%s\"" % str(key)
	for key: Variant in known:
		if not data.has(key):
			return "missing key \"%s\"" % key
	for key: String in RANGES:
		var bounds: Array = RANGES[key]
		var value: Variant = data[key]
		if not HubIconParts.is_number(value) or float(value) < float(bounds[0]) or float(value) > float(bounds[1]):
			return "\"%s\" must be a number within %s..%s" % [key, bounds[0], bounds[1]]
		numbers[key] = float(value)
	for key: String in COLOR_KEYS:
		var color: Variant = HubIconParts.color_of(data[key])
		if color == null:
			return "\"%s\" must be [red, green, blue], each within 0..1" % key
		colors[key] = color
	fallback = HubIconParts.parse("fallback", data["fallback"])
	if fallback.has("error"):
		return fallback["error"]
	if typeof(data["groups"]) != TYPE_DICTIONARY:
		return "\"groups\" must be an object of group to icons"
	for group: Variant in data["groups"]:
		if not GROUPS.has(group):
			return "groups.%s is not one of %s" % [str(group), GROUPS]
		var problem: String = _read_group(str(group), data["groups"][group])
		if problem != "":
			return problem
	return ""


func _read_group(group: String, value: Variant) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "groups.%s must be an object of id to icon" % group
	var read: Dictionary = {}
	for id: Variant in value:
		var parsed: Dictionary = HubIconParts.parse("groups.%s.%s" % [group, str(id)], value[id])
		if parsed.has("error"):
			return parsed["error"]
		read[str(id)] = parsed
	groups[group] = read
	return ""


## A plain marker and sizes that still read, for a missing or refused file.
func _defaults() -> void:
	numbers = {"size_m": 0.03, "count_font_size": 32.0, "pixel_size": 0.0005, "count_gap_m": 0.006,
		"min_contrast": 3.0, "min_color_distance": 0.25}
	colors = {"count_color": Color(0.8, 0.87, 0.93), "short_color": Color(1.0, 0.64, 0.52),
		"backdrop_color": Color(0.02, 0.035, 0.05)}
	fallback = {"color": Color(0.7, 0.72, 0.75), "parts": [
		{"shape": "ring", "size": Vector2(0.8, 0.8), "at": Vector2.ZERO, "turn_deg": 0.0,
			"color": Color(0.7, 0.72, 0.75)}]}
	groups.clear()
