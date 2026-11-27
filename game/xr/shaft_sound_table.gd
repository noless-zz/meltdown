class_name ShaftSoundTable
extends RefCounted

## The shaft choice's sounds (#1455, AUD-1, RUN-1, ARC-4), read from
## `res://data/audio/shaft_sounds.json`:
##
##     {
##       "voices": 3,               # sounds that may ring at once
##       "sounds": {"point": {"sound": "res://...", "volume_db": -20.0, "min_gap_s": 0.09}, ...}
##     }
##
## `sounds` must name `point`, `select`, `refused` and `launch`. The file is its
## own rather than a section of the base's `hub_sounds.json`, which another lane
## owns (decision record 0003); it may play the same `hub_*.wav` files so the
## shaft choice sounds like the base. `min_gap_s` is the least time between two
## plays of the same sound, so stepping down the list does not tick on every frame.
##
## Presentation only: `events` reads the panel's highlight and the press's
## answer, and changes neither (ARC-3, MP-2).

const DEFAULT_FILE: String = "res://data/audio/shaft_sounds.json"
const POINT: String = "point"
const SELECT: String = "select"
const REFUSED: String = "refused"
const LAUNCH: String = "launch"
const NEEDED: Array[String] = [POINT, SELECT, REFUSED, LAUNCH]

var voices: int = 3
## Sound name to {"sound": res:// path, "volume_db": float, "min_gap_s": float}.
var sounds: Dictionary[String, Dictionary] = {}
## Why the file was rejected, naming the field; empty when it was read.
var error: String = ""


static func load_file(path: String = DEFAULT_FILE) -> ShaftSoundTable:
	if not FileAccess.file_exists(path):
		var missing: ShaftSoundTable = ShaftSoundTable.new()
		missing.error = "%s: no such file" % path
		return missing
	return parse(FileAccess.get_file_as_string(path))


## The table in `text`; on a rejected file it has no sounds and `error` says why.
static func parse(text: String) -> ShaftSoundTable:
	var table: ShaftSoundTable = ShaftSoundTable.new()
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		return table._reject("not a JSON object")
	var root: Dictionary = data
	if not _number(root.get("voices")) or float(root["voices"]) < 1.0 \
			or float(root["voices"]) != floorf(float(root["voices"])):
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
	return table


## The sounds for one frame of the open panel, in the order they play:
## `before` and `after` are the highlighted entry around the frame (the stick
## and the aim both move it), `chosen` the kind a confirm answered ("" for none)
## and `taken` whether the run took it. A taken choice is a select and then the
## launch into the next level; a confirm the run refuses is a refusal.
static func events(before: int, after: int, chosen: String, taken: bool) -> Array[String]:
	var heard: Array[String] = []
	if chosen != "":
		heard.append_array([SELECT, LAUNCH] if taken else [REFUSED])
	elif before != after:
		heard.append(POINT)
	return heard


## Whether `name`, last played at `last` seconds (-INF for never), may play
## again at `now`.
func due(name: String, last: float, now: float) -> bool:
	return sounds.has(name) and now - last >= float(sounds[name]["min_gap_s"])


static func _number(value: Variant) -> bool:
	return value is float or value is int


func _reject(why: String) -> ShaftSoundTable:
	error = why
	sounds = {}
	return self
