class_name ReplayReactorLine
extends RefCounted

## Writes and reads a replay's reactor line (version 13): `reactor <json>`, one
## line after the box lines, holding the level's reactor as it is before the
## first tick (`ReactorState`, RUN-2). Kept apart from `Replay` and
## `ReplayLines`, which are at their size limit; the format is documented in
## `Replay`. The JSON holds the meltdown scaling keys (RUN-5) only when the level
## set them, so lines written before them read back unchanged.

## First format version that may carry a reactor line.
const VERSION: int = 13


## `reactor <json>`; the JSON reads back to exactly this reactor.
static func text(reactor: ReactorState) -> String:
	return "reactor " + reactor.to_json()


## `json_text` is everything after "reactor ". Returns "" with the reactor
## stored on `replay`, or a problem without the line number, which
## `Replay.from_text` adds.
static func parse(replay: Replay, json_text: String,
		seen: Dictionary[String, bool], version: int) -> String:
	if seen.is_empty():
		return "the first line must be '%s <version>'" % Replay.FORMAT_NAME
	if version < VERSION:
		return "a reactor line needs format version %d or later" % VERSION
	if seen.has("reactor"):
		return "'reactor' appears twice"
	seen["reactor"] = true
	var reactor: ReactorState = ReactorState.parse_json(json_text)
	if reactor.error != "":
		return reactor.error
	replay.reactor = reactor
	return ""
