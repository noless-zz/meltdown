extends RefCounted

## A weapon file may say `"crafted_only": true` (#1105, SLV-1, SLV-2, ARC-2):
## such a weapon stays out of the salvage catalogue, so adding one moves no
## session's hash, and a ship fitted with one still has it in its session's
## catalogue, so it can be slotted again after it is dropped.

const WEAPON_DIR: String = "res://data/weapons/"
const SHIP_FILE: String = "res://data/ships/default_ship.json"
const SCRATCH_DIR: String = "user://test_crafted_only_weapons"
const WEAPON_IDS: Array[String] = ["arc_lance", "needle_gun", "pulse_cannon", "slug_thrower"]
const GOOD: String = "{\"fire_interval_ticks\": 10, \"projectile_speed\": 120.0, \"lifetime\": 1.5, \"damage\": 8.0, \"energy_cost\": 2.0%s}"


func _write(file_name: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	var file: FileAccess = FileAccess.open(SCRATCH_DIR.path_join(file_name), FileAccess.WRITE)
	file.store_string(text)
	file.close()


## A scratch weapon folder: one plain weapon and one crafted-only weapon.
func _scratch_weapons() -> void:
	_write("needle_gun.json", FileAccess.get_file_as_string(WEAPON_DIR + "needle_gun.json"))
	_write("forge_gun.json", GOOD % ", \"crafted_only\": true")


func _sorted_ids(parts: Dictionary[String, WeaponDef]) -> Array[String]:
	var ids: Array[String] = []
	ids.assign(parts.keys())
	ids.sort()
	return ids


func test_crafted_only_defaults_to_false_and_reads_true() -> String:
	var plain: WeaponDef = WeaponDef.parse_json(GOOD % "")
	if plain.error != "" or plain.crafted_only:
		return "a file without the key reads crafted_only %s (%s)" % [plain.crafted_only, plain.error]
	var crafted: WeaponDef = WeaponDef.parse_json(GOOD % ", \"crafted_only\": true")
	if crafted.error != "" or not crafted.crafted_only:
		return "a crafted-only file reads crafted_only %s (%s)" % [crafted.crafted_only, crafted.error]
	if crafted.values_hash() != plain.values_hash():
		return "crafted_only changes the weapon's values hash"
	for id: String in WEAPON_IDS:
		var shipped: WeaponDef = WeaponDef.parse_json(
			FileAccess.get_file_as_string(WEAPON_DIR.path_join(id + ".json")))
		if shipped.crafted_only:
			return "shipped weapon %s is crafted-only, which would move every hash" % id
	return ""


func test_a_non_boolean_crafted_only_is_rejected_naming_the_key() -> String:
	for value: String in ["1", "0", "\"yes\"", "null", "[]"]:
		var weapon: WeaponDef = WeaponDef.parse_json(GOOD % (", \"crafted_only\": " + value))
		if weapon.error == "" or not weapon.error.contains("crafted_only"):
			return "crafted_only %s gave error \"%s\"" % [value, weapon.error]
	var typo: WeaponDef = WeaponDef.parse_json(GOOD % ", \"crafted\": true")
	if typo.error == "":
		return "an unknown key next to crafted_only was accepted"
	return ""


func test_the_catalogue_leaves_out_crafted_only_weapons() -> String:
	_scratch_weapons()
	var parts: Dictionary[String, WeaponDef] = LocalSession.load_parts(SCRATCH_DIR)
	if _sorted_ids(parts) != ["needle_gun"]:
		return "the catalogue holds %s, expected only needle_gun" % [_sorted_ids(parts)]
	if _sorted_ids(LocalSession.load_parts()) != WEAPON_IDS:
		return "the shipped catalogue holds %s" % [_sorted_ids(LocalSession.load_parts())]
	return ""


func test_a_session_fitted_with_a_crafted_weapon_can_slot_it() -> String:
	_scratch_weapons()
	var ship: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SHIP_FILE))
	ship["loadout"]["primary"] = ["forge_gun", ""]
	_write("forge_ship.json", JSON.stringify(ship))
	var tuning: ShipTuning = LocalSession.load_tuning(SCRATCH_DIR.path_join("forge_ship.json"),
		SCRATCH_DIR)
	if tuning == null or tuning.loadout.weapon_ids() != ["forge_gun"]:
		return "the scratch ship did not load with the forge gun"
	var parts: Dictionary[String, WeaponDef] = LocalSession.load_parts(SCRATCH_DIR)
	var session: LocalSession = LocalSession.new(1, null, null, tuning, [], null, parts)
	if session.sim.part_ids() != ["forge_gun", "needle_gun"]:
		return "the session catalogue holds %s" % [session.sim.part_ids()]
	if session.sim.part("forge_gun") != tuning.loadout.primary_weapons[0]:
		return "the catalogue's forge gun is not the fitted one"
	if not session.replay.to_text().contains("\npart forge_gun "):
		return "the replay does not record the forge gun"
	if _sorted_ids(parts) != ["needle_gun"]:
		return "the caller's catalogue was changed to %s" % [_sorted_ids(parts)]
	return ""


func test_the_plain_ship_session_keeps_the_shipped_catalogue() -> String:
	var parts: Dictionary[String, WeaponDef] = LocalSession.load_parts()
	var session: LocalSession = LocalSession.new(1, null, null,
		LocalSession.load_tuning(SHIP_FILE), [], null, parts)
	if session.sim.part_ids() != WEAPON_IDS:
		return "the plain session catalogue holds %s" % [session.sim.part_ids()]
	return ""


func test_a_session_without_a_catalogue_stays_without_one() -> String:
	var session: LocalSession = LocalSession.new(1, null, null,
		LocalSession.load_tuning(SHIP_FILE))
	if not session.sim.part_ids().is_empty():
		return "a session without a catalogue gained %s" % [session.sim.part_ids()]
	return ""
