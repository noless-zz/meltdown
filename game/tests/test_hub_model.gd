extends RefCounted

## The hub's model (CRW-2, CRF-3, CRF-4, CRW-1, MP-2, ARC-4, #1033): four pages
## from data, craft and fit that pass their reasons through unchanged, and a
## launch that gives the fitted loadout. Built on the shipped data files.

const SHIP_PATH: String = "res://data/ships/default_ship.json"
const ROLES_PATH: String = "res://data/crew/roles.json"


static func _texts(dir: String) -> Dictionary:
	var texts: Dictionary = {}
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".json"):
			texts[file] = FileAccess.get_file_as_string(dir.path_join(file))
	return texts


static func _ship_data() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(SHIP_PATH))


static func _model(profile: Profile = Profile.new(), fitting: Fitting = Fitting.new()) -> HubModel:
	return HubModel.create(
		HubConfig.load_shipped(),
		profile,
		CrewRoles.parse_json(FileAccess.get_file_as_string(ROLES_PATH)),
		ComponentList.parse(_texts(ComponentList.COMPONENTS_DIR)),
		UpgradeTree.parse(_texts(UpgradeTree.UPGRADES_DIR)),
		fitting,
		_ship_data())


## Enough of every component kind to craft anything in the shipped tree.
static func _rich_profile() -> Profile:
	var profile: Profile = Profile.new()
	profile.bank({"scrap_alloy": 20, "cell_salts": 20, "circuit_shards": 20, "core_glass": 20})
	return profile


func test_the_shipped_data_loads() -> String:
	var model: HubModel = _model()
	for problem: String in [model.config.error, model.roles.error, model.components.error, model.tree.error]:
		if problem != "":
			return problem
	return ""


func test_pages_come_in_the_file_order_with_their_titles() -> String:
	var model: HubModel = _model()
	if model.pages() != ["crew", "store", "craft", "fit"]:
		return "pages are %s" % [model.pages()]
	for id: String in model.pages():
		if model.page_title(id) == "":
			return "page %s has no title" % id
	var config: HubConfig = HubConfig.parse_json(JSON.stringify({
		"pages": [{"id": "fit", "title": "F"}, {"id": "craft", "title": "C"},
			{"id": "store", "title": "S"}, {"id": "crew", "title": "W"}],
		"empty_crew": "none", "empty_store": "none",
	}))
	if config.error != "" or config.pages != ["fit", "craft", "store", "crew"] or config.title("crew") != "W":
		return "reordered file read as %s (%s)" % [config.pages, config.error]
	return ""


func test_an_empty_profile_lists_no_crew_an_empty_store_and_locked_tier_1() -> String:
	var model: HubModel = _model()
	if not model.crew().is_empty() or not model.store().is_empty():
		return "crew %s store %s" % [model.crew(), model.store()]
	if model.config.empty_crew == "" or model.config.empty_store == "":
		return "empty-page texts are missing"
	if not model.craftable().is_empty() or not model.crafted().is_empty():
		return "craftable %s crafted %s" % [model.craftable(), model.crafted()]
	var locked_ids: Array[String] = []
	for row: Dictionary in model.locked():
		locked_ids.append(row["id"])
		if row["reason"] != model.tree.missing(row["id"], [], {}):
			return "%s shows a reason of its own: %s" % [row["id"], row["reason"]]
	for upgrade: UpgradeDef in model.tree.upgrades:
		if not locked_ids.has(upgrade.id):
			return "%s is not listed as locked" % upgrade.id
		if upgrade.tier == 1 and not model.tree.missing(upgrade.id, [], {}).contains("short of"):
			return "tier-1 %s is not locked for lack of components" % upgrade.id
	return ""


func test_crew_shows_each_members_role_name_and_benefit() -> String:
	var profile: Profile = Profile.new()
	profile.crew.append({"id": "crew-1", "role": "shield_tech"})
	profile.crew.append({"id": "crew-2", "role": "surveyor"})
	var rows: Array[Dictionary] = _model(profile).crew()
	if rows.size() != 2 or rows[0]["id"] != "crew-1" or rows[1]["id"] != "crew-2":
		return "rows %s" % [rows]
	if rows[0]["role_name"] != "Shield Technician" or rows[0]["stat"] != "shield_max" or rows[0]["amount"] != 5:
		return "shield tech shows %s" % rows[0]
	if rows[1]["role_name"] != "Surveyor" or rows[1]["stat"] != "map_reveal":
		return "surveyor shows %s" % rows[1]
	return ""


func test_store_lists_banked_kinds_by_tier_with_names() -> String:
	var profile: Profile = Profile.new()
	profile.bank({"core_glass": 1, "scrap_alloy": 4, "cell_salts": 2})
	var rows: Array[Dictionary] = _model(profile).store()
	var seen: Array = rows.map(func(row: Dictionary) -> String: return "%s:%d:%d" % [row["id"], row["tier"], row["count"]])
	if seen != ["cell_salts:1:2", "scrap_alloy:1:4", "core_glass:3:1"]:
		return "store is %s" % [seen]
	if rows[0]["name"] != "Cell Salts":
		return "name is %s" % rows[0]["name"]
	return ""


