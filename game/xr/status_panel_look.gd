class_name StatusPanelLook
extends RefCounted

## Parses the status panel's look file, `res://xr/status_panel_look.json`
## (ARC-4). It holds the colour of the "ESCAPED" outcome row (#361) and, as an
## optional key, the hull fraction at or below which the hull row turns red and
## the low-hull pulse fires (#616):
##
##     {"escaped_color": [r, g, b], "low_hull_fraction": f}

const DEFAULT_FILE: String = "res://xr/status_panel_look.json"
const KEYS: Array[String] = ["escaped_color"]
## Keys a file may leave out; `FALLBACK` gives their value.
const OPTIONAL_NUMBER_KEYS: Array[String] = ["low_hull_fraction"]
## Used when the file is missing or rejected. Green, so an escape never reads
## as the red of a lost ship or a failing hull.
const FALLBACK: Dictionary = {
	"escaped_color": Color(0.35, 1.0, 0.45),
	"low_hull_fraction": 0.25,
}


## Parses the text of a look file. Returns the look with colours as `Color`,
## or a dictionary holding only `"error"`, which names the field.
static func parse(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return {"error": "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]}
	if typeof(json.data) != TYPE_DICTIONARY:
		return {"error": "top level must be a JSON object"}
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not (KEYS.has(key) or OPTIONAL_NUMBER_KEYS.has(key)):
			return {"error": "unknown key \"%s\"" % str(key)}
	var look: Dictionary = FALLBACK.duplicate()
	for key: String in OPTIONAL_NUMBER_KEYS:
		if not data.has(key):
			continue
		# A bool must not pass as 0 or 1.
		if typeof(data[key]) != TYPE_FLOAT and typeof(data[key]) != TYPE_INT:
			return {"error": "\"%s\" must be a number" % key}
		if float(data[key]) < 0.0 or float(data[key]) > 1.0:
			return {"error": "\"%s\" is %s, must be within 0..1" % [key, data[key]]}
		look[key] = float(data[key])
	for key: String in KEYS:
		if not data.has(key):
			return {"error": "missing key \"%s\"" % key}
		var parts: Variant = data[key]
		if typeof(parts) != TYPE_ARRAY or (parts as Array).size() != 3:
			return {"error": "\"%s\" must be [red, green, blue]" % key}
		for part: Variant in parts:
			# A bool must not pass as 0 or 1.
			if typeof(part) != TYPE_FLOAT and typeof(part) != TYPE_INT:
				return {"error": "\"%s\" must hold numbers" % key}
			if float(part) < 0.0 or float(part) > 1.0:
				return {"error": "\"%s\" has %s, must be within 0..1" % [key, part]}
		look[key] = Color(float(parts[0]), float(parts[1]), float(parts[2]))
	return look


## Reads the look file at `path`. A missing or rejected file gives `FALLBACK`
## and pushes a warning naming the field.
static func load_file(path: String = DEFAULT_FILE) -> Dictionary:
	var values: Dictionary = {"error": "file not found"}
	if FileAccess.file_exists(path):
		values = parse(FileAccess.get_file_as_string(path))
	if values.has("error"):
		push_warning("StatusPanel uses the built-in look; %s: %s" % [path, values["error"]])
		return FALLBACK
	return values
