class_name HubSoundTable
extends RefCounted

## The home base stations' sounds (#1401, AUD-1, CRW-2, ARC-4), read from
## `res://data/audio/hub_sounds.json`:
##
##     {
##       "voices": 4,               # sounds that may ring at once
##       "sounds": {"point": {"sound": "res://...", "volume_db": -20.0, "min_gap_s": 0.09}, ...},
##       "pressed": {"craft": "crafted", "fit:empty": "unmounted", ...}
##     }
##
## `sounds` must name `point`, `select`, `back` and `refused`, which the
## stations' own steps play. `pressed` maps a hub row's action to the sound a
## successful press of it plays; `<action>:empty` is a row of that action whose
## `id` is empty (clearing a slot), tried before plain `<action>`. A press whose
## action has no entry plays `select`. `min_gap_s` is the least time between two
## plays of the same sound, so walking a list with the stick does not tick like
## a machine gun.
##
## Presentation only: it reads the stations' state and the hub text's results,
## and changes neither (ARC-3, MP-2). It names no meta class: the actions are
## the hub rows' plain strings, as `HubStations` calls the hub text by name.

const DEFAULT_FILE: String = "res://data/audio/hub_sounds.json"
const POINT: String = "point"
const SELECT: String = "select"
const BACK: String = "back"
const REFUSED: String = "refused"
const NEEDED: Array[String] = [POINT, SELECT, BACK, REFUSED]
const EMPTY_SUFFIX: String = ":empty"

var voices: int = 4
## Sound name to {"sound": res:// path, "volume_db": float, "min_gap_s": float}.
var sounds: Dictionary[String, Dictionary] = {}
## Hub row action (or `<action>:empty`) to a sound name.
var pressed: Dictionary[String, String] = {}
## Why the file was rejected, naming the field; empty when it was read.
var error: String = ""


static func load_file(path: String = DEFAULT_FILE) -> HubSoundTable:
	if not FileAccess.file_exists(path):
		var missing: HubSoundTable = HubSoundTable.new()
		missing.error = "%s: no such file" % path
		return missing
	return parse(FileAccess.get_file_as_string(path))


## The table in `text`; on a rejected file it has no sounds and `error` says why.
static func parse(text: String) -> HubSoundTable:
	var table: HubSoundTable = HubSoundTable.new()
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		return table._reject("not a JSON object")
	var root: Dictionary = data
	if not _number(root.get("voices")) or int(root["voices"]) < 1:
		return table._reject("voices must be a whole number of at least 1")
	table.voices = int(root["voices"])
	if not root.get("sounds") is Dictionary:
		return table._reject("sounds must be an object")
	var rows: Dictionary = root["sounds"]
	for name: Variant in rows:
		var row: Variant = rows[name]
		if not row is Dictionary:
			return table._reject("sounds.%s must be an object" % name)
		var fields: Dictionary = row
		if not fields.get("sound") is String or not str(fields["sound"]).begins_with("res://"):
			return table._reject("sounds.%s.sound must be a res:// path" % name)
		if not _number(fields.get("volume_db")):
			return table._reject("sounds.%s.volume_db must be a number" % name)
		if not _number(fields.get("min_gap_s")) or float(fields["min_gap_s"]) < 0.0:
			return table._reject("sounds.%s.min_gap_s must be a number of at least 0" % name)
		table.sounds[str(name)] = {"sound": str(fields["sound"]), "volume_db": float(fields["volume_db"]),
			"min_gap_s": float(fields["min_gap_s"])}
	for name: String in NEEDED:
		if not table.sounds.has(name):
			return table._reject("sounds.%s is missing" % name)
	if not root.get("pressed", {}) is Dictionary:
		return table._reject("pressed must be an object")
	var presses: Dictionary = root.get("pressed", {})
	for action: Variant in presses:
		if not table.sounds.has(str(presses[action])):
			return table._reject("pressed.%s names %s, which is no sound" % [action, presses[action]])
		table.pressed[str(action)] = str(presses[action])
	return table


## What a station's state looks like for `event`: the station in use, the
## highlighted one and the selected line. `stations` is a `HubStations`.
static func state(stations: Object) -> Dictionary:
	var hub: Object = stations.get("hub")
	return {"in_use": str(stations.get("in_use")), "highlighted": int(stations.get("highlighted")),
		"line": int(hub.call("selected_line")) if hub != null else -1}


## The sound for one frame of the stations, or "": `before` and `after` are
## `state()` around it, `acted` the named action that frame pressed ("" for
## none) and `result` what `HubStations.update` returned.
func event(before: Dictionary, after: Dictionary, acted: String, result: Dictionary) -> String:
	if not result.is_empty():
		if str(result.get("reason", "")) != "":
			return REFUSED
		return pressed_sound(result.get("pressed", {}))
	if acted == DevMenuModel.CONFIRM and before["in_use"] == "" and after["in_use"] != "":
		return SELECT
	if acted == DevMenuModel.LEFT and before["in_use"] != "":
		return BACK  # Back to the ship, or out of the station.
	if before["in_use"] != after["in_use"]:
		return ""
	if before["highlighted"] != after["highlighted"] or before["line"] != after["line"]:
		return POINT  # The stick or the aim moved onto another station or row.
	return ""


## The sound a successful press of a row doing `picked` plays.
func pressed_sound(picked: Dictionary) -> String:
	var action: String = str(picked.get("action", ""))
	if picked.has("id") and str(picked["id"]) == "" and pressed.has(action + EMPTY_SUFFIX):
		return pressed[action + EMPTY_SUFFIX]
	return pressed.get(action, SELECT)


## Whether `name`, last played at `last` seconds (-INF for never), may play
## again at `now`.
func due(name: String, last: float, now: float) -> bool:
	return sounds.has(name) and now - last >= float(sounds[name]["min_gap_s"])


static func _number(value: Variant) -> bool:
	return value is float or value is int


func _reject(why: String) -> HubSoundTable:
	error = why
	sounds = {}
	pressed = {}
	return self
