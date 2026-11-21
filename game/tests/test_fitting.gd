extends RefCounted

## Fitting crafted upgrades (CRF-4, CMB-1, ARC-2, #1012): the starting loadout is
## the ship file's plus the pilot's fitted upgrades, each refusal has one clear
## reason, and an empty fitting is exactly today's ship.

const SHIP_PATH: String = "res://data/ships/default_ship.json"
const WEAPONS_DIR: String = "res://data/weapons"


static func _ship_data() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(SHIP_PATH))


static func _tree() -> UpgradeTree:
	var texts: Dictionary = {}
	for file: String in DirAccess.get_files_at(UpgradeTree.UPGRADES_DIR):
		if file.ends_with(".json"):
			texts[file] = FileAccess.get_file_as_string(UpgradeTree.UPGRADES_DIR.path_join(file))
	return UpgradeTree.parse(texts)


static func _all_crafted(tree: UpgradeTree) -> Array[String]:
	var ids: Array[String] = []
	for upgrade: UpgradeDef in tree.upgrades:
		ids.append(upgrade.id)
	return ids


## A ship built the way a run builds it: tuning from the file, then the given
## loadout section resolved against the weapon files and equipped.
static func _ship(data: Dictionary, loadout_data: Dictionary) -> ShipState:
	var tuning: ShipTuning = ShipTuning.parse_json(JSON.stringify(data))
	var loadout: ShipLoadout = ShipLoadout.from_data(loadout_data)
	if tuning.error != "" or loadout.error != "":
		push_error("ship: %s %s" % [tuning.error, loadout.error])
		return null
	loadout.utility_slots = tuning.utility_slots
	var texts: Dictionary = {}
	for id: String in loadout.weapon_ids():
		texts[id] = FileAccess.get_file_as_string(WEAPONS_DIR.path_join(id + ".json"))
	if loadout.resolve(texts) != "":
		push_error("resolve failed")
		return null
	var ship: ShipState = ShipState.new()
	tuning.apply_to(ship)
	loadout.equip(ship)
	return ship


static func _fitting(primary: Array[String], secondary: Array[String] = ["", ""], utility: Array[String] = []) -> Fitting:
	var fitting: Fitting = Fitting.new()
	fitting.primary = primary
	fitting.secondary = secondary
	fitting.utility = utility
	return fitting


func test_the_shipped_tree_loads() -> String:
	return _tree().error


func test_a_fitted_weapon_replaces_primary_slot_1_and_is_equipped() -> String:
	var tree: UpgradeTree = _tree()
	var data: Dictionary = _ship_data()
	var fitting: Fitting = _fitting(["needle_gun", ""])
	var reason: String = Fitting.check(fitting, tree, ["needle_gun"], data)
	if reason != "":
		return "refused: %s" % reason
	var section: Dictionary = Fitting.loadout(fitting, tree, data)
	if section["primary"] != ["needle_gun", ""]:
		return "primary is %s" % [section["primary"]]
	if section["secondary"] != data["loadout"]["secondary"] or section["utility"] != data["loadout"]["utility"]:
		return "other slots changed: %s" % section
	if data["loadout"]["primary"] != ["pulse_cannon", ""]:
		return "ship data was changed"
	var ship: ShipState = _ship(data, section)
	if ship == null:
		return "loadout did not build a ship"
	var needle: WeaponDef = WeaponDef.parse_json(FileAccess.get_file_as_string(WEAPONS_DIR.path_join("needle_gun.json")))
	if ship.primary_ids[0] != "needle_gun" or ship.primary_slots[0] == null or ship.primary_slots[0].values_hash() != needle.values_hash():
		return "ship carries %s" % [ship.primary_ids]
	return ""


func test_a_fitted_weapon_in_the_empty_slot_2_keeps_slot_1() -> String:
	var tree: UpgradeTree = _tree()
	var data: Dictionary = _ship_data()
	var fitting: Fitting = _fitting(["", "slug_thrower"])
	var reason: String = Fitting.check(fitting, tree, ["slug_thrower"], data)
	if reason != "":
		return reason
	var section: Dictionary = Fitting.loadout(fitting, tree, data)
	if section["primary"] != ["pulse_cannon", "slug_thrower"]:
		return "primary is %s" % [section["primary"]]
	return ""


func test_an_empty_fitting_keeps_the_ship_hash() -> String:
	var tree: UpgradeTree = _tree()
	var data: Dictionary = _ship_data()
	var fitting: Fitting = Fitting.new()
	if Fitting.check(fitting, tree, [], data) != "":
		return "an empty fitting was refused"
	var section: Dictionary = Fitting.loadout(fitting, tree, data)
	if section != data["loadout"]:
		return "section %s" % section
	var today: ShipState = _ship(data, data["loadout"])
	var fitted: ShipState = _ship(data, section)
	if today == null or fitted == null or today.state_hash() != fitted.state_hash():
		return "hash changed"
	return ""


func test_same_inputs_give_the_same_loadout() -> String:
	var fitting: Fitting = _fitting(["arc_lance", "needle_gun"])
	var first: Dictionary = Fitting.loadout(fitting, _tree(), _ship_data())
	var second: Dictionary = Fitting.loadout(Fitting.parse_json(fitting.to_json()), _tree(), _ship_data())
	if first != second or JSON.stringify(first, "", true) != JSON.stringify(second, "", true):
		return "%s vs %s" % [first, second]
	var a: ShipState = _ship(_ship_data(), first)
	var b: ShipState = _ship(_ship_data(), second)
	if a == null or b == null or a.state_hash() != b.state_hash():
		return "hashes differ"
	return ""


