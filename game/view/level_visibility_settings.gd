class_name LevelVisibilitySettings
extends RefCounted

## The settings of room-and-portal visibility (#1364, GFX-3), read from
## `res://view/level_visibility.json` so culling can be switched off or widened
## without code (ARC-4):
##
## - `enabled`: false draws every box (the dev switch the acceptance step
##   compares against);
## - `tan_half_width`, `tan_half_height`: the view window, as tangents of the
##   half angles. Wider than both eyes of the headset together (Quest 3 shows
##   about 104 by 96 degrees), with room for the head turning between the pose
##   read and the frame shown; 1.8 by 1.6 is about 122 by 116 degrees;
## - `near_m`: an opening with a corner nearer than this does not narrow the view;
## - `margin_m`: openings are grown by this on every side, which covers each
##   eye's offset from the head (about 32 mm) and a head that moves;
## - `max_steps`: past this many openings tried in a frame, every box is drawn.
##
## A missing or rejected file falls back to `LevelVisibility.DEFAULTS` and
## names the field.

const DEFAULT_FILE: String = "res://view/level_visibility.json"
const RANGES: Dictionary = {
	"tan_half_width": [0.1, 10.0],
	"tan_half_height": [0.1, 10.0],
	"near_m": [0.001, 1.0],
	"margin_m": [0.0, 2.0],
	"max_steps": [1, 1000000],
}


## The settings in `text`, or a dictionary holding only "error".
static func parse(text: String) -> Dictionary:
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		return {"error": "top level must be a JSON object"}
	var given: Dictionary = data
	for key: Variant in given:
		if not LevelVisibility.DEFAULTS.has(key):
			return {"error": "unknown key \"%s\"" % str(key)}
	var settings: Dictionary = {}
	for key: String in LevelVisibility.DEFAULTS:
		if not given.has(key):
			return {"error": "missing key \"%s\"" % key}
		var value: Variant = given[key]
		if key == "enabled":
			if typeof(value) != TYPE_BOOL:
				return {"error": "\"enabled\" must be true or false"}
			settings[key] = value
			continue
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return {"error": "\"%s\" must be a number" % key}
		var bounds: Array = RANGES[key]
		if float(value) < float(bounds[0]) or float(value) > float(bounds[1]):
			return {"error": "\"%s\" is %s, must be within %s..%s" % [key, value, bounds[0], bounds[1]]}
		settings[key] = int(value) if key == "max_steps" else float(value)
	return settings


## The settings in the file at `path`, or one holding only "error" naming the
## path and the field.
static func load_file(path: String = DEFAULT_FILE) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": "%s: file not found" % path}
	var settings: Dictionary = parse(FileAccess.get_file_as_string(path))
	if settings.has("error"):
		return {"error": "%s: %s" % [path, settings["error"]]}
	return settings
