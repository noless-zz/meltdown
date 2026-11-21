class_name ShipPartDef
extends RefCounted

## One non-weapon ship part (shield, hull, engine or utility module), read from
## a text data file so parts are data, not code branches (ARC-4, SLV-2, CRF-3).
## Parsed like `WeaponDef`: the caller reads the file and hands its text to
## `parse_json`, because core never opens files.
##
## A part changes a ship by multiplying numbers of the ship data file. Tuning
## stays in the ship file, and the multipliers are capped so a part widens the
## pilot's options without making a level trivial (CRW-3).

## Folder of the shipped part files, one file per part, named `<id>.json`.
const PARTS_DIR: String = "res://data/ship_parts"

## Every key of a part file.
const KEYS: Array[String] = ["id", "name", "kind", "stats"]
const KINDS: Array[String] = ["shield", "hull", "engine", "module"]
const NAME_MAX_LENGTH: int = 64

## `ShipTuning` keys each kind may multiply. Modules change no numbers yet.
const STAT_KEYS: Dictionary = {
	"shield": ["max_shield", "shield_recharge", "shield_energy_cost"],
	"hull": ["max_hull", "wall_damage_per_speed"],
	"engine": [
		"max_speed", "acceleration", "afterburner_max_speed",
		"afterburner_acceleration", "afterburner_drain",
	],
	"module": [],
}

## Inclusive range of every multiplier.
const MULTIPLIER_MIN: float = 0.5
const MULTIPLIER_MAX: float = 1.5

var id: String = ""
var display_name: String = ""
var kind: String = ""
## `ShipTuning` key to multiplier.
var stats: Dictionary[String, float] = {}

## Set by `parse_json` when the text was rejected; empty otherwise. Starts with
## the file name when one was given.
var error: String = ""


## Parses the text of a part file named `file` (for example `"x.json"`; may be
## empty). The `id` must equal the file name without `.json`, so an upgrade's
## `grants` id always finds its file.
static func parse_json(text: String, file: String = "") -> ShipPartDef:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _failed(file, "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _failed(file, "top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not KEYS.has(key):
			return _failed(file, "unknown key \"%s\"" % str(key))
	for key: String in KEYS:
		if not data.has(key):
			return _failed(file, "missing key \"%s\"" % key)
	var part: ShipPartDef = ShipPartDef.new()
	if typeof(data["id"]) != TYPE_STRING or (data["id"] as String).is_empty():
		return _failed(file, "key \"id\" must be a non-empty string")
	part.id = data["id"]
	if file != "" and file.get_basename() != part.id:
		return _failed(file, "key \"id\" is \"%s\", must match the file name" % part.id)
	var name_value: Variant = data["name"]
	if typeof(name_value) != TYPE_STRING or (name_value as String).strip_edges().is_empty() \
			or (name_value as String).length() > NAME_MAX_LENGTH:
		return _failed(file, "key \"name\" must be a string of 1 to %d characters" % NAME_MAX_LENGTH)
	part.display_name = name_value
	if typeof(data["kind"]) != TYPE_STRING or not KINDS.has(data["kind"]):
		return _failed(file, "key \"kind\" must be one of %s" % ", ".join(KINDS))
	part.kind = data["kind"]
	if typeof(data["stats"]) != TYPE_DICTIONARY:
		return _failed(file, "key \"stats\" must be an object")
	var allowed: Array = STAT_KEYS[part.kind]
	var raw: Dictionary = data["stats"]
	for stat: Variant in raw:
		if typeof(stat) != TYPE_STRING or not allowed.has(stat):
			return _failed(file, "stats key \"%s\" is not allowed for kind %s" % [str(stat), part.kind])
		var value: Variant = raw[stat]
		# A bool must not pass as 0 or 1.
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return _failed(file, "stats key \"%s\" must be a number" % stat)
		var multiplier: float = float(value)
		if not is_finite(multiplier) or multiplier < MULTIPLIER_MIN or multiplier > MULTIPLIER_MAX:
			return _failed(file, "stats key \"%s\" is %s, must be %s to %s" % [
				stat, multiplier, MULTIPLIER_MIN, MULTIPLIER_MAX])
		part.stats[stat] = multiplier
	return part


## Returns a copy of `tuning_data` (the parsed object of a ship data file) with
## every part's multipliers applied. Parts are applied in id order so the
## floating-point result is the same whatever order the array is in (ARC-1).
## Each changed number is then held inside `ShipTuning.RANGES`, so the copy
## still parses. `tuning_data` is never edited; no parts gives an exact copy.
static func apply(tuning_data: Dictionary, parts: Array[ShipPartDef]) -> Dictionary:
	var result: Dictionary = tuning_data.duplicate(true)
	if parts.is_empty():
		return result
	var ordered: Array[ShipPartDef] = parts.duplicate()
	ordered.sort_custom(func(a: ShipPartDef, b: ShipPartDef) -> bool: return a.id < b.id)
	for part: ShipPartDef in ordered:
		for stat: String in part.stats:
			if _is_number(result.get(stat)):
				result[stat] = float(result[stat]) * part.stats[stat]
	# `ShipTuning.KEYS` lists a key before any key whose bound names it, so each
	# bound is final by the time it is read.
	for key: String in ShipTuning.KEYS:
		if not _is_number(result.get(key)):
			continue
		var low: float = _bound(result, ShipTuning.RANGES[key][0])
		var high: float = _bound(result, ShipTuning.RANGES[key][1])
		result[key] = clampf(float(result[key]), low, high)
	return result


static func _bound(data: Dictionary, bound: Variant) -> float:
	if typeof(bound) == TYPE_STRING:
		return float(data.get(bound, 0.0))
	return float(bound)


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT


static func _failed(file: String, message: String) -> ShipPartDef:
	var part: ShipPartDef = ShipPartDef.new()
	part.error = message if file == "" else "%s: %s" % [file, message]
	return part
