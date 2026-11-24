extends RefCounted

## The hub's model (CRW-2, CRF-3, CRF-4, CRW-1, MP-2, ARC-4, #1033): four pages
## from data, craft and fit that pass their reasons through unchanged, and a
## launch that gives the fitted loadout. Built on the shipped data files.
## The fit page and launch checks are in `test_hub_model_fitting.gd`; the
## fixtures below are public so it can share them (#1286).

const SHIP_PATH: String = "res://data/ships/default_ship.json"
const ROLES_PATH: String = "res://data/crew/roles.json"


static func shipped_texts(dir: String) -> Dictionary:
	var texts: Dictionary = {}
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".json"):
			texts[file] = FileAccess.get_file_as_string(dir.path_join(file))
	return texts


static func ship_data() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(SHIP_PATH))


static func new_model(profile: Profile = Profile.new(), fitting: Fitting = Fitting.new()) -> HubModel:
	return HubModel.create(
		HubConfig.load_shipped(),
		profile,
		CrewRoles.parse_json(FileAccess.get_file_as_string(ROLES_PATH)),
		ComponentList.parse(shipped_texts(ComponentList.COMPONENTS_DIR)),
		UpgradeTree.parse(shipped_texts(UpgradeTree.UPGRADES_DIR)),
		fitting,
		ship_data())


## Enough of every component kind to craft anything in the shipped tree.
static func rich_profile() -> Profile:
	var profile: Profile = Profile.new()
	profile.bank({"scrap_alloy": 20, "cell_salts": 20, "circuit_shards": 20, "core_glass": 20})
	return profile


func test_the_shipped_data_loads() -> String:
	var model: HubModel = new_model()
	for problem: String in [model.config.error, model.roles.error, model.components.error, model.tree.error]:
		if problem != "":
			return problem
	return ""


func test_pages_come_in_the_file_order_with_their_titles() -> String:
	var model: HubModel = new_model()
	if model.pages() != ["crew", "stats", "store", "craft", "fit"]:
		return "pages are %s" % [model.pages()]
	for id: String in model.pages():
		if model.page_title(id) == "":
			return "page %s has no title" % id
	var config: HubConfig = HubConfig.parse_json(JSON.stringify({
		"pages": [{"id": "fit", "title": "F"}, {"id": "craft", "title": "C"},
			{"id": "store", "title": "S"}, {"id": "crew", "title": "W"}, {"id": "stats", "title": "L"}],
		"empty_crew": "none", "empty_store": "none",
		"text": JSON.parse_string(FileAccess.get_file_as_string(HubConfig.CONFIG_PATH))["text"],
	}))
	if config.error != "" or config.pages != ["fit", "craft", "store", "crew", "stats"] or config.title("crew") != "W":
		return "reordered file read as %s (%s)" % [config.pages, config.error]
	return ""


func test_an_empty_profile_lists_no_crew_an_empty_store_and_locked_tier_1() -> String:
	var model: HubModel = new_model()
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
	var rows: Array[Dictionary] = new_model(profile).crew()
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
	var rows: Array[Dictionary] = new_model(profile).store()
	var seen: Array = rows.map(func(row: Dictionary) -> String: return "%s:%d:%d" % [row["id"], row["tier"], row["count"]])
	if seen != ["cell_salts:1:2", "scrap_alloy:1:4", "core_glass:3:1"]:
		return "store is %s" % [seen]
	if rows[0]["name"] != "Cell Salts":
		return "name is %s" % rows[0]["name"]
	return ""


func test_craft_moves_an_upgrade_from_locked_to_crafted_and_lowers_the_store() -> String:
	var profile: Profile = Profile.new()
	var model: HubModel = new_model(profile)
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


func test_the_model_never_changes_the_callers_ship_data() -> String:
	var data: Dictionary = ship_data()
	var profile: Profile = rich_profile()
	var model: HubModel = HubModel.create(HubConfig.load_shipped(), profile,
		CrewRoles.parse_json(FileAccess.get_file_as_string(ROLES_PATH)),
		ComponentList.parse(shipped_texts(ComponentList.COMPONENTS_DIR)),
		UpgradeTree.parse(shipped_texts(UpgradeTree.UPGRADES_DIR)), Fitting.new(), data)
	model.craft("needle_gun")
	model.fit("primary[0]", "needle_gun")
	model.launch()
	if data != ship_data():
		return "ship data changed to %s" % data
	return ""


func test_config_errors_name_the_key() -> String:
	var good: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(HubConfig.CONFIG_PATH))
	var cases: Dictionary = {
		"missing key \"empty_store\"": func(d: Dictionary) -> void: d.erase("empty_store"),
		"unknown key \"extra\"": func(d: Dictionary) -> void: d["extra"] = 1,
		"is missing page \"fit\"": func(d: Dictionary) -> void: (d["pages"] as Array).remove_at(4),
		"repeats page \"crew\"": func(d: Dictionary) -> void: d["pages"][1]["id"] = "crew",
		"\"pages[2].id\" must be one of": func(d: Dictionary) -> void: d["pages"][2]["id"] = "bar",
		"\"pages[0].title\" must be a non-empty string": func(d: Dictionary) -> void: d["pages"][0]["title"] = " ",
		"\"empty_crew\" must be a non-empty string": func(d: Dictionary) -> void: d["empty_crew"] = 3,
		"missing key \"text\"": func(d: Dictionary) -> void: d.erase("text"),
		"\"text.launch_row\" must be a non-empty string": func(d: Dictionary) -> void: d["text"].erase("launch_row"),
		"\"text\" has unknown key \"shout\"": func(d: Dictionary) -> void: d["text"]["shout"] = "x",
		"\"text.slot_names\" is missing \"utility\"": func(d: Dictionary) -> void: d["text"]["slot_names"].erase("utility"),
		"\"text.stat_names.shield_max\" must be a non-empty string": func(d: Dictionary) -> void: d["text"]["stat_names"]["shield_max"] = "",
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
