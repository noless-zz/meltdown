class_name SoundCueTable
extends RefCounted

## The sound cue table (#1290, AUD-1, ARC-4), read from `res://data/audio/cues.json`:
##
##     {
##       "max_voices": 16,        # most cues sounding at once
##       "quiet_db": -6.0,        # a cue at or below this volume is "quiet"
##       "cues": {"ROBOT_HIT": {"sound": "res://...", "volume_db": -3.0,
##                              "pitch_min": 0.9, "pitch_max": 1.1,
##                              "min_magnitude": 0.0}, ...},   # optional
##       "silent": ["AFTERBURNER_STARTED", ...]
##     }
##
## A cue is named after the `SimEvent.Kind` it sounds for, or is one the view
## derives from the bolts: `SHOT_FIRED:<weapon id>` (`SHOT_FIRED:robot` for a
## robot's shot, plain `SHOT_FIRED` for a weapon with no row of its own, so a
## new weapon file still sounds) and `BOLT_IMPACT`. Every kind the core emits
## is in `cues` or in `silent`, so a new kind cannot go quietly unheard.

const DEFAULT_FILE: String = "res://data/audio/cues.json"
const SHOT_FIRED: String = "SHOT_FIRED"
const BOLT_IMPACT: String = "BOLT_IMPACT"
const ROBOT_WEAPON: String = "robot"

var max_voices: int = 16
var quiet_db: float = -6.0
## By cue name.
var cues: Dictionary[String, SoundCue] = {}
## `SimEvent.Kind` names that play nothing.
var silent: Array[String] = []
## Why the file was rejected, naming the field; empty when it was read.
var error: String = ""


## The table at `path`; on a missing or rejected file it has no cues and `error` says why.
static func load_file(path: String = DEFAULT_FILE) -> SoundCueTable:
	if not FileAccess.file_exists(path):
		var missing: SoundCueTable = SoundCueTable.new()
		missing.error = "%s: no such file" % path
		return missing
	return parse(FileAccess.get_file_as_string(path))


## The table in `text`; see the class comment for the format.
static func parse(text: String) -> SoundCueTable:
	var table: SoundCueTable = SoundCueTable.new()
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		return table._reject("not a JSON object")
	var root: Dictionary = data
	if not (root.get("max_voices") is float or root.get("max_voices") is int) or int(root["max_voices"]) < 1:
		return table._reject("max_voices must be a whole number of at least 1")
	table.max_voices = int(root["max_voices"])
	if not (root.get("quiet_db", 0.0) is float or root.get("quiet_db") is int):
		return table._reject("quiet_db must be a number")
	table.quiet_db = float(root.get("quiet_db", table.quiet_db))
	if not root.get("cues") is Dictionary:
		return table._reject("cues must be an object")
	var rows: Dictionary = root["cues"]
	for name: Variant in rows:
		var cue: SoundCue = _cue(str(name), rows[name])
		if cue == null:
			return table._reject("cues.%s needs a res:// sound, a volume_db, 0 < pitch_min <= pitch_max and min_magnitude >= 0" % name)
		table.cues[cue.id] = cue
	if not root.get("silent", []) is Array:
		return table._reject("silent must be a list of event kinds")
	for name: Variant in root.get("silent", []):
		if not SimEvent.Kind.has(str(name)):
			return table._reject("silent lists %s, which is no event kind" % name)
		if table.cues.has(str(name)):
			return table._reject("%s is both a cue and silent" % name)
		table.silent.append(str(name))
	return table


## The cue named `id`, or null. A `SHOT_FIRED:<weapon>` with no row of its own
## falls back to plain `SHOT_FIRED`.
func cue(id: String) -> SoundCue:
	if cues.has(id):
		return cues[id]
	if id.begins_with(SHOT_FIRED + ":"):
		return cues.get(SHOT_FIRED, null)
	return null


## Whether `hit` sounds: its cue has a row and the event is big enough for it.
func plays(hit: SoundCueHit) -> bool:
	var row: SoundCue = cue(hit.cue)
	return row != null and row.sounds_at(hit.magnitude)


## The cue name for an event `kind`: its enum name.
static func kind_cue(kind: SimEvent.Kind) -> String:
	return SimEvent.Kind.keys()[kind]


## The cue name for a shot from weapon `weapon_id`.
static func shot_cue(weapon_id: String) -> String:
	return "%s:%s" % [SHOT_FIRED, weapon_id]


## Event kind names that have neither a cue nor a place in `silent`.
func unheard_kinds() -> Array[String]:
	var missing: Array[String] = []
	for name: String in SimEvent.Kind.keys():
		if not cues.has(name) and not silent.has(name):
			missing.append(name)
	return missing


static func _cue(id: String, row: Variant) -> SoundCue:
	if not row is Dictionary:
		return null
	var fields: Dictionary = row
	var sound: Variant = fields.get("sound")
	if not sound is String or not (sound as String).begins_with("res://"):
		return null
	for key: String in ["volume_db", "pitch_min", "pitch_max"]:
		if not (fields.get(key) is float or fields.get(key) is int):
			return null
	var cue: SoundCue = SoundCue.new()
	cue.id = id
	cue.sound = sound
	cue.volume_db = float(fields["volume_db"])
	cue.pitch_min = float(fields["pitch_min"])
	cue.pitch_max = float(fields["pitch_max"])
	var least: Variant = fields.get("min_magnitude", 0.0)
	if not (least is float or least is int) or float(least) < 0.0:
		return null
	cue.min_magnitude = float(least)
	if cue.pitch_min <= 0.0 or cue.pitch_min > cue.pitch_max:
		return null
	return cue


func _reject(why: String) -> SoundCueTable:
	error = why
	cues = {}
	silent = []
	return self
