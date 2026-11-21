class_name BreakChoice
extends RefCounted

## Whether the take-a-break reminder is on (CMF-10, #820), kept between starts
## in its own small file the way `PanelCorner` keeps the corner and
## `ControlsChoice` the scheme. Without a file the break prompt's data file
## (`"enabled"` in `break_prompt.json`) decides.
##
## `--break-reminder=on|off` on the command line, or the intent extra
## `meltdown_break_reminder` on the headset, read the way `LevelSwitch` reads
## `--level` (an argument wins over the extra, the last one counts), sets it for
## this start and saves it, so it beats the saved choice. The dev menu (lane-b)
## will switch it through `BreakPromptWiring.set_enabled`. A bad file or value
## is ignored with a warning naming it.
##
## View only: the file holds `{"enabled": bool}` and nothing else, and the
## reminder it switches never pauses or changes the simulation (CMF-6, ARC-3).

const DEFAULT_PATH: String = "user://meltdown_break.json"
const FIELD_ENABLED: String = "enabled"
const ARG_PREFIX: String = "--break-reminder="
const INTENT_EXTRA: String = "meltdown_break_reminder"
const ON: String = "on"
const OFF: String = "off"
const LOG_PREFIX: String = "Meltdown: break reminder"

## Every warning pushed, so tests can read them.
var warnings: PackedStringArray = PackedStringArray()

var _path: String


func _init(path: String = DEFAULT_PATH) -> void:
	_path = path


## The value asked for by `user_args`, else by the intent extra, or "".
static func requested(user_args: PackedStringArray, intent_value: String) -> String:
	var asked: String = ""
	for arg: String in user_args:
		if arg.begins_with(ARG_PREFIX):
			asked = arg.substr(ARG_PREFIX.length()).strip_edges()
	return asked if asked != "" else intent_value.strip_edges()


## Whether the reminder is on for this start: the launch switch in `user_args`
## or `intent_value` (saved when good), else the saved choice, else
## `default_enabled`, the data file's value.
func for_launch(default_enabled: bool, user_args: PackedStringArray, intent_value: String) -> bool:
	var enabled: bool = load_saved(default_enabled)
	var asked: String = requested(user_args, intent_value)
	if asked == ON or asked == OFF:
		enabled = asked == ON
		save(enabled)
		print("%s %s, from the launch switch" % [LOG_PREFIX, asked])
	elif asked != "":
		_warn("switch \"%s\" ignored, expected %s or %s" % [asked, ON, OFF])
	return enabled


## The saved choice, or `default_enabled` when there is no file. An unreadable
## or wrong file gives `default_enabled` with a warning, so it never stops the game.
func load_saved(default_enabled: bool) -> bool:
	if not FileAccess.file_exists(_path):
		return default_enabled
	var json: JSON = JSON.new()
	var parsed: bool = json.parse(FileAccess.get_file_as_string(_path)) == OK
	var saved: Variant = json.data if parsed else null
	var keys_ok: bool = saved is Dictionary and (saved as Dictionary).keys() == [FIELD_ENABLED]
	if keys_ok and typeof((saved as Dictionary)[FIELD_ENABLED]) == TYPE_BOOL:
		return bool((saved as Dictionary)[FIELD_ENABLED])
	_warn("%s ignored: expected {\"%s\": true or false}" % [_path, FIELD_ENABLED])
	return default_enabled


## Saves `enabled`; returns whether it was written.
func save(enabled: bool) -> bool:
	var file: FileAccess = FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		_warn("could not save %s (%s)" % [_path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify({FIELD_ENABLED: enabled}))
	file.close()
	return true


func _warn(text: String) -> void:
	var line: String = "%s %s" % [LOG_PREFIX, text]
	warnings.append(line)
	push_warning(line)
