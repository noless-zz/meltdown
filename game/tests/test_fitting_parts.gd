extends RefCounted

## Shield, hull and engine part slots (CRF-4, CRF-3, SLV-2, CRW-3, ARC-1, #1055):
## each part kind fits only its own slot, old fitting files still read, and the
## ship a run starts with carries the fitted parts' multipliers before the
## crew's benefits, inside `ShipTuning.RANGES`.

const SHIP_PATH: String = "res://data/ships/default_ship.json"
const DIR: String = "user://test_fitting_parts"
## A fixed copy of the roles, so the numbers below do not move when the
## shipped roles file is tuned.
const ROLES_TEXT: String = """{"roles": [
	{"id": "surveyor", "name": "Surveyor", "weight": 30, "benefit": {"stat": "map_reveal", "amount": 1}},
	{"id": "shield_tech", "name": "Shield Technician", "weight": 25, "benefit": {"stat": "shield_max", "amount": 10}},
	{"id": "cargo_rigger", "name": "Cargo Rigger", "weight": 25, "benefit": {"stat": "salvage_slots", "amount": 1}},
	{"id": "reactor_hand", "name": "Reactor Hand", "weight": 20, "benefit": {"stat": "meltdown_seconds", "amount": 5}}
], "caps": {"map_reveal": 1, "meltdown_seconds": 20, "salvage_slots": 2, "shield_max": 15}}"""


static func _ship_data() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(SHIP_PATH))


static func _tree() -> UpgradeTree:
	var texts: Dictionary = {}
	for file: String in DirAccess.get_files_at(UpgradeTree.UPGRADES_DIR):
		if file.ends_with(".json"):
			texts[file] = FileAccess.get_file_as_string(UpgradeTree.UPGRADES_DIR.path_join(file))
	return UpgradeTree.parse(texts)


static func _all_crafted() -> Array[String]:
	var ids: Array[String] = []
	for upgrade: UpgradeDef in _tree().upgrades:
		ids.append(upgrade.id)
	return ids


static func _profile(crew_roles: Array[String] = []) -> Profile:
	var profile: Profile = Profile.new()
	profile.crafted = _all_crafted()
	for i: int in crew_roles.size():
		profile.crew.append({Profile.CREW_ID: "crew-%d" % (i + 1), Profile.CREW_ROLE: crew_roles[i]})
	return profile


static func _parts(shield: String, hull: String, engine: String) -> Fitting:
	var fitting: Fitting = Fitting.new()
	fitting.parts = {"shield": shield, "hull": hull, "engine": engine}
	return fitting


static func _multiplier(part_id: String, stat: String) -> float:
	var file: String = part_id + ".json"
	var part: ShipPartDef = ShipPartDef.parse_json(
		FileAccess.get_file_as_string(ShipPartDef.PARTS_DIR.path_join(file)), file)
	return part.stats[stat]


func test_layered_plating_raises_max_hull_by_its_multiplier() -> String:
	var notes: Array[String] = []
	var ship: Dictionary = RunStartShip.build(_ship_data(), _parts("", "layered_plating", ""), _tree(), _profile(), null, notes)
	var expected: float = float(_ship_data()["max_hull"]) * _multiplier("layered_plating", "max_hull")
	if not notes.is_empty():
		return "notes %s" % [notes]
	if not is_equal_approx(float(ship["max_hull"]), expected) or expected == float(_ship_data()["max_hull"]):
		return "max_hull %s, expected %s" % [ship["max_hull"], expected]
	return ""


func test_each_part_fits_its_own_slot() -> String:
	var fitting: Fitting = _parts("lattice_shield", "ribbed_frame", "tuned_thrusters")
	var reason: String = Fitting.check(fitting, _tree(), _all_crafted(), _ship_data())
	return reason


func test_a_shield_upgrade_in_the_hull_slot_is_refused_naming_hull() -> String:
	var reason: String = Fitting.check(_parts("", "lattice_shield", ""), _tree(), _all_crafted(), _ship_data())
	if not reason.begins_with("hull: ") or not reason.contains("lattice_shield") or not reason.contains("hull slot"):
		return "reason '%s'" % reason
	return ""


func test_a_weapon_in_a_part_slot_and_a_part_in_a_weapon_slot_are_refused() -> String:
	var weapon: String = Fitting.check(_parts("needle_gun", "", ""), _tree(), _all_crafted(), _ship_data())
	if not weapon.begins_with("shield: \"needle_gun\" is kind weapon"):
		return "weapon in shield slot: '%s'" % weapon
	var in_primary: Fitting = Fitting.new()
	in_primary.primary = ["tuned_thrusters", ""]
	var part: String = Fitting.check(in_primary, _tree(), _all_crafted(), _ship_data())
	if not part.begins_with("primary[0]: \"tuned_thrusters\" is kind engine, it fits only the engine slot"):
		return "engine in primary slot: '%s'" % part
	var uncrafted: String = Fitting.check(_parts("", "layered_plating", ""), _tree(), [], _ship_data())
	if uncrafted != "hull: \"layered_plating\" is not crafted":
		return "uncrafted: '%s'" % uncrafted
	return ""


