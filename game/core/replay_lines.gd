class_name ReplayLines
extends RefCounted

## Writes and reads the lines of a replay that carry data: the box line
## (version 3), the tuning line (version 5), the weapon lines (version 7) and
## the tick lines. Split out of
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


## `weapon <kind> <slot 1..2> <id> <json>` for every slot of `loadout` that
## holds a resolved weapon, primary first. The JSON carries every value at full
## precision, so the weapon read back is exactly the weapon flown.
static func weapon_lines(loadout: ShipLoadout) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	for kind: String in ShipLoadout.KINDS:
		var ids: Array[String] = loadout.ids_of(kind)
		var weapons: Array[WeaponDef] = loadout.weapons_of(kind)
		for slot: int in ShipLoadout.SLOTS_PER_KIND:
			var weapon: WeaponDef = weapons[slot]
			if weapon == null:
				continue
			var data: Dictionary = {}
			for key: String in WeaponDef.KEYS:
				data[key] = weapon.get(key)
			lines.append("weapon %s %d %s %s" % [kind, slot + 1, ids[slot],
				JSON.stringify(data, "", false, true)])
	return lines


## `line` is the whole weapon line. Fills one slot of `replay.loadout`,
## creating it on the first weapon line.
static func parse_weapon_line(replay: Replay, line: String,
		seen: Dictionary[String, bool], version: int) -> String:
	if seen.is_empty():
		return "the first line must be '%s <version>'" % Replay.FORMAT_NAME
	if version < 7:
		return "a weapon line needs format version 7 or later"
	var words: PackedStringArray = line.split(" ", false, 4)
	if words.size() != 5:
		return "weapon needs a kind, a slot, an id and the weapon's data"
	var kind: String = words[1]
	if not ShipLoadout.KINDS.has(kind):
		return "weapon kind must be primary or secondary, found '%s'" % kind
	if not words[2].is_valid_int():
		return "weapon slot '%s' is not a whole number" % words[2]
	var slot: int = words[2].to_int()
	if slot < 1 or slot > ShipLoadout.SLOTS_PER_KIND:
		return "weapon slot must be 1 to %d, found %d" % [ShipLoadout.SLOTS_PER_KIND, slot]
	var seen_key: String = "weapon %s %d" % [kind, slot]
	if seen.has(seen_key):
		return "'%s' appears twice" % seen_key
	seen[seen_key] = true
	var id_problem: String = ShipLoadout.check_id("weapon id", words[3])
	if id_problem != "":
		return id_problem
	var weapon: WeaponDef = WeaponDef.parse_json(words[4])
	if weapon.error != "":
		return "%s: %s" % [seen_key, weapon.error]
	if replay.loadout == null:
		replay.loadout = ShipLoadout.new()
	replay.loadout.set_slot(kind, slot - 1, words[3], weapon)
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
