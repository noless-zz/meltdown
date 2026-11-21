class_name FoveationSwitch
extends RefCounted

## Launch switches for foveated rendering (#738, part 2 of #734; PRF-1, PRF-2,
## GFX-1, DEV-6). Foveation is off since #731 because level 3 with dynamic
## foveation collapsed the picture on the Quest 3; finding the failing setting
## takes one device run per setting, and these switches avoid a build for each.
##
## `--foveation=<0..3>` and `--foveation-dynamic=on|off` on the command line,
## or the intent extras `meltdown_foveation` and `meltdown_foveation_dynamic` on
## the headset, read the way `LevelSwitch` reads `--level`: an argument wins
## over the extra, and the last argument given counts. Without them the project
## settings stay as they are. A bad value is ignored with a warning naming it.
##
## The chosen values go to the OpenXR interface once, when the session begins,
## through any object with `foveation_level` and `foveation_dynamic`, so tests
## need no headset. One `MELTDOWN_FOVEATION` line is printed then, and another
## whenever the level read back differs from the last one printed (checked at
## most once a second), so a device log shows what was in use when a fault
## appears. View side only: nothing here touches simulation state (ARC-3).

const LEVEL_ARG_PREFIX: String = "--foveation="
const DYNAMIC_ARG_PREFIX: String = "--foveation-dynamic="
const LEVEL_INTENT_EXTRA: String = "meltdown_foveation"
const DYNAMIC_INTENT_EXTRA: String = "meltdown_foveation_dynamic"
const LOG_PREFIX: String = "MELTDOWN_FOVEATION "
const MAX_LEVEL: int = 3
## Seconds between two read-backs of the level in use.
const CHECK_PERIOD_S: float = 1.0
const SOURCE_DEFAULT: String = "default"
const SOURCE_SWITCH: String = "switch"
const NOT_LOGGED: int = -1

## The level asked for, valid only when `has_level`.
var level: int = 0
var has_level: bool = false
## Whether dynamic foveation was asked for, valid only when `has_dynamic`.
var dynamic: bool = false
var has_dynamic: bool = false
## Every warning and log line printed, so tests can read them.
var warnings: PackedStringArray = PackedStringArray()
var lines: PackedStringArray = PackedStringArray()

## The OpenXR interface, or a test's stand-in; null until the session begins.
var _runtime: Object = null
var _logged_level: int = NOT_LOGGED
var _since_check_s: float = 0.0


## The switches this launch was given: user arguments and, on Android, the intent extras.
static func from_launch() -> FoveationSwitch:
	return parse(OS.get_cmdline_user_args(), intent_value(LEVEL_INTENT_EXTRA),
		intent_value(DYNAMIC_INTENT_EXTRA))


## The switches in `user_args`, falling back to the intent extras' values.
static func parse(user_args: PackedStringArray, level_intent: String,
		dynamic_intent: String) -> FoveationSwitch:
	var chosen: FoveationSwitch = FoveationSwitch.new()
	var level_text: String = _requested(user_args, LEVEL_ARG_PREFIX, level_intent)
	if level_text != "":
		var asked: int = level_from(level_text)
		if asked < 0:
			chosen._warn("foveation level \"%s\" is not 0 to %d" % [level_text, MAX_LEVEL])
		else:
			chosen.level = asked
			chosen.has_level = true
	var dynamic_text: String = _requested(user_args, DYNAMIC_ARG_PREFIX, dynamic_intent)
	if dynamic_text == "on" or dynamic_text == "off":
		chosen.dynamic = dynamic_text == "on"
		chosen.has_dynamic = true
	elif dynamic_text != "":
		chosen._warn("foveation dynamic \"%s\" is not on or off" % dynamic_text)
	return chosen


## `text` as a level, or -1 unless it is a single digit from 0 to `MAX_LEVEL`.
static func level_from(text: String) -> int:
	if text.length() != 1 or not "0123456789".contains(text):
		return -1
	var value: int = text.to_int()
	return value if value <= MAX_LEVEL else -1


## The intent extra `extra_name` of the intent that started the game, or ""
## off Android or when it is absent. The same reading as
## `InstallerProbe.intent_extra`, repeated because `xr/` may not depend on `meta/`.
static func intent_value(extra_name: String) -> String:
	if OS.get_name() != "Android" or not Engine.has_singleton("AndroidRuntime"):
		return ""
	var activity: Object = Engine.get_singleton("AndroidRuntime").call("getActivity")
	var intent: Object = activity.call("getIntent") if activity != null else null
	var value: Variant = intent.call("getStringExtra", extra_name) if intent != null else null
	return value if value is String else ""


## Whether any switch was given and accepted.
func is_switched() -> bool:
	return has_level or has_dynamic


## Called when the XR session begins, before the first frame is drawn: applies
## the chosen values to `runtime` and prints the start line.
func begin(runtime: Object) -> void:
	_runtime = runtime
	if has_level:
		runtime.set("foveation_level", level)
	if has_dynamic:
		runtime.set("foveation_dynamic", dynamic)
	_since_check_s = 0.0
	_log_in_use()


## One rendered frame of `delta_s` seconds; reads the level back once a second
## and prints a line when it changed since the last line.
func advance(delta_s: float) -> void:
	if _runtime == null:
		return
	_since_check_s += delta_s
	if _since_check_s < CHECK_PERIOD_S:
		return
	_since_check_s = 0.0
	if int(_runtime.get("foveation_level")) != _logged_level:
		_log_in_use()


static func format_line(in_use_level: int, in_use_dynamic: bool, source: String) -> String:
	return '%s{"level":%d,"dynamic":%s,"source":"%s"}' % [
		LOG_PREFIX, in_use_level, "true" if in_use_dynamic else "false", source]


static func _requested(user_args: PackedStringArray, prefix: String, intent: String) -> String:
	var asked: String = ""
	for arg: String in user_args:
		if arg.begins_with(prefix):
			asked = arg.substr(prefix.length()).strip_edges()
	return asked if asked != "" else intent.strip_edges()


func _log_in_use() -> void:
	_logged_level = int(_runtime.get("foveation_level"))
	var line: String = format_line(_logged_level, bool(_runtime.get("foveation_dynamic")),
		SOURCE_SWITCH if is_switched() else SOURCE_DEFAULT)
	lines.append(line)
	print(line)


func _warn(text: String) -> void:
	var line: String = "Meltdown: %s; keeping the default" % text
	warnings.append(line)
	push_warning(line)
