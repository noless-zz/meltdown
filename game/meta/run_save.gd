class_name RunSave
extends RefCounted

## A run suspended between levels (#949, RUN-8): enough to start the next level
## of the same run on resume. Plain values only, so it does not depend on the
## run chain's own state class; this class is the data and its JSON text, and
## `RunSaveStore` puts it on disk; `RunResume` converts to and from a run.

## The newest layout this build understands. A file with a higher number came
## from a newer build and is never read or deleted by `take` (see RunSaveStore).
## Version 2 added `chosen` (#1029); a version-1 file has no shafts chosen.
const VERSION: int = 2
const KEY_VERSION: String = "version"
const KEY_RUN_SEED: String = "run_seed"
const KEY_NEXT_LEVEL: String = "next_level"
const KEY_SHIP: String = "ship"
const KEY_LOADOUT: String = "loadout"
const KEY_CHOSEN: String = "chosen"
## Every key of a version-1 file.
const KEYS_V1: Array[String] = [KEY_VERSION, KEY_RUN_SEED, KEY_NEXT_LEVEL, KEY_SHIP, KEY_LOADOUT]
## Every key of a file of the current version.
const KEYS: Array[String] = [KEY_VERSION, KEY_RUN_SEED, KEY_NEXT_LEVEL, KEY_SHIP, KEY_LOADOUT, KEY_CHOSEN]

var version: int = VERSION
## The seed the whole run's levels come from (GEN-2).
var run_seed: int = 0
## 1-based depth of the level a resume starts on.
var next_level: int = 1
## Ship data id, for example `default_ship` (`res://data/ships/<id>.json`).
var ship: String = ""
## Weapon slots to part ids, in the ship data file's shape:
## `{"primary": ["pulse_cannon", ""], "secondary": ["", ""]}`.
var loadout: Dictionary = {}
## The shaft kinds chosen so far, in order: the first is the shaft into depth 2
## (RUN-1, #1029). Empty for a run without choices and for a version-1 file.
var chosen: Array[String] = []
## Set when `parse_json` rejected the text; the save is then empty.
var error: String = ""
## True when the text was rejected only because its version is newer than ours.
var too_new: bool = false


## Empty when every field can be written and read back; otherwise names the
## first bad key.
func check() -> String:
	if version < 1 or version > VERSION:
		return "key \"%s\" is %d, must be 1 to %d" % [KEY_VERSION, version, VERSION]
	if next_level < 1:
		return "key \"%s\" is %d, must be at least 1" % [KEY_NEXT_LEVEL, next_level]
	var ship_error: String = ShipLoadout.check_id(KEY_SHIP, ship)
	if ship_error != "":
		return ship_error
	var read: ShipLoadout = ShipLoadout.from_data(loadout)
	if read.error != "":
		return "key \"%s\": %s" % [KEY_LOADOUT, read.error]
	if version < 2 and not chosen.is_empty():
		return "key \"%s\" needs version 2 or later" % KEY_CHOSEN
	for kind: String in chosen:
		if kind.is_empty():
			return "key \"%s\" has an empty shaft kind" % KEY_CHOSEN
	return ""


## JSON text with sorted keys. The seed is written as a decimal string: JSON
## numbers are read back as floats, which would round a seed above 2^53.
func to_json() -> String:
	var data: Dictionary = {
		KEY_VERSION: version,
		KEY_RUN_SEED: str(run_seed),
		KEY_NEXT_LEVEL: next_level,
		KEY_SHIP: ship,
		KEY_LOADOUT: loadout.duplicate(true),
	}
	if version >= 2:
		data[KEY_CHOSEN] = chosen.duplicate()
	return JSON.stringify(data, "\t", true) + "\n"


## Reads the text `to_json` writes. A rejected text gives an empty save with
## `error` set, naming the key (and `too_new` when the version is the only
## reason); never a crash.
static func parse_json(text: String) -> RunSave:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	# The version decides how the rest is read, so it is checked before the keys:
	# a newer build may have added keys this one does not know.
	if not data.has(KEY_VERSION) or not _whole_number(data[KEY_VERSION]):
		return _rejected("key \"%s\" must be a whole number" % KEY_VERSION)
	var file_version: int = int(data[KEY_VERSION])
	if file_version > VERSION:
		var newer: RunSave = _rejected(
			"run save version %d is newer than this build reads (%d)" % [file_version, VERSION])
		newer.too_new = true
		return newer
	if file_version < 1:
		return _rejected("key \"%s\" is %d, must be at least 1" % [KEY_VERSION, file_version])
	var keys: Array[String] = KEYS if file_version >= 2 else KEYS_V1
	for key: Variant in data:
		if not keys.has(str(key)):
			return _rejected("unknown key \"%s\"" % str(key))
	for key: String in keys:
		if not data.has(key):
			return _rejected("missing key \"%s\"" % key)
	if typeof(data[KEY_RUN_SEED]) != TYPE_STRING or not _exact_int_text(data[KEY_RUN_SEED]):
		return _rejected("key \"%s\" must be a whole number written as a string" % KEY_RUN_SEED)
	if not _whole_number(data[KEY_NEXT_LEVEL]):
		return _rejected("key \"%s\" must be a whole number" % KEY_NEXT_LEVEL)
	if typeof(data[KEY_SHIP]) != TYPE_STRING:
		return _rejected("key \"%s\" must be a string" % KEY_SHIP)
	if typeof(data[KEY_LOADOUT]) != TYPE_DICTIONARY:
		return _rejected("key \"%s\" must be an object" % KEY_LOADOUT)
	var read_chosen: Array[String] = []
	if file_version >= 2:
		if typeof(data[KEY_CHOSEN]) != TYPE_ARRAY:
			return _rejected("key \"%s\" must be an array of shaft kinds" % KEY_CHOSEN)
		for entry: Variant in data[KEY_CHOSEN]:
			if typeof(entry) != TYPE_STRING:
				return _rejected("key \"%s\" has %s, must hold only strings" % [KEY_CHOSEN, JSON.stringify(entry)])
			read_chosen.append(String(entry))
	var run: RunSave = RunSave.new()
	run.version = file_version
	run.chosen = read_chosen
	run.run_seed = String(data[KEY_RUN_SEED]).to_int()
	run.next_level = int(data[KEY_NEXT_LEVEL])
	run.ship = data[KEY_SHIP]
	run.loadout = (data[KEY_LOADOUT] as Dictionary).duplicate(true)
	var problem: String = run.check()
	if problem != "":
		return _rejected(problem)
	return run


## True for the digits `str(int)` writes: an optional minus and no leading
## zeros, within 64 bits. Anything else would not read back as the same seed.
static func _exact_int_text(text: String) -> bool:
	if not text.is_valid_int():
		return false
	# `to_int` reports an engine error past 64 bits, so compare the digits first.
	var digits: String = text.trim_prefix("-")
	var limit: String = "9223372036854775808" if text.begins_with("-") else "9223372036854775807"
	if digits.length() > limit.length() or (digits.length() == limit.length() and digits > limit):
		return false
	return str(text.to_int()) == text


## JSON gives every number as a float; a bool must not pass as 0 or 1.
static func _whole_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var number: float = value
	return is_finite(number) and number == floorf(number) and absf(number) < 1.0e15


static func _rejected(reason: String) -> RunSave:
	var run: RunSave = RunSave.new()
	run.error = reason
	return run
