extends RefCounted

## The hub's fit page and launch (CRF-4, CRW-1, MP-2, ARC-4, #1033): fits and
## refusals pass the fitting check's reasons through unchanged, part slots
## follow the weapon and utility slots, and a launch gives the fitted loadout.
## Split from `test_hub_model.gd` (#1286), whose fixtures it uses.

const Hub := preload("res://tests/test_hub_model.gd")
const ROLES_PATH: String = Hub.ROLES_PATH


func test_fit_then_launch_gives_a_loadout_that_equips_the_upgrade() -> String:
	var profile: Profile = Hub.rich_profile()
	var model: HubModel = Hub.new_model(profile)
	for id: String in ["needle_gun", "look_aim"]:
		var crafted: String = model.craft(id)
		if crafted != "":
			return "craft %s: %s" % [id, crafted]
	var reason: String = model.fit("primary[0]", "needle_gun")
	if reason == "":
		reason = model.fit("utility[0]", "look_aim")
	if reason != "":
		return "fit refused: %s" % reason
	var section: Dictionary = model.launch()
	if section.get("primary") != ["needle_gun", ""] or section.get("utility") != ["look_aim"]:
		return "launch gave %s" % section
	if section != Fitting.loadout(model.fitting, model.tree, Hub.ship_data()):
		return "launch is not Fitting.loadout"
	var loadout: ShipLoadout = ShipLoadout.from_data(section)
	if loadout.error != "":
		return "loadout rejected: %s" % loadout.error
	var slots: Array[Dictionary] = model.fit_slots()
	if slots.size() != 9 or slots[0]["upgrade"] != "needle_gun" or slots[0]["part"] != "pulse_cannon":
		return "fit page is %s" % [slots]
	if slots[4]["slot"] != "utility[0]" or slots[4]["upgrade"] != "look_aim":
		return "utility row is %s" % slots[4]
	if model.fit("utility[0]", "") != "" or model.fitting.utility != []:
		return "emptying the utility slot left %s" % [model.fitting.utility]
	return ""


func test_an_empty_fitting_launches_the_ship_files_loadout() -> String:
	var model: HubModel = Hub.new_model()
	if model.launch() != Hub.ship_data()["loadout"]:
		return "launch gave %s" % model.launch()
	return ""


func test_refusals_pass_through_unchanged() -> String:
	var profile: Profile = Profile.new()
	var model: HubModel = Hub.new_model(profile)
	var reason: String = model.craft("needle_gun")
	if reason == "" or reason != model.tree.missing("needle_gun", [], {}):
		return "short craft gave %s" % reason
	var unknown: String = model.craft("no_such_thing")
	var expected: String = Crafting.craft(Profile.new(), model.tree, "no_such_thing")
	if unknown != expected:
		return "unknown craft gave %s, Crafting says %s" % [unknown, expected]
	var cases: Array = [["primary[0]", "needle_gun"], ["secondary[0]", "needle_gun"], ["utility[3]", "look_aim"]]
	profile.crafted.append_array(["look_aim"])
	for case: Array in cases:
		var fitting: Fitting = Fitting.new()
		var ids: Array[String] = fitting.ids_of(case[0].get_slice("[", 0))
		var index: int = int(case[0].get_slice("[", 1).trim_suffix("]"))
		while ids.size() <= index:
			ids.append("")
		ids[index] = case[1]
		var direct: String = Fitting.check(fitting, model.tree, profile.crafted, Hub.ship_data())
		var through: String = model.fit(case[0], case[1])
		if direct == "" or through != direct:
			return "%s gave \"%s\", Fitting.check says \"%s\"" % [case, through, direct]
	if not model.fitting.is_empty():
		return "a refused fit changed the fitting: %s" % model.fitting.to_json()
	if model.fit("cargo[0]", "look_aim") == "" or model.fit("primary[2]", "look_aim") == "":
		return "a slot that does not exist was accepted"
	return ""


func test_the_part_slots_follow_the_weapon_and_utility_slots() -> String:
	var model: HubModel = Hub.new_model()
	var slots: Array[Dictionary] = model.fit_slots()
	var tail: Array = slots.slice(slots.size() - 3).map(func(row: Dictionary) -> Array:
		return [row["slot"], row["kind"], row["upgrade"], row["part"]])
	if tail != [["shield", "shield", "", ""], ["hull", "hull", "", ""], ["engine", "engine", "", ""]]:
		return "the last three slots are %s" % [tail]
	for row: Dictionary in slots.slice(0, slots.size() - 3):
		if not Fitting.KEYS.has(row["kind"]):
			return "a part slot comes before a weapon or utility slot: %s" % row
	return ""


func test_a_crafted_shield_part_is_fitted_and_the_launched_ship_carries_it() -> String:
	var profile: Profile = Hub.rich_profile()
	var model: HubModel = Hub.new_model(profile)
	if model.craft("shield_capacitor") != "":
		return "could not craft shield_capacitor"
	var reason: String = model.fit("shield", "shield_capacitor")
	if reason != "":
		return "fit refused: %s" % reason
	if model.fitting.parts["shield"] != "shield_capacitor" or model.fit_slots()[-3]["upgrade"] != "shield_capacitor":
		return "the shield slot holds %s" % model.fitting.parts
	if model.launch_check() != "" or model.launch().is_empty():
		return "a fitting with a shield part cannot launch: %s" % model.launch_check()
	var roles: CrewRoles = CrewRoles.parse_json(FileAccess.get_file_as_string(ROLES_PATH))
	var stock: Dictionary = RunStartShip.build(Hub.ship_data(), Fitting.new(), model.tree, profile, roles)
	var fitted: Dictionary = RunStartShip.build(Hub.ship_data(), model.fitting, model.tree, profile, roles)
	if fitted == stock:
		return "the launched ship is the stock ship"
	if model.fit("shield", "") != "" or model.fitting.parts["shield"] != "":
		return "emptying the shield slot left %s" % model.fitting.parts
	return ""


func test_a_part_of_another_kind_is_refused_with_the_checks_reason() -> String:
	var profile: Profile = Hub.rich_profile()
	var model: HubModel = Hub.new_model(profile)
	if model.craft("layered_plating") != "":
		return "could not craft layered_plating"
	var direct: Fitting = Fitting.new()
	direct.parts["shield"] = "layered_plating"
	var expected: String = Fitting.check(direct, model.tree, profile.crafted, Hub.ship_data())
	var reason: String = model.fit("shield", "layered_plating")
	if expected == "" or reason != expected:
		return "fit gave \"%s\", Fitting.check says \"%s\"" % [reason, expected]
	if not model.fitting.is_empty():
		return "a refused part fit changed the fitting: %s" % model.fitting.to_json()
	if model.fit("primary[0]", "layered_plating") == "":
		return "a hull part went in a weapon slot"
	return ""


func test_a_weapon_fit_keeps_a_fitted_part() -> String:
	var profile: Profile = Hub.rich_profile()
	var model: HubModel = Hub.new_model(profile)
	for id: String in ["needle_gun", "layered_plating"]:
		if model.craft(id) != "":
			return "could not craft %s" % id
	if model.fit("hull", "layered_plating") != "":
		return "hull fit refused"
	var reason: String = model.fit("primary[0]", "needle_gun")
	if reason != "":
		return "weapon fit refused: %s" % reason
	if model.fitting.primary[0] != "needle_gun" or model.fitting.parts["hull"] != "layered_plating":
		return "after the weapon fit: %s" % model.fitting.to_json()
	if model.launch().get("primary") != ["needle_gun", ""]:
		return "launch gave %s" % model.launch()
	return ""
