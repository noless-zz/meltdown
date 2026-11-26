class_name ReplayCrewLine
extends RefCounted

## Writes and reads a replay's crew line (version 21, #1386): the `CrewBonus`
## a run level flies with, so a replay of a run with crew reproduces (ARC-2).
## Called through `ReplayRulesLine`, which writes and applies the other
## run-level lines; `Replay` is at its size limit.
##
##     crew {"hold_slots":2,"meltdown_seconds":20}
##
## Only a bonus above zero is written. A replay without the line flies without
## crew, as every replay before version 21 did, and is written as an older
## version, so the text of every other replay, and every hash taken from it,
## stays as it was.

## First format version that may carry the line.
const VERSION: int = 21


## The version a replay with crew needs at least, or 0 without.
static func format_version(replay: Replay) -> int:
	return VERSION if _written(replay) else 0


static func lines(replay: Replay) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if _written(replay):
		out.append("crew " + replay.crew.to_json())
	return out


## Gives `sim` the replay's crew bonus, if it has one. Before the first tick.
static func apply(replay: Replay, sim: Sim) -> void:
	if replay.crew != null:
		sim.set_crew_bonus(replay.crew)


## `json_text` is everything after "crew ". Returns "" with the bonus stored
## on `replay`, or a problem without the line number.
static func parse(replay: Replay, json_text: String,
		seen: Dictionary[String, bool], version: int) -> String:
	if seen.is_empty():
		return "the first line must be '%s <version>'" % Replay.FORMAT_NAME
	if version < VERSION:
		return "a crew line needs format version %d or later" % VERSION
	if seen.has("crew"):
		return "'crew' appears twice"
	seen["crew"] = true
	var bonus: CrewBonus = CrewBonus.parse_json(json_text)
	if bonus.error != "":
		return "crew: " + bonus.error
	replay.crew = bonus
	return ""


static func _written(replay: Replay) -> bool:
	return replay.crew != null and replay.crew.error == "" and not replay.crew.is_zero()
