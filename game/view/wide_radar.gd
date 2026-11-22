class_name WideRadar
extends RefCounted

## The wide radar module's data, `res://data/utility/wide_radar.json` (#1059,
## CRF-5, ARC-4): how far from the ship the hologram map shows tunnels while
## the module is in a utility slot.
##
##     {"reveal_radius_m": 40.0}
##
## The view reads it; core only knows the module's id (`ShipLoadout`), so the
## radar never changes simulation state (MP-2).

const PATH: String = "res://data/utility/wide_radar.json"
const RADIUS_KEY: String = "reveal_radius_m"

## Metres from the ship within which tunnel boxes are shown; 0 when rejected.
var reveal_radius_m: float = 0.0
## Set when the file was rejected, naming the file and the key; empty otherwise.
var error: String = ""


## Reads and checks the file at `path`.
static func load_file(path: String = PATH) -> WideRadar:
	if not FileAccess.file_exists(path):
		return _failed("%s: the file is missing" % path)
	return parse(FileAccess.get_file_as_string(path), path)


## Checks `text`, the contents of the file at `path` (used in messages only).
static func parse(text: String, path: String = PATH) -> WideRadar:
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return _failed("%s: must be a JSON object" % path)
	var entry: Dictionary = data
	for key: Variant in entry:
		if key != RADIUS_KEY:
			return _failed("%s: unknown key \"%s\"" % [path, str(key)])
	if not entry.has(RADIUS_KEY):
		return _failed("%s: \"%s\" is missing" % [path, RADIUS_KEY])
	var value: Variant = entry[RADIUS_KEY]
	if (typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT) or not is_finite(float(value)) \
			or float(value) <= 0.0:
		return _failed("%s: \"%s\" must be a positive number" % [path, RADIUS_KEY])
	var radar: WideRadar = WideRadar.new()
	radar.reveal_radius_m = float(value)
	return radar


static func _failed(message: String) -> WideRadar:
	var radar: WideRadar = WideRadar.new()
	radar.error = message
	return radar
