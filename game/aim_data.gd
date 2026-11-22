class_name AimData
extends RefCounted

## Reads the look-aim and aim assist data files (CMB-7, CMB-8, ARC-4, #1137)
## and hands their values to a new session's simulation before its first tick,
## so tuning either file after a headset session changes the game without a
## code change. It sits beside `level_start.gd`, not in `core/`, because
## `core/` opens no files.
##
## A missing or rejected file logs one line naming the file and the parser's
## error, and the session keeps the simulation's defaults: a bad tuning file
## must never stop the game. Nothing here reads or writes a comfort setting
## (ARC-3).

const LOG_PREFIX: String = "[meltdown aim]"
const LOOK_AIM_PATH: String = "res://data/aim/look_aim.json"
const AIM_ASSIST_PATH: String = "res://data/aim/aim_assist.json"

## The last line logged, kept so tests can check it names the file.
static var last_log: String = ""


## Gives `session` the values of both files, if they load, and returns it. A
## null session is returned as is. The values are not written into the
## session's replay: a replay header line would move every pinned level hash
## (`AcceptanceStepLevel.level_hash`), and the shipped files hold the
## simulation's defaults, which a replay without the lines flies.
static func apply(session: LocalSession, look_aim_path: String = LOOK_AIM_PATH,
		aim_assist_path: String = AIM_ASSIST_PATH) -> LocalSession:
	if session == null:
		return null
	var aim: LookAim = load_look_aim(look_aim_path)
	if aim != null:
		session.sim.set_look_aim(aim)
	var assist: AimAssist = load_aim_assist(aim_assist_path)
	if assist != null:
		session.sim.set_aim_assist(assist)
	return session


## The look-aim values in the file at `path`, or null, after logging why.
static func load_look_aim(path: String) -> LookAim:
	var text: String = _read(path)
	if text == "":
		return null
	var aim: LookAim = LookAim.parse_json(text)
	if aim.error != "":
		_log(path, aim.error)
		return null
	return aim


## The aim assist values in the file at `path`, or null, after logging why.
static func load_aim_assist(path: String) -> AimAssist:
	var text: String = _read(path)
	if text == "":
		return null
	var assist: AimAssist = AimAssist.parse_json(text)
	if assist.error != "":
		_log(path, assist.error)
		return null
	return assist


## The text of the file at `path`, or "" after logging why it could not be read.
static func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		_log(path, "file not found")
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_log(path, "cannot open it (%s)" % error_string(FileAccess.get_open_error()))
		return ""
	var text: String = file.get_as_text()
	if text == "":
		_log(path, "file is empty")
	return text


static func _log(path: String, message: String) -> void:
	last_log = "%s %s: %s" % [LOG_PREFIX, path, message]
	print(last_log)
