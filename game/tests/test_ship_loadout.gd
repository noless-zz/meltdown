extends RefCounted

## Starting loadout from the ship data file, recorded in the replay (#223,
## CMB-1, ARC-2, ARC-4).

const DEFAULT_SHIP: String = "res://data/ships/default_ship.json"
const WEAPON_DIR: String = "res://data/weapons/"
## `_unarmed_replay()`'s final hash on `main` before loadouts existed (#223),
## so a replay without weapon lines must keep it.
const HASH_BEFORE_LOADOUTS: int = 1806171824


static func _ship_text() -> String:
	return FileAccess.get_file_as_string(DEFAULT_SHIP)


## What a caller outside core does: read the file of every id the loadout names.
static func _weapon_texts(loadout: ShipLoadout) -> Dictionary:
	var texts: Dictionary = {}
	for id: String in loadout.weapon_ids():
		texts[id] = FileAccess.get_file_as_string(WEAPON_DIR + id + ".json")
	return texts


## The shipped loadout, resolved from the shipped weapon files.
static func _default_loadout() -> ShipLoadout:
	var loadout: ShipLoadout = ShipTuning.parse_json(_ship_text()).loadout
	loadout.resolve(_weapon_texts(loadout))
	return loadout


## Two ships in a box, both pulling the trigger now and then, recorded with
## the shipped tuning and no weapons. Recorded on `main` before #223 as
## `HASH_BEFORE_LOADOUTS`.
static func _unarmed_replay() -> Replay:
	var replay: Replay = Replay.new(223, 2)
	replay.set_box(Vector3i(-50000, -50000, -400000), Vector3i(50000, 50000, 50000))
	replay.tuning = ShipTuning.parse_json(_ship_text())
	for i: int in 120:
		var inputs: Array[ShipInput] = [
			ShipInput.new(Vector3i(0, 0, -1000), Vector3i(0, 120, 0), false, false, true),
			ShipInput.new(Vector3i(300, 0, -600), Vector3i.ZERO, i % 40 < 20, false, i % 2 == 0)]
		replay.add_tick(inputs)
	return replay


static func _error_with_loadout(loadout: Variant) -> String:
	var data: Dictionary = JSON.parse_string(_ship_text()) as Dictionary
	data["loadout"] = loadout
	return ShipTuning.parse_json(JSON.stringify(data)).error


func test_shipped_ship_has_the_pulse_cannon_in_primary_slot_1() -> String:
	var tuning: ShipTuning = ShipTuning.parse_json(_ship_text())
	if tuning.error != "":
		return "default ship rejected: " + tuning.error
	var loadout: ShipLoadout = tuning.loadout
	if loadout.primary_ids != (["pulse_cannon", ""] as Array[String]):
		return "primary ids are %s" % [loadout.primary_ids]
	if loadout.secondary_ids != (["", ""] as Array[String]):
		return "secondary ids are %s" % [loadout.secondary_ids]
	if loadout.weapon_ids() != (["pulse_cannon"] as Array[String]):
		return "weapon ids are %s" % [loadout.weapon_ids()]
	var problem: String = loadout.resolve(_weapon_texts(loadout))
	if problem != "":
		return "resolve failed: " + problem
	if loadout.primary_weapons[0] == null or loadout.primary_weapons[1] != null:
		return "only primary slot 1 should hold a weapon"
	for weapon: WeaponDef in loadout.secondary_weapons:
		if weapon != null:
			return "a secondary slot holds a weapon"
	return ""


func test_ship_file_without_loadout_starts_empty() -> String:
	var data: Dictionary = JSON.parse_string(_ship_text()) as Dictionary
	data.erase("loadout")
	var tuning: ShipTuning = ShipTuning.parse_json(JSON.stringify(data))
	if tuning.error != "":
		return "rejected: " + tuning.error
	if not tuning.loadout.weapon_ids().is_empty():
		return "a loadout appeared from nowhere"
	return ""


func test_armed_replay_fires_and_reproduces_its_hash() -> String:
	var replay: Replay = _unarmed_replay()
	replay.loadout = _default_loadout()
	var sim: Sim = replay.run()
	if sim == null:
		return "run failed: " + replay.run_error
	# Both ships hold the trigger on the first tick, so each fires at once.
	var probe: Replay = _unarmed_replay()
	probe.loadout = _default_loadout()
	probe.frames = probe.frames.slice(0, 1)
	var fired: int = probe.run().projectiles.size()
	if fired != 2:
		return "expected one shot per ship on the first tick, found %d" % fired
	if sim.ships[0].primary_slots[0] == null or sim.ships[1].primary_slots[0] == null:
		return "a ship was not armed"
	var hash_flown: int = sim.state_hash()
	if hash_flown == HASH_BEFORE_LOADOUTS:
		return "arming the ships did not change the hash"
	var text: String = replay.to_text()
	if text.find("\nweapon primary 1 pulse_cannon {") < 0:
		return "no weapon line in:\n%s" % text
	# Read back with no files at hand: the weapon comes from the text alone.
	var loaded: Replay = Replay.from_text(text)
	if loaded.error != "":
		return "reload failed: " + loaded.error
	var replayed: Sim = loaded.run()
	if replayed.state_hash() != hash_flown:
		return "replayed hash %d, flown %d" % [replayed.state_hash(), hash_flown]
	if loaded.to_text() != text:
		return "round trip changed the text"
	return ""


