class_name ComfortChoice
extends RefCounted

## The player's comfort preset and whether the first-launch flight test has
## been done or skipped (CMF-4), kept between starts.
##
## It lives in `xr/` because comfort settings live only there (ARC-3). The file
## holds the preset number and the test flag and nothing else, so nothing in it
## can change speed, damage or timers (CMF-6).

const DEFAULT_PATH: String = "user://meltdown_comfort.json"
const FIELD_PRESET: String = "preset"
const FIELD_TEST_DONE: String = "flight_test_done"
## Every field the file may hold; anything else is rejected rather than kept,
## so the file cannot grow simulation settings by accident (CMF-6).
const FIELDS: Array[String] = [FIELD_PRESET, FIELD_TEST_DONE]
const MIN_PRESET: int = 1
const MAX_PRESET: int = 4
const LOG_PREFIX: String = "Meltdown: comfort choice"

var _preset: int = ComfortPresetFiles.START_NUMBER
var _test_done: bool = false
## Why the last `load_from` fell back to first launch; empty when the file was
## read, or simply missing.
var _load_error: String = ""


## True until the flight test has been done or skipped and saved.
func first_launch() -> bool:
	return not _test_done


## The chosen preset, 1..4.
func preset() -> int:
	return _preset


## The last load's reason for treating the file as missing, naming the field;
## empty when nothing was wrong.
func load_error() -> String:
	return _load_error


## Sets the preset (an X press, or the test's recommendation). A number outside
## 1..4 is refused and the current preset kept; returns whether it was taken.
func set_preset(number: int) -> bool:
	if number < MIN_PRESET or number > MAX_PRESET:
		push_warning("%s: preset %d refused, expected %d..%d" % [LOG_PREFIX, number, MIN_PRESET, MAX_PRESET])
		return false
	_preset = number
	return true


## The flight test finished with `number` recommended, or was skipped (the
## caller passes the skip preset). Later starts are no longer first launches.
func finish_test(number: int) -> bool:
	if not set_preset(number):
		return false
	_test_done = true
	return true


## Reads `path`. A missing file is a first launch; an unreadable file or a bad
## value is reported with the field named and also treated as a first launch,
## so a broken file never stops the game from starting.
func load_from(path: String = DEFAULT_PATH) -> void:
	_preset = ComfortPresetFiles.START_NUMBER
	_test_done = false
	_load_error = ""
	if not FileAccess.file_exists(path):
		return
	var error: String = _read(path)
	if not error.is_empty():
		_preset = ComfortPresetFiles.START_NUMBER
		_test_done = false
		_load_error = error
		push_warning("%s %s ignored: %s" % [LOG_PREFIX, path, error])


## Writes the choice to `path`; returns false (and reports why) on failure.
func save_to(path: String = DEFAULT_PATH) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("%s could not save %s (%s)" % [LOG_PREFIX, path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify({FIELD_PRESET: _preset, FIELD_TEST_DONE: _test_done}, "\t"))
	file.close()
	return true


## Fills the fields from `path`; returns an error naming the field, or "".
func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty() and FileAccess.get_open_error() != OK:
		return "file could not be read (%s)" % error_string(FileAccess.get_open_error())
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return "not JSON (line %d: %s)" % [json.get_error_line(), json.get_error_message()]
	if typeof(json.data) != TYPE_DICTIONARY:
		return "not a JSON object"
	var data: Dictionary = json.data
	for key: Variant in data.keys():
		if not FIELDS.has(str(key)):
			return "unknown field \"%s\"" % str(key)
	var preset_error: String = _read_preset(data)
	if not preset_error.is_empty():
		return preset_error
	if not data.has(FIELD_TEST_DONE):
		return "field \"%s\" missing" % FIELD_TEST_DONE
	if typeof(data[FIELD_TEST_DONE]) != TYPE_BOOL:
		return "field \"%s\" is %s, expected true or false" % [FIELD_TEST_DONE, type_string(typeof(data[FIELD_TEST_DONE]))]
	_test_done = data[FIELD_TEST_DONE]
	return ""


## JSON gives every number as a float, so a whole float is accepted as the
## preset number and anything with a fraction is not.
func _read_preset(data: Dictionary) -> String:
	if not data.has(FIELD_PRESET):
		return "field \"%s\" missing" % FIELD_PRESET
	var value: Variant = data[FIELD_PRESET]
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return "field \"%s\" is %s, expected a number" % [FIELD_PRESET, type_string(typeof(value))]
	var number: float = float(value)
	if number != floorf(number) or number < MIN_PRESET or number > MAX_PRESET:
		return "field \"%s\" is %s, expected %d..%d" % [FIELD_PRESET, str(value), MIN_PRESET, MAX_PRESET]
	_preset = int(number)
	return ""
