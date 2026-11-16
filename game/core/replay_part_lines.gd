class_name ReplayPartLines
extends RefCounted

## Writes and reads a replay's part lines (version 10): one line per entry of
## the part catalogue (`Sim.set_parts`). Kept apart from `ReplayLines`, which
## is near its size limit; the format is documented in `Replay`.
##
## The parse function returns "" on success, with the part stored on the
## replay, or a problem without the line number, which `Replay.from_text` adds.


## `part <id> <json>` for every part, sorted by id so the text is stable. The
## JSON carries every weapon value at full precision, so the part read back is
## exactly the part flown with.
static func part_lines(parts: Dictionary[String, WeaponDef]) -> PackedStringArray:
	var ids: Array[String] = []
	ids.assign(parts.keys())
	ids.sort()
	var lines: PackedStringArray = PackedStringArray()
	for id: String in ids:
		lines.append("part %s %s" % [id,
			JSON.stringify(ReplayLines.weapon_data(parts[id]), "", false, true)])
	return lines


## `line` is the whole part line. Adds one entry to `replay.parts`.
static func parse_part_line(replay: Replay, line: String,
		seen: Dictionary[String, bool], version: int) -> String:
	if seen.is_empty():
		return "the first line must be '%s <version>'" % Replay.FORMAT_NAME
	if version < 10:
		return "a part line needs format version 10 or later"
	var words: PackedStringArray = line.split(" ", false, 2)
	if words.size() != 3:
		return "part needs an id and the part's data"
	var id: String = words[1]
	var id_problem: String = ShipLoadout.check_id("part id", id)
	if id_problem != "":
		return id_problem
	var seen_key: String = "part %s" % id
	if seen.has(seen_key):
		return "'%s' appears twice" % seen_key
	seen[seen_key] = true
	var weapon: WeaponDef = WeaponDef.parse_json(words[2])
	if weapon.error != "":
		return "%s: %s" % [seen_key, weapon.error]
	replay.parts[id] = weapon
	return ""
