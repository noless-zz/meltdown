class_name PickupHint
extends RefCounted

## When the slot control's label says "fly through to pick up" instead of
## naming the click (#600, #606, SLV-1, PLT-5). The owner pressed the stick
## click next to a floating part and expected it to pick the part up; parts
## are picked up by flying through them, and the click only slots a part
## already in the hold. So while the hold is empty and a part floats within
## `distance_m` of the ship, the label says how to pick it up.
##
## It reads session copies of the ship and the salvage and only decides a
## label's words: it never writes simulation state (ARC-3, MP-2). The distance
## is a guess for the next headset session and lives in
## `res://xr/pickup_hint.json` so the owner can change it (ARC-4).

const DEFAULT_FILE: String = "res://xr/pickup_hint.json"
const KEY: String = "distance_m"
## Allowed range of `distance_m`, inclusive. Below the pickup reach (about
## 2.5 m) the hint would only show once the part is already taken.
const MIN_DISTANCE_M: float = 1.0
const MAX_DISTANCE_M: float = 100.0

## Distance from the ship's centre to a part's centre, metres, within which
## the hint shows.
var distance_m: float = 12.0
## Set when the text was rejected; empty otherwise.
var error: String = ""


## Parses the text of a pickup-hint data file: one JSON object holding only
## `distance_m`, a number in range. On failure the returned hint has `error`
## set and the default distance.
static func parse_json(text: String) -> PickupHint:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if str(key) != KEY:
			return _rejected("unknown key \"%s\"" % str(key))
	if not data.has(KEY):
		return _rejected("missing key \"%s\"" % KEY)
	var value: Variant = data[KEY]
	# A bool must not pass as 0 or 1.
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return _rejected("key \"%s\" must be a number" % KEY)
	if float(value) < MIN_DISTANCE_M or float(value) > MAX_DISTANCE_M:
		return _rejected("key \"%s\" is %s, must be within %s..%s" % [KEY, value, MIN_DISTANCE_M, MAX_DISTANCE_M])
	var hint: PickupHint = PickupHint.new()
	hint.distance_m = float(value)
	return hint


## Reads and parses the file at `path`. A missing file is rejected like bad text.
static func load_file(path: String = DEFAULT_FILE) -> PickupHint:
	if not FileAccess.file_exists(path):
		return _rejected("file %s not found" % path)
	var hint: PickupHint = parse_json(FileAccess.get_file_as_string(path))
	if hint.error != "":
		hint.error = "%s: %s" % [path, hint.error]
	return hint


## True when `ship`'s hold is empty and a part of `salvage` floats within
## `distance_m` of the ship's centre.
func is_due(ship: ShipState, salvage: Array[SalvageItem]) -> bool:
	if ship == null or not ship.hold.is_empty():
		return false
	for item: SalvageItem in salvage:
		if item.position.distance_to(ship.position) <= distance_m:
			return true
	return false


static func _rejected(message: String) -> PickupHint:
	var hint: PickupHint = PickupHint.new()
	hint.error = message
	return hint
