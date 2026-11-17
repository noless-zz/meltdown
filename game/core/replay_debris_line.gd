class_name ReplayDebrisLine
extends RefCounted

## Writes and reads a replay's debris line (version 15): `debris <json>`, one
## line after the reactor line, holding the level's falling debris as a JSON
## list (`MeltdownDebris`, RUN-4). Written only when the run has debris, so
## replays without it read and hash as before. Kept apart from `Replay`, which
## is at its size limit; the format is documented there.

## First format version that may carry a debris line.
const VERSION: int = 15


## `debris <json>`; the JSON reads back to exactly these entries.
static func text(debris: MeltdownDebris) -> String:
	return "debris " + debris.to_json()


## `json_text` is everything after "debris ". Returns "" with the debris
## stored on `replay`, or a problem without the line number, which
## `Replay.from_text` adds.
static func parse(replay: Replay, json_text: String,
		seen: Dictionary[String, bool], version: int) -> String:
	if seen.is_empty():
		return "the first line must be '%s <version>'" % Replay.FORMAT_NAME
	if version < VERSION:
		return "a debris line needs format version %d or later" % VERSION
	if seen.has("debris"):
		return "'debris' appears twice"
	seen["debris"] = true
	var debris: MeltdownDebris = MeltdownDebris.parse_json(json_text)
	if debris.error != "":
		return debris.error
	replay.debris = debris
	return ""
