class_name MenuSoundTable
extends RefCounted

## The development menu's sounds (#1457, AUD-1, CRW-2, ARC-4), read from
## `res://data/audio/menu_sounds.json`:
##
##     {
##       "voices": 3,               # sounds that may ring at once
##       "sounds": {"point": {"sound": "res://...", "volume_db": -20.0, "min_gap_s": 0.09}, ...},
##       "confirmed": {"close": "back", "restart": "launch", ...}
##     }
##
## `sounds` must name `open`, `point`, `change`, `confirm`, `refused` and
## `back`, one per thing the menu does, so each keeps its own `min_gap_s` and a
## fast scroll does not hold back a value change. The files are the home
## base's (`hub_*.wav`), so the menu sounds like the stations. `confirmed` maps
## what a confirm returned, up to its first `:` (`corner:centre` is `corner`),
## to a sound; anything else plays `confirm`. Any other field, or a field of the
## wrong type, rejects the whole file with `error` naming it, and the menu is
## then silent.
##
## Presentation only: it reads the menu's own state and changes nothing
## (ARC-3, MP-2).

const DEFAULT_FILE: String = "res://data/audio/menu_sounds.json"
const OPEN: String = "open"
const POINT: String = "point"
const CHANGE: String = "change"
const CONFIRM: String = "confirm"
const REFUSED: String = "refused"
const BACK: String = "back"
const NEEDED: Array[String] = [OPEN, POINT, CHANGE, CONFIRM, REFUSED, BACK]
const FIELDS: Array[String] = ["voices", "sounds", "confirmed"]
const SOUND_FIELDS: Array[String] = ["sound", "volume_db", "min_gap_s"]

var voices: int = 3
## Sound name to {"sound": res:// path, "volume_db": float, "min_gap_s": float}.
var sounds: Dictionary[String, Dictionary] = {}
## A confirm's result, up to its first `:`, to a sound name.
var confirmed: Dictionary[String, String] = {}
## Why the file was rejected, naming the field; empty when it was read.
var error: String = ""


static func load_file(path: String = DEFAULT_FILE) -> MenuSoundTable:
	if not FileAccess.file_exists(path):
		var missing: MenuSoundTable = MenuSoundTable.new()
		missing.error = "%s: no such file" % path
		return missing
	return parse(FileAccess.get_file_as_string(path))


## The table in `text`; on a rejected file it has no sounds and `error` says why.
static func parse(text: String) -> MenuSoundTable:
	var table: MenuSoundTable = MenuSoundTable.new()
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		return table._reject("not a JSON object")
	var root: Dictionary = data
	for key: Variant in root:
		if not FIELDS.has(str(key)):
			return table._reject("%s is not a field of the menu sounds" % key)
	if not _number(root.get("voices")) or int(root["voices"]) < 1:
		return table._reject("voices must be a whole number of at least 1")
	table.voices = int(root["voices"])
	if not root.get("sounds") is Dictionary:
		return table._reject("sounds must be an object")
	var rows: Dictionary = root["sounds"]
	for name: Variant in rows:
		var why: String = _row_error(str(name), rows[name])
		if why != "":
			return table._reject(why)
		var fields: Dictionary = rows[name]
		table.sounds[str(name)] = {"sound": str(fields["sound"]), "volume_db": float(fields["volume_db"]),
			"min_gap_s": float(fields["min_gap_s"])}
	for name: String in NEEDED:
		if not table.sounds.has(name):
			return table._reject("sounds.%s is missing" % name)
	if not root.get("confirmed", {}) is Dictionary:
		return table._reject("confirmed must be an object")
	var results: Dictionary = root.get("confirmed", {})
	for result: Variant in results:
		if not table.sounds.has(str(results[result])):
			return table._reject("confirmed.%s names %s, which is no sound" % [result, results[result]])
		table.confirmed[str(result)] = str(results[result])
	return table


## What the menu looks like for `event`: open or not, the list shown, the
## highlighted row and that row's words. `menu` is a `DevMenu`, or null.
static func state(menu: DevMenu) -> Dictionary:
	if menu == null or not menu.visible:
		return {"open": false}
	var model: DevMenuModel = menu.model
	return {"open": true, "section": model.rows.section, "row": model.selected,
		"text": DevMenu.row_text(model, model.selected, true)}


## The menu actions (`DevMenuModel.ACTIONS`) down in `held` and not in `before`.
static func pressed(before: Dictionary, held: Dictionary) -> Array[String]:
	var down: Array[String] = []
	for action: String in DevMenuModel.ACTIONS:
		if bool(held.get(action, false)) and not bool(before.get(action, false)):
			down.append(action)
	return down


## The sound for one frame of the menu, or "": `before` and `after` are
## `state()` around it, `down` the actions pressed that frame (`pressed`) and
## `result` what the menu returned. A frame with nothing pressed only sounds
## when the menu opens or closes, so an update hiding a row is silent.
func event(before: Dictionary, after: Dictionary, down: Array[String], result: String) -> String:
	var was_open: bool = bool(before.get("open", false))
	var is_open: bool = bool(after.get("open", false))
	if is_open and not was_open:
		return OPEN
	if was_open and not is_open:
		return confirmed_sound(result) if result != "" else BACK
	if not is_open or down.is_empty():
		return ""
	if result != "":
		return confirmed_sound(result)
	if before["section"] != after["section"]:
		return BACK if after["section"] == DevMenuRows.TOP else CONFIRM  # A Back row, or into a section.
	if before["row"] != after["row"]:
		return POINT
	if before["text"] != after["text"]:
		return CONFIRM if down.has(DevMenuModel.CONFIRM) else CHANGE  # Confirm arms Return to base.
	return REFUSED  # Pressed, and nothing could change: no value here, or a value that cannot move.


## The sound a confirm returning `result` plays.
func confirmed_sound(result: String) -> String:
	return confirmed.get(result.get_slice(":", 0), CONFIRM)


## Whether `name`, last played at `last` seconds (-INF for never), may play
## again at `now`.
func due(name: String, last: float, now: float) -> bool:
	return sounds.has(name) and now - last >= float(sounds[name]["min_gap_s"])


static func _row_error(name: String, row: Variant) -> String:
	if not row is Dictionary:
		return "sounds.%s must be an object" % name
	var fields: Dictionary = row
	for key: Variant in fields:
		if not SOUND_FIELDS.has(str(key)):
			return "sounds.%s.%s is not a field of a sound" % [name, key]
	if not fields.get("sound") is String or not str(fields["sound"]).begins_with("res://"):
		return "sounds.%s.sound must be a res:// path" % name
	if not _number(fields.get("volume_db")):
		return "sounds.%s.volume_db must be a number" % name
	if not _number(fields.get("min_gap_s")) or float(fields["min_gap_s"]) < 0.0:
		return "sounds.%s.min_gap_s must be a number of at least 0" % name
	return ""


static func _number(value: Variant) -> bool:
	return value is float or value is int


func _reject(why: String) -> MenuSoundTable:
	error = why
	sounds = {}
	confirmed = {}
	return self
