class_name AutoLevelChoice
extends RefCounted

## The pilot's auto-level choice from the dev menu (#1247, CMF-1, CMF-5): one
## on/off for every preset whose roll the pilot flies, kept in
## `user://meltdown_auto_level.json` (`{"enabled": bool}`) the way
## `SwivelChoice` keeps the swivel. Without a file nothing is chosen, so every
## preset keeps its own file's value: off on presets 3 and 4. A bad file is
## warned by path and chooses nothing.
##
## Presets whose roll is "Off, auto-level" (1 and 2) always level; the choice
## leaves them alone. On any other preset, the custom mode included, `applied`
## sets `auto_level`, and on a fully manual roll (preset 4) it also lets the
## roll level, since `ComfortPreset.levels_roll` never levels a fully manual
## roll. The preset files are not changed: preset 4's file stays free of any
## intervention (CMF-2) and only the pilot's own choice adds one.
##
## Rates come from the preset (`auto_level_rate_deg_per_s`), so everyone who
## turns it on gets the same correction (CMF-6). The correction is an ordinary
## roll input the XR layer adds and the replay records; nothing in `core/`
## changes (ARC-3).

const DEFAULT_PATH: String = "user://meltdown_auto_level.json"
const FIELD_ENABLED: String = "enabled"
const LOG_PREFIX: String = "Meltdown: auto-level choice"
## `ComfortWiring.auto_level_choice` before the menu or the saved file has spoken.
const UNSET: int = -1
const OFF: int = 0
const ON: int = 1

## Every warning pushed, so tests can read them.
var warnings: PackedStringArray = PackedStringArray()

var _path: String


func _init(path: String = DEFAULT_PATH) -> void:
	_path = path


## The saved choice: UNSET without a file, and UNSET with a warning naming the
## path for a file that is not exactly `{"enabled": true or false}`.
func load_saved() -> int:
	if not FileAccess.file_exists(_path):
		return UNSET
	var json: JSON = JSON.new()
	var parsed: bool = json.parse(FileAccess.get_file_as_string(_path)) == OK
	var saved: Variant = json.data if parsed else null
	var keys_ok: bool = saved is Dictionary and (saved as Dictionary).keys() == [FIELD_ENABLED]
	if keys_ok and typeof((saved as Dictionary)[FIELD_ENABLED]) == TYPE_BOOL:
		return ON if bool((saved as Dictionary)[FIELD_ENABLED]) else OFF
	_warn("%s ignored: expected {\"%s\": true or false}; the preset decides" % [_path, FIELD_ENABLED])
	return UNSET


## Saves `enabled`; returns whether it was written.
func save(enabled: bool) -> bool:
	var file: FileAccess = FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		_warn("could not save %s (%s)" % [_path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify({FIELD_ENABLED: enabled}))
	file.close()
	return true


## True when `preset` always levels, whatever the choice: its roll is
## "Off, auto-level" (presets 1 and 2).
static func fixed_by(preset: ComfortPreset) -> bool:
	return preset != null and preset.roll_mode == ComfortPreset.RollMode.OFF_AUTO_LEVEL


## `preset` under `choice` (UNSET, OFF or ON): the same preset when the choice
## is unset, the preset always levels, or it already matches; otherwise a copy
## with `auto_level` set, and with a fully manual roll made manual when on. A
## copy, because the preset files are shared cached resources.
static func applied(preset: ComfortPreset, choice: int) -> ComfortPreset:
	if preset == null or choice == UNSET or fixed_by(preset):
		return preset
	var on: bool = choice == ON
	if preset.levels_roll() == on and preset.auto_level == on:
		return preset
	var copy: ComfortPreset = preset.duplicate() as ComfortPreset
	copy.auto_level = on
	if on and copy.roll_mode == ComfortPreset.RollMode.FULLY_MANUAL:
		copy.roll_mode = ComfortPreset.RollMode.MANUAL
	return copy


func _warn(text: String) -> void:
	var line: String = "%s %s" % [LOG_PREFIX, text]
	warnings.append(line)
	push_warning(line)
