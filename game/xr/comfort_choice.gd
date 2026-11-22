class_name ComfortChoice
extends RefCounted

## The player's comfort preset and whether the first-launch flight test has
## been done or skipped (CMF-4), kept between starts.
##
## It lives in `xr/` because comfort settings live only there (ARC-3). The file
## holds the preset number (or `"custom"` with the custom file's base preset,
## #806) and the test flag and nothing else, so nothing in it can change speed,
## damage or timers (CMF-6). The custom mode's settings stay in its own file.

const DEFAULT_PATH: String = "user://meltdown_comfort.json"
const FIELD_PRESET: String = "preset"
const FIELD_TEST_DONE: String = "flight_test_done"
## Written only with the custom mode: the preset to use if its file is gone.
const FIELD_CUSTOM_BASE: String = "custom_base"
## The preset field's value for the custom mode.
const CUSTOM: String = "custom"
## Every field the file may hold; anything else is rejected rather than kept,
## so the file cannot grow simulation settings by accident (CMF-6).
const FIELDS: Array[String] = [FIELD_PRESET, FIELD_TEST_DONE, FIELD_CUSTOM_BASE]
const MIN_PRESET: int = 1
const MAX_PRESET: int = 4
const LOG_PREFIX: String = "Meltdown: comfort choice"

var _preset: int = ComfortPresetFiles.START_NUMBER
var _test_done: bool = false
## The custom file's base preset while the custom mode is chosen, else 0.
var _custom_base: int = 0
## Why the last `load_from` fell back to first launch; empty when the file was
## read, or simply missing.
var _load_error: String = ""


## True until the flight test has been done or skipped and saved.
func first_launch() -> bool:
	return not _test_done


## The chosen preset, 1..4, or `ComfortPresetFiles.CUSTOM_NUMBER`.
func preset() -> int:
	return _preset


## The preset to use when the custom mode is chosen but its file is gone.
func custom_base() -> int:
	return _custom_base


## The last load's reason for treating the file as missing, naming the field;
## empty when nothing was wrong.
func load_error() -> String:
	return _load_error


## Sets the preset (a menu choice, or the test's recommendation). A number outside
## 1..4 is refused and the current preset kept; returns whether it was taken.
func set_preset(number: int) -> bool:
	if number < MIN_PRESET or number > MAX_PRESET:
		push_warning("%s: preset %d refused, expected %d..%d" % [LOG_PREFIX, number, MIN_PRESET, MAX_PRESET])
		return false
	_preset = number
	_custom_base = 0
	return true


## Chooses the custom mode, remembering `base` (1..4), the custom file's base
## preset, for a start where the file is gone. Returns whether it was taken.
func set_custom(base: int) -> bool:
	if base < MIN_PRESET or base > MAX_PRESET:
		push_warning("%s: custom base %d refused, expected %d..%d" % [LOG_PREFIX, base, MIN_PRESET, MAX_PRESET])
		return false
	_preset = ComfortPresetFiles.CUSTOM_NUMBER
	_custom_base = base
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
	_custom_base = 0
	_load_error = ""
	if not FileAccess.file_exists(path):
		return
	var error: String = _read(path)
	if not error.is_empty():
		_preset = ComfortPresetFiles.START_NUMBER
		_test_done = false
		_custom_base = 0
		_load_error = error
		push_warning("%s %s ignored: %s" % [LOG_PREFIX, path, error])


## Writes the choice to `path`; returns false (and reports why) on failure.
func save_to(path: String = DEFAULT_PATH) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("%s could not save %s (%s)" % [LOG_PREFIX, path, error_string(FileAccess.get_open_error())])
		return false
	var data: Dictionary = {FIELD_PRESET: _preset, FIELD_TEST_DONE: _test_done}
	if _preset == ComfortPresetFiles.CUSTOM_NUMBER:
		data = {FIELD_PRESET: CUSTOM, FIELD_CUSTOM_BASE: _custom_base, FIELD_TEST_DONE: _test_done}
	file.store_string(JSON.stringify(data, "\t"))
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


## The preset is a number or `"custom"`; the custom mode also needs its base.
func _read_preset(data: Dictionary) -> String:
	if not data.has(FIELD_PRESET):
		return "field \"%s\" missing" % FIELD_PRESET
	var value: Variant = data[FIELD_PRESET]
	if typeof(value) == TYPE_STRING and value == CUSTOM:
		if not data.has(FIELD_CUSTOM_BASE):
			return "field \"%s\" missing" % FIELD_CUSTOM_BASE
		var base_error: String = _whole_in_range(FIELD_CUSTOM_BASE, data[FIELD_CUSTOM_BASE])
		if not base_error.is_empty():
			return base_error
		_preset = ComfortPresetFiles.CUSTOM_NUMBER
		_custom_base = int(data[FIELD_CUSTOM_BASE])
		return ""
	var preset_error: String = _whole_in_range(FIELD_PRESET, value)
	if not preset_error.is_empty():
		return preset_error
	if data.has(FIELD_CUSTOM_BASE):
		return "field \"%s\" given without the custom mode" % FIELD_CUSTOM_BASE
	_preset = int(value)
	return ""


## JSON gives every number as a float, so a whole float is accepted as a
## preset number and anything with a fraction is not.
static func _whole_in_range(field: String, value: Variant) -> String:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return "field \"%s\" is %s, expected a number" % [field, type_string(typeof(value))]
	var number: float = float(value)
	if number != floorf(number) or number < MIN_PRESET or number > MAX_PRESET:
		return "field \"%s\" is %s, expected %d..%d" % [field, str(value), MIN_PRESET, MAX_PRESET]
	return ""
