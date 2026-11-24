class_name HubWords
extends RefCounted

## The words of the hub's rows (CRW-2, ARC-4, NAM-3, #1058), the `text` object of
## `data/hub/hub.json`, so every line a hub panel shows can change without code.
## Row texts are `String.format` patterns; the placeholders each row may use are
## listed in `PLACEHOLDERS`. Kept apart from `HubConfig`, which reads the rest of
## the file, so each class stays small.

## Row patterns, each with the placeholders `HubText` fills in. A `_note` key
## (and `launch_discard_note`, `stats_empty`) is the one line of explanation
## shown under its row only while that row is selected (#1300).
const PLACEHOLDERS: Dictionary[String, Array] = {
	"crew_row": ["role"],
	"crew_note": ["amount", "stat"],
	"store_row": ["name", "count"],
	"store_note": ["tier"],
	"ready_header": [],
	"locked_header": [],
	"built_header": [],
	"ready_row": ["name"],
	"locked_row": ["name"],
	"locked_note": ["reason"],
	"built_row": ["name"],
	"slot_row": ["slot", "fitted"],
	"slot_upgrade": ["name"],
	"slot_part": ["part"],
	"slot_empty": [],
	"slot_stock": [],
	"fit_option_row": ["name"],
	"clear_row": [],
	"launch_row": [],
	"resume_row": ["level"],
	"resume_note": ["seed"],
	"launch_discard_note": [],
	"resume_none": [],
	"empty_crew_note": [],
	"empty_store_note": [],
	"stats_empty": [],
	"stats_runs_started": ["count"],
	"stats_runs_won": ["count"],
	"stats_runs_lost": ["count"],
	"stats_levels_escaped": ["count"],
	"stats_deepest_level": ["count"],
	"stats_miners_rescued": ["count"],
	"stats_components_banked": ["count"],
}
## Logbook rows (#1095) are `STATS_ROW_PREFIX` + a `ProfileStats` counter key.
const STATS_ROW_PREFIX: String = "stats_"
const KEY_SLOT_NAMES: String = "slot_names"
const KEY_STAT_NAMES: String = "stat_names"
## Slot kinds a slot name is needed for: `Fitting.KEYS`, then `Fitting.PART_KEYS`.
const SLOT_KINDS: Array[String] = ["primary", "secondary", "utility", "shield", "hull", "engine"]

var rows: Dictionary[String, String] = {}
## Slot kind to a pattern with `{number}`, counted from 1.
var slot_names: Dictionary[String, String] = {}
## Crew benefit stat id to its shown name; an unlisted stat shows its id.
var stat_names: Dictionary[String, String] = {}
## Set by `parse` when the value was rejected; every error names the key.
var error: String = ""


## Reads the value of the `text` key. Every error names the key under `text`.
static func parse(value: Variant, max_length: int) -> HubWords:
	var words: HubWords = HubWords.new()
	if typeof(value) != TYPE_DICTIONARY:
		return _failed("key \"text\" must be an object")
	var data: Dictionary = value
	for key: Variant in data:
		if not (PLACEHOLDERS.has(str(key)) or str(key) == KEY_SLOT_NAMES or str(key) == KEY_STAT_NAMES):
			return _failed("key \"text\" has unknown key \"%s\"" % str(key))
	for key: String in PLACEHOLDERS:
		var message: String = _check("text.%s" % key, data.get(key), max_length)
		if message != "":
			return _failed(message)
		words.rows[key] = data[key]
	var message: String = words._read_names(data, KEY_SLOT_NAMES, SLOT_KINDS, words.slot_names, max_length)
	if message == "":
		message = words._read_names(data, KEY_STAT_NAMES, [], words.stat_names, max_length)
	if message != "":
		return _failed(message)
	return words


## Row `key` with `values` filled in.
func row(key: String, values: Dictionary = {}) -> String:
	var pattern: String = rows.get(key, "")
	return pattern.format(values)


## The shown name of slot `kind` number `index` (0 based).
func slot_name(kind: String, index: int) -> String:
	var pattern: String = slot_names.get(kind, kind)
	return pattern.format({"number": index + 1})


func stat_name(stat: String) -> String:
	return stat_names.get(stat, stat)


## Reads object `key` of strings into `into`; `required` keys must all be there.
func _read_names(data: Dictionary, key: String, required: Array, into: Dictionary[String, String],
		max_length: int) -> String:
	if typeof(data.get(key)) != TYPE_DICTIONARY:
		return "key \"text.%s\" must be an object" % key
	var names: Dictionary = data[key]
	for name: Variant in names:
		var message: String = _check("text.%s.%s" % [key, str(name)], names[name], max_length)
		if message != "":
			return message
		into[str(name)] = names[name]
	for name: String in required:
		if not into.has(name):
			return "key \"text.%s\" is missing \"%s\"" % [key, name]
	return ""


static func _check(key: String, value: Variant, max_length: int) -> String:
	if typeof(value) != TYPE_STRING or String(value).strip_edges().is_empty():
		return "key \"%s\" must be a non-empty string" % key
	if String(value).length() > max_length:
		return "key \"%s\" is longer than %d characters" % [key, max_length]
	return ""


static func _failed(message: String) -> HubWords:
	var words: HubWords = HubWords.new()
	words.error = message
	return words