func test_replay_without_loadout_keeps_its_hash() -> String:
	var replay: Replay = _unarmed_replay()
	var sim: Sim = replay.run()
	if sim.state_hash() != HASH_BEFORE_LOADOUTS:
		return "hash %d, expected %d from main" % [sim.state_hash(), HASH_BEFORE_LOADOUTS]
	var probe: Replay = Replay.from_text(replay.to_text())
	if probe.loadout != null or probe.to_text().find("weapon") >= 0:
		return "a loadout appeared in a replay without one"
	var replayed: Sim = probe.run()
	if not replayed.projectiles.is_empty():
		return "an unarmed replay fired"
	if replayed.state_hash() != HASH_BEFORE_LOADOUTS:
		return "reloaded hash %d, expected %d" % [replayed.state_hash(), HASH_BEFORE_LOADOUTS]
	return ""


func test_equip_only_before_the_first_tick() -> String:
	var sim: Sim = Sim.new(1, 1)
	var inputs: Array[ShipInput] = [ShipInput.new()]
	sim.step(inputs)
	if sim.equip(_default_loadout()):
		return "equipped after the first tick"
	if sim.ships[0].primary_slots[0] != null:
		return "a refused equip changed a slot"
	return ""


func test_loadout_errors_name_the_field() -> String:
	var cases: Array[Array] = [
		[["pulse_cannon"], "\"loadout\" must be an object"],
		[{"tertiary": []}, "unknown key \"loadout.tertiary\""],
		[{"primary": "pulse_cannon"}, "\"loadout.primary\" must be a list"],
		[{"primary": ["a", "b", "c"]}, "\"loadout.primary\" has 3 slots, at most 2"],
		[{"secondary": ["", "", ""]}, "\"loadout.secondary\" has 3 slots, at most 2"],
		[{"primary": [7]}, "\"loadout.primary[0]\" must be a string"],
		[{"primary": ["", "Pulse"]}, "\"loadout.primary[1]\" is \"Pulse\", must use only a-z, 0-9 and _"],
		[{"secondary": ["../x"]}, "\"loadout.secondary[0]\" is \"../x\", must use only a-z, 0-9 and _"],
		[{"primary": ["a".repeat(65)]}, "\"loadout.primary[0]\" must be 1 to 64 characters"],
	]
	for item: Array in cases:
		var error: String = _error_with_loadout(item[0])
		if error != item[1]:
			return "%s gave \"%s\", expected \"%s\"" % [item[0], error, item[1]]
	return ""


func test_resolve_errors_name_the_slot_and_arm_nothing() -> String:
	var loadout: ShipLoadout = ShipTuning.parse_json(_ship_text()).loadout
	var missing: String = loadout.resolve({})
	if missing != "\"loadout.primary[0]\" names weapon \"pulse_cannon\", which has no data":
		return "missing data gave \"%s\"" % missing
	var bad: String = loadout.resolve({"pulse_cannon": "{\"damage\": 1}"})
	if bad != "\"loadout.primary[0]\" weapon \"pulse_cannon\": missing key \"fire_interval_ticks\"":
		return "bad data gave \"%s\"" % bad
	if loadout.is_armed():
		return "a failed resolve left a weapon in a slot"
	return ""


func test_weapon_line_rejections() -> String:
	var header: String = "meltdown-replay 7\nseed 1\nships 1\n"
	var cannon: String = FileAccess.get_file_as_string(WEAPON_DIR + "pulse_cannon.json").replace("\n", "").replace("\t", "")
	var cases: Array[Array] = [
		["meltdown-replay 6\nseed 1\nships 1\nweapon primary 1 pulse_cannon %s\n" % cannon,
			"line 4: a weapon line needs format version 7 or later"],
		[header + "weapon tertiary 1 pulse_cannon %s\n" % cannon,
			"line 4: weapon kind must be primary or secondary, found 'tertiary'"],
		[header + "weapon primary 3 pulse_cannon %s\n" % cannon, "line 4: weapon slot must be 1 to 2, found 3"],
		[header + "weapon primary 1 Pulse %s\n" % cannon,
			"line 4: \"weapon id\" is \"Pulse\", must use only a-z, 0-9 and _"],
		[header + "weapon primary 1 pulse_cannon\n", "line 4: weapon needs a kind, a slot, an id and the weapon's data"],
		[header + "weapon primary 1 x %s\nweapon primary 1 x %s\n" % [cannon, cannon],
			"line 5: 'weapon primary 1' appears twice"],
		[header + "weapon primary 1 x {\"damage\":1}\n", "line 4: weapon primary 1: missing key \"fire_interval_ticks\""],
	]
	for item: Array in cases:
		var replay: Replay = Replay.from_text(item[0] + "inputs\n")
		if replay.error != item[1]:
			return "gave \"%s\", expected \"%s\"" % [replay.error, item[1]]
	return ""