func test_craft_moves_an_upgrade_from_locked_to_crafted_and_lowers_the_store() -> String:
	var profile: Profile = Profile.new()
	var model: HubModel = _model(profile)
	profile.bank({"scrap_alloy": 3, "cell_salts": 2})
	if not model.craftable().has("needle_gun"):
		return "needle_gun is not craftable after banking: %s" % [model.craftable()]
	var reason: String = model.craft("needle_gun")
	if reason != "":
		return "craft refused: %s" % reason
	if model.crafted() != ["needle_gun"] or model.craftable().has("needle_gun"):
		return "crafted %s craftable %s" % [model.crafted(), model.craftable()]
	for row: Dictionary in model.locked():
		if row["id"] == "needle_gun":
			return "needle_gun is still locked"
	if not model.store().is_empty():
		return "store after spending everything is %s" % [model.store()]
	return ""


func test_fit_then_launch_gives_a_loadout_that_equips_the_upgrade() -> String:
	var profile: Profile = _rich_profile()
	var model: HubModel = _model(profile)
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
	if section != Fitting.loadout(model.fitting, model.tree, _ship_data()):
		return "launch is not Fitting.loadout"
	var loadout: ShipLoadout = ShipLoadout.from_data(section)
	if loadout.error != "":
		return "loadout rejected: %s" % loadout.error
	var slots: Array[Dictionary] = model.fit_slots()
	if slots.size() != 6 or slots[0]["upgrade"] != "needle_gun" or slots[0]["part"] != "pulse_cannon":
		return "fit page is %s" % [slots]
	if slots[4]["slot"] != "utility[0]" or slots[4]["upgrade"] != "look_aim":
		return "utility row is %s" % slots[4]
	if model.fit("utility[0]", "") != "" or model.fitting.utility != []:
		return "emptying the utility slot left %s" % [model.fitting.utility]
	return ""


func test_an_empty_fitting_launches_the_ship_files_loadout() -> String:
	var model: HubModel = _model()
	if model.launch() != _ship_data()["loadout"]:
		return "launch gave %s" % model.launch()
	return ""


func test_refusals_pass_through_unchanged() -> String:
	var profile: Profile = Profile.new()
	var model: HubModel = _model(profile)
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
		var direct: String = Fitting.check(fitting, model.tree, profile.crafted, _ship_data())
		var through: String = model.fit(case[0], case[1])
		if direct == "" or through != direct:
			return "%s gave \"%s\", Fitting.check says \"%s\"" % [case, through, direct]
	if not model.fitting.is_empty():
		return "a refused fit changed the fitting: %s" % model.fitting.to_json()
	if model.fit("cargo[0]", "look_aim") == "" or model.fit("primary[2]", "look_aim") == "":
		return "a slot that does not exist was accepted"
	return ""


func test_the_model_never_changes_the_callers_ship_data() -> String:
	var data: Dictionary = _ship_data()
	var profile: Profile = _rich_profile()
	var model: HubModel = HubModel.create(HubConfig.load_shipped(), profile,
		CrewRoles.parse_json(FileAccess.get_file_as_string(ROLES_PATH)),
		ComponentList.parse(_texts(ComponentList.COMPONENTS_DIR)),
		UpgradeTree.parse(_texts(UpgradeTree.UPGRADES_DIR)), Fitting.new(), data)
	model.craft("needle_gun")
	model.fit("primary[0]", "needle_gun")
	model.launch()
	if data != _ship_data():
		return "ship data changed to %s" % data
	return ""


func test_config_errors_name_the_key() -> String:
	var good: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(HubConfig.CONFIG_PATH))
	var cases: Dictionary = {
		"missing key \"empty_store\"": func(d: Dictionary) -> void: d.erase("empty_store"),
		"unknown key \"extra\"": func(d: Dictionary) -> void: d["extra"] = 1,
		"is missing page \"fit\"": func(d: Dictionary) -> void: (d["pages"] as Array).remove_at(3),
		"repeats page \"crew\"": func(d: Dictionary) -> void: d["pages"][1]["id"] = "crew",
		"\"pages[2].id\" must be one of": func(d: Dictionary) -> void: d["pages"][2]["id"] = "bar",
		"\"pages[0].title\" must be a non-empty string": func(d: Dictionary) -> void: d["pages"][0]["title"] = " ",
		"\"empty_crew\" must be a non-empty string": func(d: Dictionary) -> void: d["empty_crew"] = 3,
	}
	for expected: String in cases:
		var data: Dictionary = good.duplicate(true)
		(cases[expected] as Callable).call(data)
		var config: HubConfig = HubConfig.parse_json(JSON.stringify(data))
		if not config.error.contains(expected):
			return "expected \"%s\", got \"%s\"" % [expected, config.error]
		if not config.pages.is_empty():
			return "a rejected config kept pages"
	return ""
