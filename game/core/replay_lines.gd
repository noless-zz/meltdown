class_name ReplayLines
extends RefCounted

## Writes and reads the lines of a replay that carry data: the tuning line
## (version 5), the weapon lines (version 7), the robot lines (version 8, armed and with every
## robot key from version 9) and the tick lines. Split out of `Replay` to keep
## both files short; the format is documented there.
##
## The parse functions return "" on success, with the value stored on the
## replay, or a problem without the line number, which `Replay.from_text` adds.

## The two keys of a version 9 robot line's JSON object.
const ROBOT_LINE_KEYS: Array[String] = ["robot", "weapon"]


## `tuning <json>`, with full precision so the values read back are exactly
## the values flown.
static func tuning_text(values: ShipTuning) -> String:
	var data: Dictionary = {}
	for key: String in ShipTuning.KEYS:
		data[key] = values.get(key)
	return "tuning " + JSON.stringify(data, "", false, true)


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
			lines.append("weapon %s %d %s %s" % [kind, slot + 1, ids[slot],
				JSON.stringify(weapon_data(weapon), "", false, true)])
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


## `robot <x y z> <facing x y z> <json>`: position and facing in whole
## millimetres, then one JSON object at full precision, so the robot read back
## is exactly the robot flown against. Its "robot" key holds every value of the
## robot's type, optional ones included (a wake range only when set), and its
## "weapon" key the resolved weapon's values, or null for an unarmed robot
## (version 9).
static func robot_text(spawn: RobotSpawn) -> String:
	var def_data: Dictionary = {}
	for key: String in RobotDef.KEYS + RobotDef.OPTIONAL_KEYS:
		# An unset wake range is left out, so lines for robots without one
		# read exactly as before (#301).
		if key == "wake_range" and not spawn.def.has_wake_range():
			continue
		def_data[key] = spawn.def.get(key)
	var weapon_values: Variant = null
	if spawn.weapon != null:
		weapon_values = weapon_data(spawn.weapon)
	var p: Vector3i = spawn.position_mm
	var f: Vector3i = spawn.facing_mm
	return "robot %d %d %d %d %d %d %s" % [p.x, p.y, p.z, f.x, f.y, f.z,
		JSON.stringify({"robot": def_data, "weapon": weapon_values}, "", false, true)]


## `line` is the whole robot line. Appends one spawn to `replay.robots`.
## Version 8 lines hold the robot type's data alone and read as unarmed.
static func parse_robot_line(replay: Replay, line: String,
		seen: Dictionary[String, bool], version: int) -> String:
	if seen.is_empty():
		return "the first line must be '%s <version>'" % Replay.FORMAT_NAME
	if version < 8:
		return "a robot line needs format version 8 or later"
	var words: PackedStringArray = line.split(" ", false, 7)
	if words.size() != 8:
		return "robot needs a position, a facing and the robot's data"
	var values: Array[int] = []
	for index: int in range(1, 7):
		if not words[index].is_valid_int():
			return "'%s' is not a whole number" % words[index]
		values.append(words[index].to_int())
	var facing: Vector3i = Vector3i(values[3], values[4], values[5])
	if facing == Vector3i.ZERO:
		return "robot facing must not be zero"
	var number: int = replay.robots.size() + 1
	var def_text: String = words[7]
	var weapon: WeaponDef = null
	if version >= 9:
		var parts: Array = []
		var problem: String = _split_robot_json(words[7], parts)
		if problem != "":
			return "robot %d: %s" % [number, problem]
		def_text = parts[0]
		if parts[1] != null:
			weapon = WeaponDef.parse_json(parts[1])
			if weapon.error != "":
				return "robot %d weapon: %s" % [number, weapon.error]
	var def: RobotDef = RobotDef.parse_json(def_text)
	if def.error != "":
		return "robot %d: %s" % [number, def.error]
	replay.robots.append(RobotSpawn.new(def, Vector3i(values[0], values[1], values[2]),
		facing, weapon))
	return ""


## Every value of `weapon` by key, as the weapon and robot lines write them.
static func weapon_data(weapon: WeaponDef) -> Dictionary:
	var data: Dictionary = {}
	for key: String in WeaponDef.KEYS:
		data[key] = weapon.get(key)
	# Burst keys only when set, so lines for weapons without them read exactly
	# as before (#612).
	if weapon.has_bursts():
		for key: String in WeaponDef.OPTIONAL_KEYS:
			data[key] = weapon.get(key)
	return data


## Splits a version 9 robot object into the robot type's text and the
## weapon's text (null when unarmed), appended to `into`. Each is written back
## at full precision, so the parsers below see the values exactly.
static func _split_robot_json(text: String, into: Array) -> String:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]
	if typeof(json.data) != TYPE_DICTIONARY:
		return "robot data must be a JSON object"
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not ROBOT_LINE_KEYS.has(key):
			return "unknown key \"%s\"" % str(key)
	for key: String in ROBOT_LINE_KEYS:
		if not data.has(key):
			return "missing key \"%s\"" % key
	if typeof(data["robot"]) != TYPE_DICTIONARY:
		return "key \"robot\" must be a JSON object"
	into.append(JSON.stringify(data["robot"], "", false, true))
	if data["weapon"] == null:
		into.append(null)
		return ""
	if typeof(data["weapon"]) != TYPE_DICTIONARY:
		return "key \"weapon\" must be a JSON object or null"
	into.append(JSON.stringify(data["weapon"], "", false, true))
	return ""


## One tick: ten integers per ship, ships joined by `Replay.SHIP_SEPARATOR`.
static func tick_text(frame: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for input: ShipInput in frame:
		var t: Vector3i = input.thrust_q
		var r: Vector3i = input.turn_q
		parts.append("%d %d %d %d %d %d %d %d %d %d" % [
			t.x, t.y, t.z, r.x, r.y, r.z, 1 if input.afterburner else 0,
			1 if input.reset_to_start else 0, 1 if input.fire_primary else 0,
			1 if input.slot_held else 0])
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
		var slot: int = values[9] if expected >= 10 else 0
		if slot != 0 and slot != 1:
			return "slot must be 0 or 1, found %d" % slot
		inputs.append(ShipInput.new(
			Vector3i(values[0], values[1], values[2]),
			Vector3i(values[3], values[4], values[5]),
			afterburner == 1, reset == 1, fire == 1, slot == 1))
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
	if version <= 10:
		return 9
	return 10
