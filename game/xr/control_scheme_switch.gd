class_name ControlSchemeSwitch
extends RefCounted

## Chooses the control scheme at launch (#739, PLT-5): `--controls=thumbsticks`
## or `--controls=gripped` on the command line, or the intent extra
## `meltdown_controls` on the headset, read the way `LevelSwitch` reads
## `--level`: an argument wins over the extra and the last argument given
## counts. Without either, or with a bad value (ignored with a warning naming
## it), the thumbsticks fly. A menu replaces this later (#778).
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
var gripped: GrippedSampler = GrippedSampler.new()
## Every warning and log line printed, so tests can read them.
var warnings: PackedStringArray = PackedStringArray()
var lines: PackedStringArray = PackedStringArray()


## The scheme this launch asked for: user arguments and, on Android, the intent extra.
static func from_launch() -> ControlSchemeSwitch:
	return parse(OS.get_cmdline_user_args(), FoveationSwitch.intent_value(INTENT_EXTRA))


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
	elif asked != "":
		chosen._warn("control scheme \"%s\" is not %s" % [asked, " or ".join(SCHEMES)])
	return chosen


static func format_line(in_use: String, left_handed: bool) -> String:
	return '%s{"scheme":"%s","left_handed":%s}' % [
		LOG_PREFIX, in_use, "true" if left_handed else "false"]


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


func _warn(text: String) -> void:
	var line: String = "Meltdown: %s; keeping %s" % [text, THUMBSTICKS]
	warnings.append(line)
	push_warning(line)
