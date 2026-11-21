extends RefCounted

## The ship a run starts with: ship file, fitting and crew benefits in one pure
## step (CRF-4, CMB-1, CRW-1, CRW-3, ARC-2, #1054).

const SHIP_PATH: String = "res://data/ships/default_ship.json"
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


static func _roles() -> CrewRoles:
	return CrewRoles.parse_json(ROLES_TEXT)


static func _profile(crafted: Array[String], role_ids: Array[String] = []) -> Profile:
	var profile: Profile = Profile.new()
	profile.crafted = crafted
	for i: int in role_ids.size():
		profile.crew.append({Profile.CREW_ID: "crew-%d" % (i + 1), Profile.CREW_ROLE: role_ids[i]})
	return profile


static func _fitting(primary: Array[String], utility: Array[String] = []) -> Fitting:
	var fitting: Fitting = Fitting.new()
	fitting.primary = primary
	fitting.utility = utility
	return fitting


## "" when `data` passes `ShipTuning` and its loadout passes `ShipLoadout.from_data`.
static func _valid(data: Dictionary) -> String:
	var tuning: ShipTuning = ShipTuning.parse_json(JSON.stringify(data))
	if tuning.error != "":
		return "tuning: %s" % tuning.error
	var loadout: ShipLoadout = ShipLoadout.from_data(data.get(ShipTuning.LOADOUT_KEY, {}))
	if loadout.error != "":
		return "loadout: %s" % loadout.error
	return ""


func test_fixtures_load() -> String:
	var problems: String = _tree().error + _roles().error + _valid(_ship_data())
	return problems


func test_everything_null_gives_an_exact_copy() -> String:
	var data: Dictionary = _ship_data()
	var notes: Array[String] = []
	var built: Dictionary = RunStartShip.build(data, null, null, null, null, notes)
	if built != data or JSON.stringify(built) != JSON.stringify(data):
		return "built %s" % JSON.stringify(built)
	if not notes.is_empty():
		return "notes %s" % str(notes)
	built[ShipTuning.LOADOUT_KEY]["primary"][0] = "changed"
	if data[ShipTuning.LOADOUT_KEY]["primary"][0] != "pulse_cannon":
		return "the result shares data with the ship file"
	return ""


func test_a_fitted_crafted_weapon_replaces_primary_slot_1() -> String:
	var data: Dictionary = _ship_data()
	var before: String = JSON.stringify(data)
	var notes: Array[String] = []
	var built: Dictionary = RunStartShip.build(data, _fitting(["needle_gun", ""]), _tree(), _profile(["needle_gun"]), _roles(), notes)
	if built["loadout"]["primary"] != ["needle_gun", ""]:
		return "primary %s" % str(built["loadout"]["primary"])
	if not notes.is_empty():
		return "notes %s" % str(notes)
	if JSON.stringify(data) != before:
		return "ship data was changed"
	return _valid(built)


func test_a_fitted_look_aim_appears_in_the_utility_section() -> String:
	var data: Dictionary = _ship_data()
	var built: Dictionary = RunStartShip.build(data, _fitting(["", ""], ["look_aim"]), _tree(), _profile(["look_aim"]), null)
	if built["loadout"]["utility"] != ["look_aim"]:
		return "utility %s" % str(built["loadout"]["utility"])
	if built["loadout"]["primary"] != data["loadout"]["primary"]:
		return "primary changed to %s" % str(built["loadout"]["primary"])
	return _valid(built)


func test_an_uncrafted_upgrade_is_ignored_with_one_note_naming_the_slot() -> String:
	var data: Dictionary = _ship_data()
	var notes: Array[String] = []
	var built: Dictionary = RunStartShip.build(data, _fitting(["needle_gun", ""]), _tree(), _profile([]), _roles(), notes)
	if built != data:
		return "built %s" % JSON.stringify(built)
	if notes.size() != 1 or not notes[0].contains("primary[0]") or not notes[0].contains("needle_gun"):
		return "notes %s" % str(notes)
	return ""


func test_two_shield_crew_raise_max_shield_by_the_capped_total() -> String:
	var data: Dictionary = _ship_data()
	var notes: Array[String] = []
	var built: Dictionary = RunStartShip.build(data, null, null, _profile([], ["shield_tech", "shield_tech"]), _roles(), notes)
	# 10 + 10 is capped at 15.
	if not is_equal_approx(float(built["max_shield"]), float(data["max_shield"]) + 15.0):
		return "max_shield %s from %s" % [built["max_shield"], data["max_shield"]]
	if not notes.is_empty():
		return "notes %s" % str(notes)
	return _valid(built)


func test_an_unknown_crew_role_adds_a_note_and_nothing_else() -> String:
	var data: Dictionary = _ship_data()
	var notes: Array[String] = []
	var built: Dictionary = RunStartShip.build(data, null, null, _profile([], ["juggler"]), _roles(), notes)
	if built != data:
		return "built %s" % JSON.stringify(built)
	if notes.size() != 1 or not notes[0].contains("juggler"):
		return "notes %s" % str(notes)
	return ""


func test_same_inputs_give_the_same_dictionary_and_key_order() -> String:
	var first: Dictionary = RunStartShip.build(_ship_data(), _fitting(["needle_gun", ""], ["look_aim"]), _tree(), _profile(["needle_gun", "look_aim"], ["shield_tech"]), _roles())
	var second: Dictionary = RunStartShip.build(_ship_data(), _fitting(["needle_gun", ""], ["look_aim"]), _tree(), _profile(["needle_gun", "look_aim"], ["shield_tech"]), _roles())
	if JSON.stringify(first) != JSON.stringify(second) or str(first.keys()) != str(second.keys()):
		return "two builds differ"
	if str(first.keys()) != str(_ship_data().keys()):
		return "key order changed: %s" % str(first.keys())
	return _valid(first)


func test_a_null_tree_with_a_fitting_keeps_the_ship_file_loadout() -> String:
	var data: Dictionary = _ship_data()
	var notes: Array[String] = []
	var built: Dictionary = RunStartShip.build(data, _fitting(["needle_gun", ""]), null, _profile(["needle_gun"]), null, notes)
	if built != data or notes.size() != 1:
		return "built %s notes %s" % [JSON.stringify(built), str(notes)]
	return ""
