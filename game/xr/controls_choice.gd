class_name ControlsChoice
extends RefCounted

## The control choices made in the dev menu (PLT-5), kept between starts in
## one small file the way `PanelCorner` keeps the corner, so the owner picks
## them once in the headset instead of passing switches from adb every
## launch (#748): the scheme (#778), and the hand and pitch settings (#790).
##
## The file holds `{"scheme": <name>, "left_handed": <bool>, "invert_pitch":
## <bool>}`; each field is optional, and saving one keeps the others. A launch
## argument or intent extra still wins over the saved scheme
## (`ControlSchemeSwitch.from_launch`), so a test run can force a scheme
## without touching what the owner saved. No launch switch exists for the
## hands or pitch, so the file alone sets them; with no file the game flies
## right-handed with normal pitch.
## Input side only: nothing here reaches the simulation (ARC-3, MP-2).

const DEFAULT_PATH: String = "user://meltdown_controls.json"
const FIELD_SCHEME: String = "scheme"
const FIELD_LEFT_HANDED: String = "left_handed"
const FIELD_INVERT_PITCH: String = "invert_pitch"
const FIELDS: Array[String] = [FIELD_SCHEME, FIELD_LEFT_HANDED, FIELD_INVERT_PITCH]
const LOG_PREFIX: String = "Meltdown: controls choice"

## Every warning pushed, so tests can read them.
var warnings: PackedStringArray = PackedStringArray()

var _path: String


func _init(path: String = DEFAULT_PATH) -> void:
	_path = path


## The saved scheme, or "" when there is none. An unreadable or wrong file
## gives "" with a warning, so it never stops the game.
func load_saved() -> String:
	return str(_read().get(FIELD_SCHEME, ""))


## Sets `mapping`'s hand and pitch settings from the file (both off without
## one) and returns it, so the game's one mapping is built in one place.
func apply_hands(mapping: ThumbstickMapping) -> ThumbstickMapping:
	var saved: Dictionary = _read()
	mapping.left_handed = bool(saved.get(FIELD_LEFT_HANDED, false))
	mapping.invert_pitch = bool(saved.get(FIELD_INVERT_PITCH, false))
	return mapping


## Saves `scheme`, keeping the saved hand settings; an unknown name is
## refused with a warning. Returns whether it was saved.
func save(scheme: String) -> bool:
	if not ControlSchemeSwitch.SCHEMES.has(scheme):
		_warn("scheme \"%s\" not saved" % scheme)
		return false
	return _merge({FIELD_SCHEME: scheme})


## Saves the hand and pitch settings, keeping the saved scheme.
func save_hands(left_handed: bool, invert_pitch: bool) -> bool:
	return _merge({FIELD_LEFT_HANDED: left_handed, FIELD_INVERT_PITCH: invert_pitch})


## The file's fields, or {} with one warning when it is unreadable or wrong.
func _read() -> Dictionary:
	if not FileAccess.file_exists(_path):
		return {}
	var json: JSON = JSON.new()
	var parsed: bool = json.parse(FileAccess.get_file_as_string(_path)) == OK
	var saved: Variant = json.data if parsed else null
	if saved is Dictionary and _valid(saved):
		return saved
	_warn("%s ignored: expected {\"%s\": %s, \"%s\": true or false, \"%s\": true or false}" % [
		_path, FIELD_SCHEME, " or ".join(ControlSchemeSwitch.SCHEMES), FIELD_LEFT_HANDED,
		FIELD_INVERT_PITCH])
	return {}


static func _valid(saved: Dictionary) -> bool:
	if saved.is_empty():
		return false
	for key: Variant in saved:
		if not FIELDS.has(str(key)):
			return false
	if saved.has(FIELD_SCHEME) and not ControlSchemeSwitch.SCHEMES.has(str(saved[FIELD_SCHEME])):
		return false
	for field: String in [FIELD_LEFT_HANDED, FIELD_INVERT_PITCH]:
		if saved.has(field) and typeof(saved[field]) != TYPE_BOOL:
			return false
	return true


func _merge(fields: Dictionary) -> bool:
	var saved: Dictionary = _read()
	saved.merge(fields, true)
	var file: FileAccess = FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		_warn("could not save %s (%s)" % [_path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(saved))
	file.close()
	return true


func _warn(text: String) -> void:
	var line: String = "%s %s" % [LOG_PREFIX, text]
	warnings.append(line)
	push_warning(line)