func test_parts_and_crew_together_stay_inside_the_ranges() -> String:
	var data: Dictionary = _ship_data()
	var top: float = float(ShipTuning.RANGES["max_shield"][1])
	data["max_shield"] = top - 5.0
	var fitting: Fitting = _parts("glass_core_shield", "fused_bulkhead", "torsion_drive")
	var notes: Array[String] = []
	var ship: Dictionary = RunStartShip.build(data, fitting, _tree(), _profile(["shield_tech", "shield_tech"]),
		CrewRoles.parse_json(ROLES_TEXT), notes)
	if not notes.is_empty():
		return "notes %s" % [notes]
	if float(ship["max_shield"]) != top:
		return "max_shield %s, want the cap %s" % [ship["max_shield"], top]
	var tuning: ShipTuning = ShipTuning.parse_json(JSON.stringify(ship))
	if tuning.error != "":
		return "built ship does not parse: %s" % tuning.error
	return ""


func test_same_inputs_give_the_same_ship_data() -> String:
	var fitting: Fitting = _parts("baffled_emitter", "ribbed_frame", "swept_intakes")
	var roles: CrewRoles = CrewRoles.parse_json(ROLES_TEXT)
	var a: Dictionary = RunStartShip.build(_ship_data(), fitting, _tree(), _profile(["shield_tech"]), roles)
	var b: Dictionary = RunStartShip.build(_ship_data(), fitting, _tree(), _profile(["shield_tech"]), roles)
	if JSON.stringify(a) != JSON.stringify(b):
		return "two builds differ"
	if JSON.stringify(a) == JSON.stringify(_ship_data()):
		return "the parts changed nothing"
	return ""


func test_a_part_file_that_fails_to_load_is_skipped_with_a_note() -> String:
	var dir: String = ProjectSettings.globalize_path(DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var out: FileAccess = FileAccess.open(dir.path_join("layered_plating.json"), FileAccess.WRITE)
	out.store_string("{ broken")
	out.close()
	var notes: Array[String] = []
	var fitting: Fitting = _parts("", "layered_plating", "tuned_thrusters")
	var ship: Dictionary = RunStartShip.build(_ship_data(), fitting, _tree(), _profile(), null, notes, DIR)
	DirAccess.remove_absolute(dir.path_join("layered_plating.json"))
	if notes.size() != 2 or not notes[0].begins_with("part layered_plating skipped") \
			or not notes[1].begins_with("part tuned_thrusters skipped"):
		return "notes %s" % [notes]
	if float(ship["max_hull"]) != float(_ship_data()["max_hull"]):
		return "a broken part still changed max_hull"
	return ""


func test_json_round_trip_keeps_the_parts() -> String:
	var fitting: Fitting = _parts("lattice_shield", "", "tuned_thrusters")
	fitting.primary = ["", "needle_gun"]
	var read: Fitting = Fitting.parse_json(fitting.to_json())
	if read.error != "" or read.to_json() != fitting.to_json():
		return "read back '%s': %s" % [read.error, read.to_json()]
	if read.parts != fitting.parts or read.part_ids() != (["lattice_shield", "tuned_thrusters"] as Array[String]):
		return "parts %s" % [read.parts]
	return ""


func test_part_parse_errors_name_the_key() -> String:
	var base: String = "\"primary\": [\"\", \"\"], \"secondary\": [\"\", \"\"], \"utility\": []"
	var cases: Array = [
		["{%s, \"parts\": []}" % base, "key \"parts\" must be an object"],
		["{%s, \"parts\": {\"cargo\": \"\"}}" % base, "key \"parts\" has unknown slot \"cargo\""],
		["{%s, \"parts\": {\"hull\": 3}}" % base, "key \"parts.hull\" must be a string"],
	]
	for case: Array in cases:
		var read: Fitting = Fitting.parse_json(case[0])
		if read.error != case[1] or not read.is_empty():
			return "%s gave '%s'" % [case[0], read.error]
	return ""


func test_a_version_1_file_loads_with_empty_part_slots() -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var store: FittingStore = FittingStore.new(DIR + "/meltdown_fitting.json")
	var out: FileAccess = FileAccess.open(store.path, FileAccess.WRITE)
	out.store_string("{\"version\": 1, \"fitting\": {\"primary\": [\"needle_gun\", \"\"], \"secondary\": [\"\", \"\"], \"utility\": []}}")
	out.close()
	var read: Fitting = store.load_fitting()
	DirAccess.remove_absolute(store.path)
	if store.message != "" or store.locked:
		return "message '%s', locked %s" % [store.message, store.locked]
	if read.primary != (["needle_gun", ""] as Array[String]) or not read.part_ids().is_empty():
		return "read %s" % read.to_json()
	return ""


func test_a_stale_part_is_dropped_and_a_good_one_kept() -> String:
	var fitting: Fitting = _parts("lattice_shield", "gone_plating", "")
	var notes: Array[String] = []
	var kept: Fitting = FittingStore.valid_for(fitting, _tree(), _all_crafted(), _ship_data(), notes)
	if kept.parts != ({"shield": "lattice_shield", "hull": "", "engine": ""} as Dictionary[String, String]):
		return "kept %s" % [kept.parts]
	if notes != (["dropped hull: unknown upgrade \"gone_plating\""] as Array[String]):
		return "notes %s" % [notes]
	return ""