func _refused(fitting: Fitting, crafted: Array[String], expected: String, data: Dictionary = _ship_data()) -> String:
	var reason: String = Fitting.check(fitting, _tree(), crafted, data)
	if reason != expected:
		return "reason '%s', expected '%s'" % [reason, expected]
	return ""


func test_refused_when_not_crafted() -> String:
	return _refused(_fitting(["needle_gun", ""]), ["slug_thrower"],
		"primary[0]: \"needle_gun\" is not crafted")


func test_refused_for_an_unknown_upgrade() -> String:
	return _refused(_fitting(["warp_gun", ""]), _all_crafted(_tree()),
		"primary[0]: unknown upgrade \"warp_gun\"")


func test_refused_for_a_module_in_a_weapon_slot() -> String:
	return _refused(_fitting(["mine_scanner", ""]), _all_crafted(_tree()),
		"primary[0]: \"mine_scanner\" is a module, only a weapon fits a primary slot")


func test_refused_for_a_weapon_in_a_utility_slot() -> String:
	return _refused(_fitting(["", ""], ["", ""], ["needle_gun"]), _all_crafted(_tree()),
		"utility[0]: \"needle_gun\" is a weapon, only a module fits a utility slot")


func test_refused_for_a_weapon_in_a_secondary_slot() -> String:
	return _refused(_fitting(["", ""], ["needle_gun", ""]), _all_crafted(_tree()),
		"secondary[0]: \"needle_gun\" cannot go in a secondary slot: there are no secondary weapons yet")


func test_refused_for_a_slot_the_ship_does_not_have() -> String:
	var data: Dictionary = _ship_data()
	data["utility_slots"] = 1
	return _refused(_fitting(["", ""], ["", ""], ["", "mine_scanner"]), _all_crafted(_tree()),
		"utility[1] does not exist: the ship has 1 utility slots", data)


func test_refused_for_the_same_upgrade_in_two_slots() -> String:
	return _refused(_fitting(["needle_gun", "needle_gun"]), ["needle_gun"],
		"primary[1]: \"needle_gun\" is already fitted in primary[0]")


func test_shield_hull_and_engine_are_not_fittable_yet() -> String:
	var crafted: Array[String] = _all_crafted(_tree())
	for id: String in ["lattice_shield", "layered_plating", "tuned_thrusters"]:
		var reason: String = Fitting.check(_fitting(["", ""], ["", ""], [id]), _tree(), crafted, _ship_data())
		if not reason.ends_with("not fittable yet") or not reason.contains(id):
			return "%s: '%s'" % [id, reason]
	return ""


func test_a_module_the_simulation_does_not_know_is_not_fittable_yet() -> String:
	# Fitting one would build a loadout the run rejects, so it is refused here first.
	for id: String in ["mine_scanner", "wide_radar"]:
		var reason: String = Fitting.check(_fitting(["", ""], ["", ""], [id]), _tree(), _all_crafted(_tree()), _ship_data())
		if not reason.begins_with("utility[0]: \"%s\" grants module" % id) or not reason.ends_with("not fittable yet"):
			return "%s: '%s'" % [id, reason]
	return ""


func test_the_crafted_look_aim_module_fits_and_is_equipped() -> String:
	var tree: UpgradeTree = _tree()
	var fitting: Fitting = _fitting(["", ""], ["", ""], ["look_aim"])
	var reason: String = Fitting.check(fitting, tree, ["look_aim"], _ship_data())
	if reason != "":
		return "look_aim refused: " + reason
	var section: Dictionary = Fitting.loadout(fitting, tree, _ship_data())
	var ship: ShipState = _ship(_ship_data(), section)
	if ship == null or ship.utility_slots != (["look_aim", ""] as Array[String]):
		return "fitted look_aim equipped %s" % ["nothing" if ship == null else str(ship.utility_slots)]
	var uncrafted: String = Fitting.check(fitting, tree, [], _ship_data())
	if uncrafted != "utility[0]: \"look_aim\" is not crafted":
		return "an uncrafted look_aim gave '%s'" % uncrafted
	return ""


func test_json_round_trip() -> String:
	var fitting: Fitting = _fitting(["", "needle_gun"], ["", ""], ["", "mine_scanner"])
	var text: String = fitting.to_json()
	var read: Fitting = Fitting.parse_json(text)
	if read.error != "" or read.to_json() != text:
		return "read back '%s': %s" % [read.error, read.to_json()]
	if read.primary != ["", "needle_gun"] or read.utility != ["", "mine_scanner"]:
		return "fields %s %s" % [read.primary, read.utility]
	return ""


func test_parse_errors_name_the_key() -> String:
	var cases: Array = [
		["{\"primary\": [\"\", \"\"], \"secondary\": [\"\", \"\"], \"utility\": [], \"hull\": []}", "unknown key \"hull\""],
		["{\"primary\": [\"\", \"\"], \"secondary\": [\"\", \"\"]}", "missing key \"utility\""],
		["{\"primary\": \"needle_gun\", \"secondary\": [], \"utility\": []}", "key \"primary\" must be a list"],
		["{\"primary\": [\"a\", \"b\", \"c\"], \"secondary\": [], \"utility\": []}", "key \"primary\" has 3 slots, at most 2"],
		["{\"primary\": [3], \"secondary\": [], \"utility\": []}", "key \"primary[0]\" must be a string"],
		["{\"primary\": [\"Bad Id\"], \"secondary\": [], \"utility\": []}", "key \"primary[0]\" is \"Bad Id\""],
		["[]", "top level must be a JSON object"],
	]
	for case: Array in cases:
		var read: Fitting = Fitting.parse_json(case[0])
		if not read.error.begins_with(case[1]):
			return "'%s' gave '%s'" % [case[0], read.error]
		if not read.is_empty():
			return "a rejected fitting is not empty"
	return ""
