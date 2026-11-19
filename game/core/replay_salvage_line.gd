class_name ReplaySalvageLine
extends RefCounted

## Writes and reads a replay's salvage line (version 16): `salvage <json>`, the
## run's `SalvageRules` as a one-line salvage data file (#600). Kept apart from
## `Replay`, which is at its size limit; the format is documented there. A
## replay without the line flies the rules of `SalvageRules.new()`, which are
## the rules every replay before version 16 was recorded with.

## First format version that may carry a salvage line.
const VERSION: int = 16


static func text(rules: SalvageRules) -> String:
	return "salvage " + rules.to_json()


## `json_text` is everything after "salvage ". Returns "" with the rules stored
## on `replay`, or a problem without the line number, which `Replay.from_text`
## adds.
static func parse(replay: Replay, json_text: String,
		seen: Dictionary[String, bool], version: int) -> String:
	if seen.is_empty():
		return "the first line must be '%s <version>'" % Replay.FORMAT_NAME
	if version < VERSION:
		return "a salvage line needs format version %d or later" % VERSION
	if seen.has("salvage"):
		return "'salvage' appears twice"
	seen["salvage"] = true
	var rules: SalvageRules = SalvageRules.parse_json(json_text)
	if rules.error != "":
		return "salvage: " + rules.error
	replay.salvage_rules = rules
	return ""
