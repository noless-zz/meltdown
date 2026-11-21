class_name ControlsChoice
extends RefCounted

## The control scheme chosen in the dev menu (#778, PLT-5), kept between
## starts in its own small file the way `PanelCorner` keeps the corner, so
## the owner picks thumbsticks or gripped once in the headset instead of
## passing `--controls=` from adb every launch (#748).
##
## The file holds `{"scheme": <name>}` and nothing else. A launch argument or
## intent extra still wins over it (`ControlSchemeSwitch.from_launch`), so a
## test run can force a scheme without touching what the owner saved.
## Input side only: nothing here reaches the simulation (ARC-3, MP-2).

const DEFAULT_PATH: String = "user://meltdown_controls.json"
const FIELD_SCHEME: String = "scheme"
const LOG_PREFIX: String = "Meltdown: controls choice"

## Every warning pushed, so tests can read them.
var warnings: PackedStringArray = PackedStringArray()

var _path: String


func _init(path: String = DEFAULT_PATH) -> void:
	_path = path


## The saved scheme, or "" when there is no file. An unreadable or wrong file
## gives "" with a warning, so it never stops the game.
func load_saved() -> String:
	if not FileAccess.file_exists(_path):
		return ""
	var json: JSON = JSON.new()
	var parsed: bool = json.parse(FileAccess.get_file_as_string(_path)) == OK
	var saved: Variant = json.data if parsed else null
	var keys_ok: bool = saved is Dictionary and (saved as Dictionary).keys() == [FIELD_SCHEME]
	if keys_ok and ControlSchemeSwitch.SCHEMES.has(str((saved as Dictionary)[FIELD_SCHEME])):
		return str((saved as Dictionary)[FIELD_SCHEME])
	_warn("%s ignored: expected {\"%s\": %s}" % [_path, FIELD_SCHEME,
		" or ".join(ControlSchemeSwitch.SCHEMES)])
	return ""


## Saves `scheme`; an unknown name is refused with a warning. Returns whether it was saved.
func save(scheme: String) -> bool:
	if not ControlSchemeSwitch.SCHEMES.has(scheme):
		_warn("scheme \"%s\" not saved" % scheme)
		return false
	var file: FileAccess = FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		_warn("could not save %s (%s)" % [_path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify({FIELD_SCHEME: scheme}))
	file.close()
	return true


func _warn(text: String) -> void:
	var line: String = "%s %s" % [LOG_PREFIX, text]
	warnings.append(line)
	push_warning(line)
