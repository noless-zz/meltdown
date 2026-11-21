class_name ComfortSwitch
extends RefCounted

## The launch switch for the custom comfort mode (CMF-1, #806): `--comfort=custom`
## on the command line, or the intent extra `meltdown_comfort` = `custom` on the
## headset, read the way `LevelSwitch` reads `--level`: an argument wins over
## the extra, and the last argument given counts. A bad value is ignored with a
## warning naming it. Without the switch, `--comfort-preset=N` decides as before.
##
## View side only: it picks which comfort preset this player's input uses and
## never touches simulation state (ARC-3, CMF-6).

const ARG_PREFIX: String = "--comfort="
const INTENT_EXTRA: String = "meltdown_comfort"
const CUSTOM: String = "custom"

## True when the custom mode was asked for with a good value.
var custom: bool = false
## Every warning printed, so tests can read them.
var warnings: PackedStringArray = PackedStringArray()


## The switch this launch was given: user arguments and, on Android, the intent extra.
static func from_launch() -> ComfortSwitch:
	return parse(OS.get_cmdline_user_args(), FoveationSwitch.intent_value(INTENT_EXTRA))


## The switch in `user_args`, falling back to the intent extra's value.
static func parse(user_args: PackedStringArray, intent: String) -> ComfortSwitch:
	var chosen: ComfortSwitch = ComfortSwitch.new()
	var asked: String = ""
	for arg: String in user_args:
		if arg.begins_with(ARG_PREFIX):
			asked = arg.substr(ARG_PREFIX.length()).strip_edges()
	if asked == "":
		asked = intent.strip_edges()
	if asked == CUSTOM:
		chosen.custom = true
	elif asked != "":
		var line: String = "Meltdown: comfort mode \"%s\" is not %s; ignored" % [asked, CUSTOM]
		chosen.warnings.append(line)
		push_warning(line)
	return chosen


## The preset number a run starts with: the custom mode when the switch asks
## for it, otherwise `ComfortPresetFiles.number_from_args(args)`.
func number(args: PackedStringArray) -> int:
	return ComfortPresetFiles.CUSTOM_NUMBER if custom else ComfortPresetFiles.number_from_args(args)


## `main.gd`'s start preset for the arguments `args`.
static func number_from_launch(args: PackedStringArray) -> int:
	return from_launch().number(args)
