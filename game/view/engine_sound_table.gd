class_name EngineSoundTable
extends RefCounted

## The pilot's engine sound table (#1398, AUD-1, ARC-4), read from
## `res://data/audio/engine.json`:
##
##     {
##       "offset_m": [0.0, -0.5, 0.8],   # where it sounds, in the ship's space: below and behind the seat
##       "fade_seconds": 0.4,            # how long the engine takes to come in or go out
##       "smoothing_seconds": 0.15,      # how quickly the thrust layer follows the drive
##       "thrust_weight": 0.6,           # share of thrust in the drive; speed has the rest
##       "idle": {"sound": "res://...", "volume_db": -24.0, "pitch": 1.0},
##       "thrust": {"sound": "res://...", "volume_min_db": -36.0, "volume_max_db": -18.0,
##                  "pitch_min": 0.8, "pitch_max": 1.3},
##       "burst": {"sound": "res://...", "volume_db": -16.0}
##     }
##
## Every key is required; a rejected file names the field in `error`, and the
## engine then stays silent rather than play guessed levels.

const DEFAULT_FILE: String = "res://data/audio/engine.json"

var offset: Vector3 = Vector3(0.0, -0.5, 0.8)
var fade_seconds: float = 0.4
var smoothing_seconds: float = 0.15
var thrust_weight: float = 0.6
var idle_sound: String = ""
var idle_db: float = -24.0
var idle_pitch: float = 1.0
var thrust_sound: String = ""
var thrust_min_db: float = -36.0
var thrust_max_db: float = -18.0
var thrust_pitch_min: float = 0.8
var thrust_pitch_max: float = 1.3
var burst_sound: String = ""
var burst_db: float = -16.0
## Why the file was rejected, naming the field; empty when it was read.
var error: String = ""


## The table at `path`; on a missing or rejected file `error` says why.
static func load_file(path: String = DEFAULT_FILE) -> EngineSoundTable:
	if not FileAccess.file_exists(path):
		return EngineSoundTable.new()._reject("%s: no such file" % path)
	return parse(FileAccess.get_file_as_string(path))


## The table in `text`; see the class comment for the format.
static func parse(text: String) -> EngineSoundTable:
	var table: EngineSoundTable = EngineSoundTable.new()
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		return table._reject("not a JSON object")
	var root: Dictionary = data
	var offset_value: Variant = root.get("offset_m")
	if not offset_value is Array or (offset_value as Array).size() != 3:
		return table._reject("offset_m must be a list of three numbers")
	var listed: Array = offset_value
	for value: Variant in listed:
		if not _is_number(value):
			return table._reject("offset_m must be a list of three numbers")
	table.offset = Vector3(float(listed[0]), float(listed[1]), float(listed[2]))
	for key: String in ["fade_seconds", "smoothing_seconds"]:
		if not _is_number(root.get(key)) or float(root[key]) <= 0.0:
			return table._reject("%s must be a number above 0" % key)
	table.fade_seconds = float(root["fade_seconds"])
	table.smoothing_seconds = float(root["smoothing_seconds"])
	if not _is_number(root.get("thrust_weight")) or float(root["thrust_weight"]) < 0.0 \
			or float(root["thrust_weight"]) > 1.0:
		return table._reject("thrust_weight must be a number from 0 to 1")
	table.thrust_weight = float(root["thrust_weight"])
	var why: String = _section_error(root, "idle", ["volume_db", "pitch"])
	if why == "":
		why = _section_error(root, "thrust", ["volume_min_db", "volume_max_db", "pitch_min", "pitch_max"])
	if why == "":
		why = _section_error(root, "burst", ["volume_db"])
	if why != "":
		return table._reject(why)
	var idle: Dictionary = root["idle"]
	var thrust: Dictionary = root["thrust"]
	var burst: Dictionary = root["burst"]
	if float(idle["pitch"]) <= 0.0:
		return table._reject("idle.pitch must be above 0")
	if float(thrust["volume_min_db"]) > float(thrust["volume_max_db"]):
		return table._reject("thrust.volume_min_db must not be above thrust.volume_max_db")
	if float(thrust["pitch_min"]) <= 0.0 or float(thrust["pitch_min"]) > float(thrust["pitch_max"]):
		return table._reject("thrust needs 0 < pitch_min <= pitch_max")
	table.idle_sound = idle["sound"]
	table.idle_db = float(idle["volume_db"])
	table.idle_pitch = float(idle["pitch"])
	table.thrust_sound = thrust["sound"]
	table.thrust_min_db = float(thrust["volume_min_db"])
	table.thrust_max_db = float(thrust["volume_max_db"])
	table.thrust_pitch_min = float(thrust["pitch_min"])
	table.thrust_pitch_max = float(thrust["pitch_max"])
	table.burst_sound = burst["sound"]
	table.burst_db = float(burst["volume_db"])
	return table


## The loudest the engine gets, in dB: idle and a full thrust layer summed as
## power, or the burst if that is louder. The mix test holds it under the
## shot cues and robot voices.
func loudest_db() -> float:
	var steady: float = linear_to_db(db_to_linear(idle_db) + db_to_linear(thrust_max_db))
	return maxf(steady, burst_db)


## Why `root[name]` is not a section with a res:// `sound` and number `keys`, "" when it is.
static func _section_error(root: Dictionary, name: String, keys: Array[String]) -> String:
	if not root.get(name) is Dictionary:
		return "%s must be an object" % name
	var section: Dictionary = root[name]
	if not section.get("sound") is String or not (section["sound"] as String).begins_with("res://"):
		return "%s.sound must be a res:// path" % name
	for key: String in keys:
		if not _is_number(section.get(key)):
			return "%s.%s must be a number" % [name, key]
	return ""


static func _is_number(value: Variant) -> bool:
	return value is float or value is int


func _reject(why: String) -> EngineSoundTable:
	error = why
	return self
