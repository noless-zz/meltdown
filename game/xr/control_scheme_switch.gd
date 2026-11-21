class_name ControlSchemeSwitch
extends RefCounted

## Chooses the control scheme at launch (#739, PLT-5): `--controls=thumbsticks`
## or `--controls=gripped` on the command line, or the intent extra
## `meltdown_controls` on the headset, read the way `LevelSwitch` reads
## `--level`: an argument wins over the extra and the last argument given
## counts. Without either, the scheme saved from the dev menu flies
## (`ControlsChoice`, #778); with no saved file, or with a bad value (ignored
## with a warning naming it), the thumbsticks fly.
##
## The dev menu switches the scheme mid-session with `switch_to` (#778),
## only while it is open, so the ship is on neutral input at that moment.
##
## `map_values` turns one frame's sampled values into one tick's input through
## the chosen scheme. The keyboard has no hand poses, so it always flies
## through the thumbstick mapping, which keeps flat play working (PLT-4).
## The scheme in use is printed once, on the first frame, when the hand
## setting is known. Input side only: no simulation state here (ARC-3, MP-2).

const ARG_PREFIX: String = "--controls="
const INTENT_EXTRA: String = "meltdown_controls"
const THUMBSTICKS: String = "thumbsticks"
const GRIPPED: String = "gripped"
const SCHEMES: Array[String] = [THUMBSTICKS, GRIPPED]
const LOG_PREFIX: String = "MELTDOWN_CONTROLS "

var scheme: String = THUMBSTICKS
## Whether an argument or intent extra named a valid scheme; it then beats the saved one.
var from_switch: bool = false
var gripped: GrippedSampler = GrippedSampler.new()
## Every warning and log line printed, so tests can read them.
var warnings: PackedStringArray = PackedStringArray()
var lines: PackedStringArray = PackedStringArray()


## The scheme this launch asked for: user arguments and, on Android, the
## intent extra; without either, the one saved at `saved_path`.
static func from_launch(saved_path: String = ControlsChoice.DEFAULT_PATH) -> ControlSchemeSwitch:
	var chosen: ControlSchemeSwitch = parse(OS.get_cmdline_user_args(),
		FoveationSwitch.intent_value(INTENT_EXTRA))
	chosen.use_saved(ControlsChoice.new(saved_path).load_saved())
	return chosen


## The scheme in `user_args`, falling back to the intent extra's value.
static func parse(user_args: PackedStringArray, intent: String) -> ControlSchemeSwitch:
	var chosen: ControlSchemeSwitch = ControlSchemeSwitch.new()
	var asked: String = ""
	for arg: String in user_args:
		if arg.begins_with(ARG_PREFIX):
			asked = arg.substr(ARG_PREFIX.length()).strip_edges()
	if asked == "":
		asked = intent.strip_edges()
	if asked in SCHEMES:
		chosen.scheme = asked
		chosen.from_switch = true
	elif asked != "":
		chosen._warn("control scheme \"%s\" is not %s" % [asked, " or ".join(SCHEMES)])
	return chosen


## The start line; a change from the menu adds `"source":"menu"` (#778).
static func format_line(in_use: String, left_handed: bool, source: String = "") -> String:
	var tail: String = ',"source":"%s"' % source if source != "" else ""
	return '%s{"scheme":"%s","left_handed":%s%s}' % [
		LOG_PREFIX, in_use, "true" if left_handed else "false", tail]


## Flies `saved` (a scheme name, or "" for none) unless the launch switch chose one.
func use_saved(saved: String) -> void:
	if not from_switch and saved in SCHEMES:
		scheme = saved


## Changes the scheme for the rest of the session from the dev menu (#778).
## Any grab point the gripped sampler holds is let go, so the gripped scheme
## never starts from a pose recorded before the switch. Prints the line again
## with the menu as its source. An unknown name changes nothing; returns
## whether `to` is now in use.
func switch_to(to: String, left_handed: bool) -> bool:
	if not to in SCHEMES:
		_warn("control scheme \"%s\" from the menu is not %s" % [to, " or ".join(SCHEMES)], scheme)
		return false
	scheme = to
	gripped.release_all()
	_log(format_line(scheme, left_handed, "menu"))
	return true


func is_gripped() -> bool:
	return scheme == GRIPPED


## One tick's input from one frame's values, through the chosen scheme.
func map_values(mapping: ThumbstickMapping, values: Dictionary) -> ShipInput:
	if lines.is_empty():
		_log(format_line(scheme, mapping.left_handed))
	if is_gripped() and values.has(ControllerSampler.POSES):
		return gripped.map_values(values, mapping)
	return ControllerSampler.map_values(mapping, values)


func _log(line: String) -> void:
	lines.append(line)
	print(line)


func _warn(text: String, keeping: String = THUMBSTICKS) -> void:
	var line: String = "Meltdown: %s; keeping %s" % [text, keeping]
	warnings.append(line)
	push_warning(line)
