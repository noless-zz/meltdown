class_name ReplayHeader
extends RefCounted

## Reads one header line of a replay (everything before `inputs`) into the
## replay. Split out of `Replay` to keep it short; the format is documented
## there. Data lines go to `ReplayLines`, `ReplayBoxLine`, `ReplayPartLines`,
## `ReplayReactorLine`, `ReplayDebrisLine`, `ReplaySalvageLine`, `ReplayAimLine`, `ReplayRulesLine` and
## `ReplayStartLine`.
##
## Version 1 has no afterburner column: six numbers per ship, read with the
## afterburner off. Versions 1 to 3 have no reset column and are read with it
## off. Versions 1 to 5 have no fire column and are read with it off. Versions
## 1 to 10 have no slot column and are read with it off. Versions 1 and 2 have
## no box line, versions 3 to 11 at most one, versions 1 to 4 no tuning line,
## versions 1 to 6 no weapon lines, versions 1 to 7 no robot lines, versions 1
## to 9 no part lines, versions 1 to 12 no reactor line, versions 1 to 13 no
## start line, versions 1 to 14 no debris line, versions 1 to 15 no salvage
## line, versions 1 to 16 no aim line and no aim columns, versions 1 to 17 no
## components or rescue line. Version 8 robot lines hold the robot's data file alone, with no
## "robot" or "weapon" key, and read as unarmed.


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
	if line.begins_with("debris "):
		return ReplayDebrisLine.parse(replay, line.substr(7), seen, replay.parse_version)
	if line.begins_with("salvage "):
		return ReplaySalvageLine.parse(replay, line.substr(8), seen, replay.parse_version)
	if line.begins_with("aim "):
		return ReplayAimLine.parse(replay, line.substr(4), seen, replay.parse_version)
	if line.begins_with("components "):
		return ReplayRulesLine.parse_components(replay, line.substr(11), seen, replay.parse_version)
	if line.begins_with("rescue "):
		return ReplayRulesLine.parse_rescue(replay, line.substr(7), seen, replay.parse_version)
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


## Parses whole replay text for `Replay.from_text`, which documents it; here so
## `replay.gd` stays under its size limit.
static func read_text(text: String) -> Replay:
	var replay: Replay = Replay.new()
	var in_header: bool = true
	var seen: Dictionary[String, bool] = {}
	var line_number: int = 0
	for raw_line: String in text.split("\n"):
		line_number += 1
		var line: String = raw_line.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var problem: String = ""
		if in_header:
			if line == "inputs":
				in_header = false
				if not (seen.has("seed") and seen.has("ships")):
					problem = "header needs both seed and ships"
			else:
				problem = parse_line(replay, line, seen)
		else:
			problem = ReplayLines.parse_tick_line(replay, line, replay.parse_version)
		if problem != "":
			replay.error = "line %d: %s" % [line_number, problem]
			return replay
	if in_header:
		replay.error = "no inputs section"
	return replay
