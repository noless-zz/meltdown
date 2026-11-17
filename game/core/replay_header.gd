class_name ReplayHeader
extends RefCounted

## Reads one header line of a replay (everything before `inputs`) into the
## replay. Split out of `Replay` to keep it short; the format is documented
## there. Data lines go to `ReplayLines`, `ReplayBoxLine`, `ReplayPartLines`,
## `ReplayReactorLine` and `ReplayStartLine`.


## Returns "" with the value stored on `replay`, or a problem without the line
## number, which `Replay.from_text` adds.
static func parse_line(replay: Replay, line: String, seen: Dictionary[String, bool]) -> String:
	if line.begins_with("tuning "):
		return ReplayLines.parse_tuning_line(replay, line.substr(7), seen, replay.parse_version)
	if line.begins_with("weapon "):
		return ReplayLines.parse_weapon_line(replay, line, seen, replay.parse_version)
	if line.begins_with("robot "):
		return ReplayLines.parse_robot_line(replay, line, seen, replay.parse_version)
	if line.begins_with("reactor "):
		return ReplayReactorLine.parse(replay, line.substr(8), seen, replay.parse_version)
	if line.begins_with("part "):
		return ReplayPartLines.parse_part_line(replay, line, seen, replay.parse_version)
	var words: PackedStringArray = line.split(" ", false)
	if words.size() > 0 and words[0] == "box":
		return ReplayBoxLine.parse(replay, words, seen, replay.parse_version)
	if words.size() > 0 and words[0] == "start":
		return ReplayStartLine.parse(replay, words, seen, replay.parse_version)
	if words.size() != 2 or not words[1].is_valid_int():
		return "expected a name and one whole number"
	var key: String = words[0]
	var value: int = words[1].to_int()
	# The format line must come first so that a file of another kind, or of a
	# newer version whose keys mean something else, is rejected before use.
	if seen.is_empty() != (key == Replay.FORMAT_NAME):
		return "the first line must be '%s <version>'" % Replay.FORMAT_NAME
	if seen.has(key):
		return "'%s' appears twice" % key
	seen[key] = true
	if key == Replay.FORMAT_NAME:
		if value < Replay.OLDEST_VERSION or value > Replay.FORMAT_VERSION:
			return "unsupported format version %d" % value
		replay.parse_version = value
		return ""
	match key:
		"seed":
			replay.run_seed = value
		"ships":
			if value < 1:
				return "ships must be at least 1"
			replay.ship_count = value
		"hash":
			# State hashes are never negative, and NO_HASH is. Reading
			# "hash -1" as "no hash" would switch the check off silently.
			if value < 0:
				return "hash must not be negative"
			replay.expected_hash = value
		_:
			return "unknown header line '%s'" % key
	return ""
