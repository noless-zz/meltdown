class_name RefreshChoice
extends RefCounted

## The pilot's 120 Hz option (#838, PRF-1, CMF-1): only preset 4 allows
## 120 Hz (`allow_120_hz`), but it asks for 90 like the others, so the faster
## rate is a choice the pilot makes, kept like the other settings.
##
## `--refresh=120` or `--refresh=90` on the command line, or the intent extra
## `meltdown_refresh` on the headset, is read the way `ControlSchemeSwitch`
## reads `--controls=`: an argument wins over the extra, the last argument
## given counts, and a switch beats the saved choice. Without a switch the
## choice saved in `user://meltdown_refresh.json` (`{"120_hz": true}`)
## counts; with neither the option is off. A bad value or file is warned by
## value or path and treated as off, so a typo never raises the rate.
## Display side only: the simulation keeps its 60 Hz tick (ARC-3, CMF-6).

const DEFAULT_PATH: String = "user://meltdown_refresh.json"
const FIELD_120_HZ: String = "120_hz"
const ARG_PREFIX: String = "--refresh="
const INTENT_EXTRA: String = "meltdown_refresh"
const ON: String = "120"
const OFF: String = "90"
const HIGH_HZ: float = 120.0
const LOG_PREFIX: String = "Meltdown: refresh choice"
const SOURCE_SWITCH: String = "switch"
const SOURCE_SAVED: String = "saved"
const SOURCE_DEFAULT: String = "default"

## Whether the pilot asked for 120 Hz where the preset allows it.
var on: bool = false
## Whether an argument or intent extra was given; it then beats the saved choice.
var from_switch: bool = false
## Where `on` came from: SOURCE_SWITCH, SOURCE_SAVED or SOURCE_DEFAULT.
var source: String = SOURCE_DEFAULT
## Every warning pushed, so tests can read them.
var warnings: PackedStringArray = PackedStringArray()


## The choice this launch made: user arguments and, on Android, the intent
## extra; without either, the one saved at `saved_path`.
static func from_launch(saved_path: String = DEFAULT_PATH) -> RefreshChoice:
	var chosen: RefreshChoice = parse(OS.get_cmdline_user_args(),
		FoveationSwitch.intent_value(INTENT_EXTRA))
	chosen.use_saved(saved_path)
	return chosen


## The choice in `user_args`, falling back to the intent extra's value.
static func parse(user_args: PackedStringArray, intent: String) -> RefreshChoice:
	var chosen: RefreshChoice = RefreshChoice.new()
	var asked: String = ""
	for arg: String in user_args:
		if arg.begins_with(ARG_PREFIX):
			asked = arg.substr(ARG_PREFIX.length()).strip_edges()
	if asked == "":
		asked = intent.strip_edges()
	if asked == "":
		return chosen
	chosen.from_switch = true
	chosen.source = SOURCE_SWITCH
	chosen.on = asked == ON
	if asked != ON and asked != OFF:
		chosen._warn("refresh \"%s\" is not %s or %s; 120 Hz off" % [asked, ON, OFF])
	return chosen


## Takes the choice saved at `path` unless a switch was given.
func use_saved(path: String = DEFAULT_PATH) -> void:
	if from_switch or not FileAccess.file_exists(path):
		return
	var json: JSON = JSON.new()
	var parsed: bool = json.parse(FileAccess.get_file_as_string(path)) == OK
	var saved: Variant = json.data if parsed else null
	if saved is Dictionary and (saved as Dictionary).size() == 1 \
			and typeof((saved as Dictionary).get(FIELD_120_HZ)) == TYPE_BOOL:
		on = bool(saved[FIELD_120_HZ])
		source = SOURCE_SAVED
		return
	_warn("%s ignored: expected {\"%s\": true or false}; 120 Hz off" % [path, FIELD_120_HZ])


## Saves `p_on` at `path` for later launches; returns whether it was saved.
## For the dev menu entry that follows in lane-b.
func save(p_on: bool, path: String = DEFAULT_PATH) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_warn("could not save %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify({FIELD_120_HZ: p_on}))
	file.close()
	return true


## The rate `preset` asks for under this choice: 120 Hz when the option is
## on and the preset allows it, otherwise the preset's own rate.
func wanted_hz(preset: ComfortPreset) -> float:
	if on and preset.allow_120_hz:
		return HIGH_HZ
	return RefreshRate.target_hz(preset)


func describe() -> String:
	return "%s 120 Hz %s (%s)" % [LOG_PREFIX, "on" if on else "off", source]


func _warn(text: String) -> void:
	var line: String = "%s %s" % [LOG_PREFIX, text]
	warnings.append(line)
	push_warning(line)
