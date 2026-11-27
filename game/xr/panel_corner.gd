class_name PanelCorner
extends RefCounted

## Which corner of the view the status panel sits in (#752, part 1 of #748),
## kept between starts in its own small file, the way `ComfortChoice` keeps
## the preset. `CENTRE` is the place the panel had before corners, below and
## ahead of the eye. `DEFAULT_CORNER`, bottom left, is the place without a saved
## choice: the owner's corner, which #1321 kept as the default and #1452 found
## a fresh install or a lost save did not give.
##
## `--panel=<corner>` on the command line, or the intent extra `meltdown_panel`
## on the headset, read the way `LevelSwitch` reads `--level` (an argument wins
## over the extra, the last one counts), chooses and saves a corner, so the
## owner can try corners from adb before the in-headset menu exists (#748).
## The menu will call `choose` too. An unknown name is ignored with one line.
##
## Presentation only: the file holds the corner and nothing else, and
## `current` is read by `StatusPanel.rig_transform` alone, so no choice here
## can reach the simulation (ARC-3, CMF-6).

const DEFAULT_PATH: String = "user://meltdown_panel.json"
const FIELD_CORNER: String = "corner"
const CENTRE: String = "centre"
const DEFAULT_CORNER: String = "bottom_left"
const ARG_PREFIX: String = "--panel="
const INTENT_EXTRA: String = "meltdown_panel"
const LOG_PREFIX: String = "Meltdown: status panel"

## The corner the panel is placed in now, for `StatusPanel.rig_transform`.
## Set by `load_saved` and `choose`.
static var current: String = DEFAULT_CORNER

## Every warning pushed, so tests can read them.
var warnings: PackedStringArray = PackedStringArray()

var _path: String
var _corner: String = DEFAULT_CORNER


func _init(path: String = DEFAULT_PATH) -> void:
	_path = path


## The corner of this launch: the saved one, then the switch if one was given.
static func from_launch(path: String = DEFAULT_PATH) -> PanelCorner:
	var store: PanelCorner = PanelCorner.new(path)
	store.load_saved()
	store.apply_switch(OS.get_cmdline_user_args(), FoveationSwitch.intent_value(INTENT_EXTRA))
	return store


## Every name `choose` takes: the four corners and `CENTRE`.
static func names() -> Array[String]:
	var all: Array[String] = StatusPanelLook.CORNER_NAMES.duplicate()
	all.append(CENTRE)
	return all


## The corner asked for by `user_args`, else by the intent extra, or "".
static func requested(user_args: PackedStringArray, intent_value: String) -> String:
	var asked: String = ""
	for arg: String in user_args:
		if arg.begins_with(ARG_PREFIX):
			asked = arg.substr(ARG_PREFIX.length()).strip_edges()
	return asked if asked != "" else intent_value.strip_edges()


func corner() -> String:
	return _corner


## Places the panel in `corner_name` and saves it. An unknown name is ignored
## with one warning and nothing changes; returns whether it was taken.
func choose(corner_name: String) -> bool:
	if not names().has(corner_name):
		_warn("corner \"%s\" ignored, expected one of %s" % [corner_name, ", ".join(names())])
		return false
	_corner = corner_name
	current = corner_name
	_save()
	return true


## Chooses the corner `--panel=` or the intent extra asks for, if any.
func apply_switch(user_args: PackedStringArray, intent_value: String) -> void:
	var asked: String = requested(user_args, intent_value)
	if asked != "" and choose(asked):
		print("%s in %s, from the launch switch" % [LOG_PREFIX, asked])


## Reads the saved corner. A missing file gives `DEFAULT_CORNER`; an
## unreadable or wrong one gives it with a warning, so it never stops the game.
func load_saved() -> void:
	_corner = DEFAULT_CORNER
	if FileAccess.file_exists(_path):
		var json: JSON = JSON.new()
		var parsed: bool = json.parse(FileAccess.get_file_as_string(_path)) == OK
		var saved: Variant = json.data if parsed else null
		var keys_ok: bool = saved is Dictionary and (saved as Dictionary).keys() == [FIELD_CORNER]
		if keys_ok and names().has(str((saved as Dictionary)[FIELD_CORNER])):
			_corner = str((saved as Dictionary)[FIELD_CORNER])
		else:
			_warn("%s ignored: expected {\"%s\": <corner>}" % [_path, FIELD_CORNER])
	current = _corner


func _save() -> void:
	var file: FileAccess = FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		_warn("could not save %s (%s)" % [_path, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify({FIELD_CORNER: _corner}))
	file.close()


func _warn(text: String) -> void:
	var line: String = "%s %s" % [LOG_PREFIX, text]
	warnings.append(line)
	push_warning(line)
