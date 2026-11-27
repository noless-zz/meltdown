class_name UpdateSignLook
extends RefCounted

## What the "Update available" sign at the home base says and where it stands
## (#1450, DEV-8, CRW-2, ARC-4), from `res://xr/update_sign.json`:
##
##     {"position_m": [0.4, -0.4, -0.35], "title_text": "Update available: {version}",
##      "hint_text": "Update: open the menu", "line_pitch_m": 0.045,
##      "pixel_size_m": 0.0007, "font_size": 48}
##
## `position_m` is in the room's space, whose origin is the seated pilot's eye
## point: right, up, forward is -z. `{version}` names the waiting build. Every
## key is optional; a missing or refused file gives the built-in values, with
## `error` naming the field. No nodes: `UpdateSign` draws it.

const DEFAULT_FILE: String = "res://xr/update_sign.json"
const TEXT_KEYS: Array[String] = ["title_text", "hint_text"]
const NUMBER_KEYS: Array[String] = ["line_pitch_m", "pixel_size_m", "font_size"]

## Low and to the right of the seat, below the line of sight to the stations.
var position_m: Vector3 = Vector3(0.4, -0.4, -0.35)
var title_text: String = "Update available: {version}"
var hint_text: String = "Update: open the menu"
var line_pitch_m: float = 0.045
var pixel_size_m: float = 0.0007
var font_size: float = 48.0
## Why the file was refused, or "".
var error: String = ""


## Reads `path`; a missing or refused file gives the built-in values with `error` set.
static func load_file(path: String = DEFAULT_FILE) -> UpdateSignLook:
	if not FileAccess.file_exists(path):
		var missing: UpdateSignLook = UpdateSignLook.new()
		missing.error = "file not found"
		return missing
	var look: UpdateSignLook = parse(FileAccess.get_file_as_string(path))
	if look.error != "":
		push_warning("UpdateSign uses the built-in look; %s: %s" % [path, look.error])
	return look


## Parses a sign file's text; on a problem the built-in values stay and `error` names the field.
static func parse(text: String) -> UpdateSignLook:
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return _refused("not a JSON object")
	var read: UpdateSignLook = UpdateSignLook.new()
	read.error = read._read(data)
	return read if read.error == "" else _refused(read.error)


## The sign's lines for the waiting build `version`; none when no build waits.
func lines(version: String) -> Array[String]:
	if version == "":
		return []
	return [title_text.replace("{version}", version), hint_text.replace("{version}", version)]


func _read(data: Dictionary) -> String:
	for key: Variant in data:
		if not (["position_m"] + TEXT_KEYS + NUMBER_KEYS).has(str(key)):
			return "unknown key \"%s\"" % str(key)
	if data.has("position_m"):
		var value: Variant = data["position_m"]
		if typeof(value) != TYPE_ARRAY or (value as Array).size() != 3:
			return "\"position_m\" must be [right, up, back] in metres"
		for item: Variant in value:
			if not (item is float or item is int):
				return "\"position_m\" must be [right, up, back] in metres"
		position_m = Vector3(float(value[0]), float(value[1]), float(value[2]))
		if position_m.length() < 0.1:
			return "\"position_m\" must be at least 0.1 m from the eye point"
	for key: String in TEXT_KEYS:
		if data.has(key):
			if typeof(data[key]) != TYPE_STRING or (data[key] as String).strip_edges() == "":
				return "\"%s\" must be a non-empty string" % key
			set(key, data[key])
	for key: String in NUMBER_KEYS:
		if data.has(key):
			if not (data[key] is float or data[key] is int) or float(data[key]) <= 0.0:
				return "\"%s\" must be a number over 0" % key
			set(key, float(data[key]))
	return ""


static func _refused(problem: String) -> UpdateSignLook:
	var built_in: UpdateSignLook = UpdateSignLook.new()
	built_in.error = problem
	return built_in
