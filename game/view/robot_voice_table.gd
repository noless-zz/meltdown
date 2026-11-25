class_name RobotVoiceTable
extends RefCounted

## The robot voice table (#1363, AUD-2, ARC-4), read from
## `res://data/audio/robot_voices.json`:
##
##     {
##       "max_voices": 6,            # most robot voices sounding at once, nearest first
##       "reference_m": 3.0,         # full volume this close; quieter by distance beyond
##       "far_cutoff_hz": 2500.0,    # the distance low-pass: duller far away, brighter near
##       "muffle_cutoff_hz": 700.0,  # the low-pass of a voice heard through a wall
##       "voices": {"drone": {"sound": "res://...", "volume_db": -10.0,
##                            "pitch_min": 0.9, "pitch_max": 1.2,
##                            "range_m": 30.0, "muffle_db": -12.0}, ...}
##     }
##
## Rows are keyed by robot type id. A type with no row is silent; the unit
## tests check every shipped robot type has one.

const DEFAULT_FILE: String = "res://data/audio/robot_voices.json"
const ROW_NUMBERS: Array[String] = ["volume_db", "pitch_min", "pitch_max", "range_m", "muffle_db"]

var max_voices: int = 6
var reference_m: float = 3.0
var far_cutoff_hz: float = 2500.0
var muffle_cutoff_hz: float = 700.0
## By robot type id.
var voices: Dictionary[String, RobotVoiceRow] = {}
## Why the file was rejected, naming the field; empty when it was read.
var error: String = ""


## The table at `path`; on a missing or rejected file it has no voices and `error` says why.
static func load_file(path: String = DEFAULT_FILE) -> RobotVoiceTable:
	if not FileAccess.file_exists(path):
		return RobotVoiceTable.new()._reject("%s: no such file" % path)
	return parse(FileAccess.get_file_as_string(path))


## The table in `text`; see the class comment for the format.
static func parse(text: String) -> RobotVoiceTable:
	var table: RobotVoiceTable = RobotVoiceTable.new()
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		return table._reject("not a JSON object")
	var root: Dictionary = data
	if not _is_number(root.get("max_voices")) or int(root["max_voices"]) < 1:
		return table._reject("max_voices must be a whole number of at least 1")
	table.max_voices = int(root["max_voices"])
	for key: String in ["reference_m", "far_cutoff_hz", "muffle_cutoff_hz"]:
		if not _is_number(root.get(key)) or float(root[key]) <= 0.0:
			return table._reject("%s must be a number above 0" % key)
	table.reference_m = float(root["reference_m"])
	table.far_cutoff_hz = float(root["far_cutoff_hz"])
	table.muffle_cutoff_hz = float(root["muffle_cutoff_hz"])
	if not root.get("voices") is Dictionary:
		return table._reject("voices must be an object")
	var rows: Dictionary = root["voices"]
	for id: Variant in rows:
		var why: String = _row_error(rows[id])
		if why != "":
			return table._reject("voices.%s: %s" % [id, why])
		table.voices[str(id)] = _row(str(id), rows[id])
	return table


## The voice of robot type `id`, or null when it has none.
func voice(id: String) -> RobotVoiceRow:
	return voices.get(id, null)


static func _row_error(row: Variant) -> String:
	if not row is Dictionary:
		return "must be an object"
	var fields: Dictionary = row
	if not fields.get("sound") is String or not (fields["sound"] as String).begins_with("res://"):
		return "sound must be a res:// path"
	for key: String in ROW_NUMBERS:
		if not _is_number(fields.get(key)):
			return "%s must be a number" % key
	if float(fields["pitch_min"]) <= 0.0 or float(fields["pitch_min"]) > float(fields["pitch_max"]):
		return "needs 0 < pitch_min <= pitch_max"
	if float(fields["range_m"]) <= 0.0:
		return "range_m must be above 0"
	if float(fields["muffle_db"]) > 0.0:
		return "muffle_db must be 0 or below"
	return ""


static func _row(id: String, fields: Dictionary) -> RobotVoiceRow:
	var row: RobotVoiceRow = RobotVoiceRow.new()
	row.id = id
	row.sound = fields["sound"]
	row.volume_db = float(fields["volume_db"])
	row.pitch_min = float(fields["pitch_min"])
	row.pitch_max = float(fields["pitch_max"])
	row.range_m = float(fields["range_m"])
	row.muffle_db = float(fields["muffle_db"])
	return row


static func _is_number(value: Variant) -> bool:
	return value is float or value is int


func _reject(why: String) -> RobotVoiceTable:
	error = why
	voices = {}
	return self
