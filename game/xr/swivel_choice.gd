class_name SwivelChoice
extends RefCounted

## The pilot's swivel-chair choice from the dev menu (#853, CMF-7, CMF-1):
## one on/off for every preset, kept in `user://meltdown_swivel.json`
## (`{"enabled": bool}`) the way `BreakChoice` keeps the break reminder.
## Without a file it is off, as on every shipped preset; a bad file is warned
## by path and treated as off, so a typo never starts the ship turning.
##
## `applied` sets only `swivel_enabled` on presets 1 to 4; the other swivel
## rows stay the preset's. In the custom mode the custom file's own value wins,
## so the menu never contradicts a file the owner pushed (#837). View and input
## side only: the swivel still only produces yaw input (CMF-6, ARC-3, MP-2).

const DEFAULT_PATH: String = "user://meltdown_swivel.json"
const FIELD_ENABLED: String = "enabled"
const LOG_PREFIX: String = "Meltdown: swivel choice"
## `ComfortWiring.swivel_choice` before the menu or the saved file has spoken.
const UNSET: int = -1
const OFF: int = 0
const ON: int = 1

## Every warning pushed, so tests can read them.
var warnings: PackedStringArray = PackedStringArray()

var _path: String


func _init(path: String = DEFAULT_PATH) -> void:
	_path = path


## The saved choice; off without a file, and off with a warning naming the
## path for a file that is not exactly `{"enabled": true or false}`.
func load_saved() -> bool:
	if not FileAccess.file_exists(_path):
		return false
	var json: JSON = JSON.new()
	var parsed: bool = json.parse(FileAccess.get_file_as_string(_path)) == OK
	var saved: Variant = json.data if parsed else null
	var keys_ok: bool = saved is Dictionary and (saved as Dictionary).keys() == [FIELD_ENABLED]
	if keys_ok and typeof((saved as Dictionary)[FIELD_ENABLED]) == TYPE_BOOL:
		return bool((saved as Dictionary)[FIELD_ENABLED])
	_warn("%s ignored: expected {\"%s\": true or false}; swivel off" % [_path, FIELD_ENABLED])
	return false


## Saves `enabled`; returns whether it was written.
func save(enabled: bool) -> bool:
	var file: FileAccess = FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		_warn("could not save %s (%s)" % [_path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify({FIELD_ENABLED: enabled}))
	file.close()
	return true


## `preset` numbered `number` under `choice` (UNSET, OFF or ON): the same
## preset when the choice is unset, already matches, or `number` is the custom
## mode; otherwise a copy with only `swivel_enabled` changed. A copy, because
## the preset files are shared cached resources.
static func applied(preset: ComfortPreset, number: int, choice: int) -> ComfortPreset:
	if preset == null or choice == UNSET or number == ComfortPresetFiles.CUSTOM_NUMBER:
		return preset
	if preset.swivel_enabled == (choice == ON):
		return preset
	var copy: ComfortPreset = preset.duplicate() as ComfortPreset
	copy.swivel_enabled = choice == ON
	return copy


func _warn(text: String) -> void:
	var line: String = "%s %s" % [LOG_PREFIX, text]
	warnings.append(line)
	push_warning(line)
