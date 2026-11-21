class_name ReplayAimLine
extends RefCounted

## Writes and reads a replay's aim line (version 17): `aim <json>`, the run's
## `LookAim` as a one-line look-aim data file (CMB-6). Kept apart from `Replay`,
## which is at its size limit; the format is documented there. A replay
## without the line flies the values of `LookAim.new()`, and one that never
## aims off the nose flies the same whatever the values.

## First format version that may carry an aim line.
const VERSION: int = ReplayLines.AIM_VERSION


static func lines(replay: Replay) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if replay.look_aim != null:
		out.append("aim " + replay.look_aim.to_json())
	return out


## Gives `sim` the replay's look-aim values, if it has any. Before the first tick.
static func apply(replay: Replay, sim: Sim) -> void:
	if replay.look_aim != null:
		sim.set_look_aim(replay.look_aim)


## `json_text` is everything after "aim ". Returns "" with the values stored on
## `replay`, or a problem without the line number, which `Replay.from_text`
## adds.
static func parse(replay: Replay, json_text: String,
		seen: Dictionary[String, bool], version: int) -> String:
	if seen.is_empty():
		return "the first line must be '%s <version>'" % Replay.FORMAT_NAME
	if version < VERSION:
		return "an aim line needs format version %d or later" % VERSION
	if seen.has("aim"):
		return "'aim' appears twice"
	seen["aim"] = true
	var aim: LookAim = LookAim.parse_json(json_text)
	if aim.error != "":
		return "aim: " + aim.error
	replay.look_aim = aim
	return ""
