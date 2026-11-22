class_name UtilityRadius
extends RefCounted

## Reads a utility module's data file that holds one radius in metres, as
## `{"<key>": 40.0}` (ARC-4). Shared by `WideRadar` (#1059) and `MineScanner`
## (#1072) so both files are checked alike: a JSON object, the key present, no
## other keys, a positive finite number. Every error names the file and the key.


## The radius under `key` in `text`, the contents of the file at `path` (used in
## messages only), as `{"value": float, "error": String}`: the value and "", or
## 0 and an error naming `path` and the key.
static func parse(text: String, path: String, key: String) -> Dictionary:
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return _failed("%s: must be a JSON object" % path)
	var entry: Dictionary = data
	for name: Variant in entry:
		if name != key:
			return _failed("%s: unknown key \"%s\"" % [path, str(name)])
	if not entry.has(key):
		return _failed("%s: \"%s\" is missing" % [path, key])
	var value: Variant = entry[key]
	# A bool must not pass as 0 or 1, nor a string as a number.
	if (typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT) or not is_finite(float(value)) \
			or float(value) <= 0.0:
		return _failed("%s: \"%s\" must be a positive number" % [path, key])
	return {"value": float(value), "error": ""}


## Reads the file at `path` and parses it as `parse` does; a missing file is an
## error naming the path.
static func load_file(path: String, key: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failed("%s: the file is missing" % path)
	return parse(FileAccess.get_file_as_string(path), path, key)


static func _failed(message: String) -> Dictionary:
	return {"value": 0.0, "error": message}
