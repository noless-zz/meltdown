class_name ReplayLines
extends RefCounted

## Writes and reads the lines of a replay that carry data: the box line
## (version 3), the tuning line (version 5) and the tick lines. Split out of
## `Replay` to keep both files short; the format is documented there.
##
## The parse functions return "" on success, with the value stored on the
## replay, or a problem without the line number, which `Replay.from_text` adds.


## `box <min x y z> <max x y z>`, in whole millimetres.
static func box_text(min_mm: Vector3i, max_mm: Vector3i) -> String:
	return "box %d %d %d %d %d %d" % [min_mm.x, min_mm.y, min_mm.z, max_mm.x, max_mm.y, max_mm.z]


## `tuning <json>`, with full precision so the values read back are exactly
## the values flown.
static func tuning_text(values: ShipTuning) -> String:
	var data: Dictionary = {}
	for key: String in ShipTuning.KEYS:
		data[key] = values.get(key)
	return "tuning " + JSON.stringify(data, "", false, true)


## `words` is the whole line split on spaces, starting with "box".
static func parse_box_line(replay: Replay, words: PackedStringArray,
		seen: Dictionary[String, bool], version: int) -> String:
	if seen.is_empty():
		return "the first line must be '%s <version>'" % Replay.FORMAT_NAME
	if version < 3:
		return "a box line needs format version 3 or later"
	if seen.has("box"):
		return "'box' appears twice"
	seen["box"] = true
	if words.size() != 7:
		return "box needs six whole numbers"
	var values: Array[int] = []
	for index: int in range(1, 7):
		if not words[index].is_valid_int():
			return "'%s' is not a whole number" % words[index]
		values.append(words[index].to_int())
	var min_mm: Vector3i = Vector3i(values[0], values[1], values[2])
	var max_mm: Vector3i = Vector3i(values[3], values[4], values[5])
	if min_mm.x >= max_mm.x or min_mm.y >= max_mm.y or min_mm.z >= max_mm.z:
		return "box min corner must be below its max corner on every axis"
	replay.set_box(min_mm, max_mm)
	return ""


## `json_text` is everything after "tuning ".
static func parse_tuning_line(replay: Replay, json_text: String,
		seen: Dictionary[String, bool], version: int) -> String:
	if seen.is_empty():
		return "the first line must be '%s <version>'" % Replay.FORMAT_NAME
	if version < 5:
		return "a tuning line needs format version 5 or later"
	if seen.has("tuning"):
		return "'tuning' appears twice"
	seen["tuning"] = true
	var parsed: ShipTuning = ShipTuning.parse_json(json_text)
	if parsed.error != "":
		return "tuning: " + parsed.error
	replay.tuning = parsed
	return ""


## One tick: nine integers per ship, ships joined by `Replay.SHIP_SEPARATOR`.
static func tick_text(frame: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for input: ShipInput in frame:
		var t: Vector3i = input.thrust_q
		var r: Vector3i = input.turn_q
		parts.append("%d %d %d %d %d %d %d %d %d" % [
			t.x, t.y, t.z, r.x, r.y, r.z, 1 if input.afterburner else 0,
			1 if input.reset_to_start else 0, 1 if input.fire_primary else 0])
	return Replay.SHIP_SEPARATOR.join(parts)


## Appends the tick to `replay.frames`, with one input per ship.
static func parse_tick_line(replay: Replay, line: String, version: int) -> String:
	var groups: PackedStringArray = line.split("|")
	if groups.size() != replay.ship_count:
		return "expected inputs for %d ships, found %d" % [replay.ship_count, groups.size()]
	var expected: int = numbers_per_ship(version)
	var inputs: Array[ShipInput] = []
	for group: String in groups:
		var words: PackedStringArray = group.split(" ", false)
		if words.size() != expected:
			return "each ship needs %d numbers, found %d" % [expected, words.size()]
		var values: Array[int] = []
		for word: String in words:
			if not word.is_valid_int():
				return "'%s' is not a whole number" % word
			values.append(word.to_int())
		# Only 0 and 1 are accepted, so a typo cannot be read as "on".
		var afterburner: int = values[6] if expected >= 7 else 0
		if afterburner != 0 and afterburner != 1:
			return "afterburner must be 0 or 1, found %d" % afterburner
		var reset: int = values[7] if expected >= 8 else 0
		if reset != 0 and reset != 1:
			return "reset must be 0 or 1, found %d" % reset
		var fire: int = values[8] if expected >= 9 else 0
		if fire != 0 and fire != 1:
			return "fire must be 0 or 1, found %d" % fire
		inputs.append(ShipInput.new(
			Vector3i(values[0], values[1], values[2]),
			Vector3i(values[3], values[4], values[5]),
			afterburner == 1, reset == 1, fire == 1))
	replay.frames.append(inputs)
	return ""


## How many numbers each ship has on a tick line of `version`.
static func numbers_per_ship(version: int) -> int:
	if version == 1:
		return 6
	if version <= 3:
		return 7
	if version <= 5:
		return 8
	return 9
