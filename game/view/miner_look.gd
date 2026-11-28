class_name MinerLook
extends RefCounted

## Parses `res://view/miner_look.json`, the look of a trapped miner's beacon
## and rescue ring (SLV-3, ARC-4), and holds the number and colour checks the
## other view looks share. Kept apart from `MinerView` so the node only draws
## (#1446).

const KEYS: Array[String] = ["beacon", "ring"]
const BEACON_KEYS: Array[String] = ["radius", "height", "color", "energy"]
const RING_KEYS: Array[String] = ["radius", "width", "track_color", "track_energy", "fill_color", "fill_energy"]
## Allowed range of every number key, inclusive.
const RANGES: Dictionary = {
	"radius": [0.05, 5.0], "height": [0.1, 10.0], "width": [0.01, 1.0],
	"energy": [0.0, 10.0], "track_energy": [0.0, 10.0], "fill_energy": [0.0, 20.0],
}
## Look used when the file is missing or rejected.
const FALLBACK: Dictionary = {
	"beacon": {"radius": 0.3, "height": 1.4, "color": Color(0.35, 1.0, 0.5), "energy": 3.0},
	"ring": {"radius": 1.3, "width": 0.14, "track_color": Color(0.4, 0.4, 0.4), "track_energy": 0.4,
		"fill_color": Color(0.5, 1.0, 0.6), "fill_energy": 3.0},
}


## Parses the text of a look file: `{"beacon": {"radius", "height", "color",
## "energy"}, "ring": {"radius", "width", "track_color", "track_energy",
## "fill_color", "fill_energy"}}`, colours as [r, g, b] within 0..1. Returns
## the look with colours as `Color`s, or a dictionary holding only `"error"`,
## which names the key.
static func parse(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return {"error": "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]}
	if typeof(json.data) != TYPE_DICTIONARY:
		return {"error": "top level must be a JSON object"}
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not (KEYS.has(key) or key == MinerPod.KEY or key == MinerLeave.KEY):
			return {"error": "unknown key \"%s\"" % str(key)}
	var look: Dictionary = {}
	if data.has(MinerLeave.KEY):
		look[MinerLeave.KEY] = MinerLeave.parse(data[MinerLeave.KEY])
		if look[MinerLeave.KEY].has("error"):
			return look[MinerLeave.KEY]
	if data.has(MinerPod.KEY):
		look[MinerPod.KEY] = MinerPod.parse(data[MinerPod.KEY])
		if look[MinerPod.KEY].has("error"):
			return look[MinerPod.KEY]
	var shapes: Dictionary = {"beacon": BEACON_KEYS, "ring": RING_KEYS}
	for part: String in shapes:
		var entry: Dictionary = _parse_entry(part, data.get(part, null), shapes[part])
		if entry.has("error"):
			return entry
		look[part] = entry
	if look["ring"]["width"] >= look["ring"]["radius"]:
		return {"error": "\"ring.width\" must be less than ring.radius"}
	return look


## A number key within its range, or the reason it is not.
static func check_number(field: String, value: Variant, limits: Array) -> String:
	# A bool must not pass as 0 or 1.
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return "\"%s\" must be a number" % field
	if float(value) < float(limits[0]) or float(value) > float(limits[1]):
		return "\"%s\" is %s, must be within %s..%s" % [field, value, limits[0], limits[1]]
	return ""


## `[r, g, b]` within 0..1 as a `Color`, or a String naming `field`.
static func parse_color(field: String, value: Variant) -> Variant:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 3:
		return "\"%s\" must be [red, green, blue]" % field
	for part: Variant in value:
		if (typeof(part) != TYPE_FLOAT and typeof(part) != TYPE_INT) or float(part) < 0.0 or float(part) > 1.0:
			return "\"%s\" must hold numbers within 0..1" % field
	return Color(float(value[0]), float(value[1]), float(value[2]))


static func _parse_entry(part: String, entry: Variant, keys: Array[String]) -> Dictionary:
	if typeof(entry) != TYPE_DICTIONARY:
		return {"error": "key \"%s\" must be an object" % part}
	var data: Dictionary = entry
	for key: Variant in data:
		if not keys.has(key):
			return {"error": "\"%s\" has unknown key \"%s\"" % [part, str(key)]}
	var look: Dictionary = {}
	for key: String in keys:
		var field: String = "%s.%s" % [part, key]
		if not data.has(key):
			return {"error": "\"%s\" is missing" % field}
		if key.ends_with("color"):
			var color: Variant = parse_color(field, data[key])
			if typeof(color) == TYPE_STRING:
				return {"error": color}
			look[key] = color
		else:
			var problem: String = check_number(field, data[key], RANGES[key])
			if problem != "":
				return {"error": problem}
			look[key] = float(data[key])
	return look
