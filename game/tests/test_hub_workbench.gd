extends RefCounted

## The Workbench says what each upgrade costs, what is held, what it does and
## what it unlocks, by name (#1317, CRF-3, CRF-6, CRW-2, ARC-4), and no id from
## any data file reaches a hub screen. Built on the shipped data files.

const Fixtures: GDScript = preload("res://tests/test_hub_model.gd")
const ROLES_PATH: String = "res://data/crew/roles.json"


static func _model(profile: Profile = Profile.new(), fitting: Fitting = Fitting.new()) -> HubModel:
	var model: HubModel = Fixtures.new_model(profile, fitting)
	model.parts = HubPartInfo.load_shipped()
	return model


static func _craft_lines(model: HubModel) -> Array[String]:
	var hub: HubText = HubText.new(model)
	hub.page = model.pages().find(HubConfig.CRAFT)
	return hub.lines()


static func _words() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(HubConfig.CONFIG_PATH))["text"]


func test_each_row_shows_the_cost_with_what_is_held_by_name() -> String:
	var profile: Profile = Profile.new()
	profile.bank({"cell_salts": 2, "scrap_alloy": 5})
	var model: HubModel = _model(profile)
	var hub: HubText = HubText.new(model)
	hub.page = model.pages().find(HubConfig.CRAFT)
	# Ember Coil costs 3 Cell Salts and 2 Scrap Alloy; 2 and 5 are held.
	var expected: String = "Cost: Cell Salts 2/3, Scrap Alloy 5/2"
	if HubCraftRows.cost_text(model, "ember_coil") != expected:
		return "ember coil's cost reads \"%s\"" % HubCraftRows.cost_text(model, "ember_coil")
	var ids: Array[String] = model.craftable()
	for entry: Dictionary in model.locked():
		ids.append(entry["id"])
	for id: String in ids:
		var cost: String = HubCraftRows.cost_text(model, id)
		# Details show only under the selected upgrade (#1300).
		hub.move(-1000)
		while hub.selected().get("id", "") != id and hub.selected_line() < hub.lines().size() - 1:
			hub.move(1)
		var lines: Array[String] = hub.lines()
		if hub.selected().get("id", "") != id or lines[hub.selected_line() + 1] != cost:
			return "no cost row under %s in %s" % [id, lines]
		var upgrade: UpgradeDef = model.tree.get_upgrade(id)
		for component: String in upgrade.cost:
			var item: String = "%s %d/%d" % [model.components.get_kind(component).display_name,
				profile.count_of(component), upgrade.cost[component]]
			if not cost.contains(item):
				return "%s's cost \"%s\" lacks \"%s\"" % [id, cost, item]
	return ""


func test_the_cost_row_sits_under_its_upgrade() -> String:
	var model: HubModel = _model()
	var hub: HubText = HubText.new(model)
	hub.page = model.pages().find(HubConfig.CRAFT)
	hub.row = 0
	var lines: Array[String] = hub.lines()
	var id: String = hub.selected().get("id", "")
	if id == "" or lines[hub.selected_line() + 1] != HubCraftRows.cost_text(model, id):
		return "the line under %s is \"%s\"" % [id, lines[hub.selected_line() + 1]]
	return ""


func test_what_an_upgrade_does_comes_from_its_part_file() -> String:
	var model: HubModel = _model()
	var weapon: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/weapons/ember_coil.json"))
	var rate: float = 60.0 / float(weapon["fire_interval_ticks"])
	var cases: Dictionary[String, String] = {
		"ember_coil": "Does: Damage %d, %s shots/s" % [int(weapon["damage"]), str(rate)],
		"glass_core_shield": "Does: Shield +40%, Recharge +20%, Shield energy -20%",
		"layered_plating": "Does: Hull +25%",
		"wide_radar": "Does: Map reveal 40 m",
	}
	for id: String in cases:
		if HubCraftRows.effect_text(model, id) != cases[id]:
			return "%s does \"%s\", expected \"%s\"" % [id, HubCraftRows.effect_text(model, id), cases[id]]
	if not _craft_lines(model).has(cases["ember_coil"]):
		return "the Workbench does not show ember coil's numbers"
	return ""


func test_every_shipped_upgrade_has_named_numbers() -> String:
	var model: HubModel = _model()
	var named: Dictionary = _words()["effect_names"]
	for upgrade: UpgradeDef in model.tree.upgrades:
		var effects: Array[Dictionary] = model.parts.effects(upgrade)
		if effects.is_empty():
			return "no part file gives numbers for %s" % upgrade.id
		for entry: Dictionary in effects:
			if not named.has(entry["key"]):
				return "hub.json names no \"%s\" (from %s)" % [entry["key"], upgrade.id]
	return ""


func test_each_upgrade_shows_what_it_unlocks_by_name() -> String:
	var model: HubModel = _model()
	if HubCraftRows.unlocks_text(model, "slug_thrower") != "Unlocks: Drift Mortar":
		return "slug thrower unlocks \"%s\"" % HubCraftRows.unlocks_text(model, "slug_thrower")
	for upgrade: UpgradeDef in model.tree.upgrades:
		var text: String = HubCraftRows.unlocks_text(model, upgrade.id)
		for other: UpgradeDef in model.tree.upgrades:
			if other.requires.has(upgrade.id) and not text.contains(other.display_name):
				return "%s does not say it unlocks %s: \"%s\"" % [upgrade.id, other.id, text]
	return ""


func test_a_locked_row_says_why_in_words() -> String:
	var model: HubModel = _model()
	var cases: Dictionary[String, String] = {
		"drift_mortar": "Needs Slug Thrower",
		"ember_coil": "3 more Cell Salts, 2 more Scrap Alloy",
	}
	var hub: HubText = HubText.new(model)
	hub.page = model.pages().find(HubConfig.CRAFT)
	for id: String in cases:
		if HubCraftRows.reason(model, id) != cases[id]:
			return "%s is locked because \"%s\"" % [id, HubCraftRows.reason(model, id)]
		# The reason is the locked row's note, shown under it while selected (#1300).
		hub.move(-1000)
		for i: int in 200:
			if hub.selected().get("id", "") == id:
				break
			hub.move(1)
		if hub.lines()[hub.selected_line()] != model.tree.get_upgrade(id).display_name or hub.note() != cases[id]:
			return "%s's row is \"%s\" with note \"%s\"" % [id, hub.lines()[hub.selected_line()], hub.note()]
	return ""


func test_the_rows_still_build_the_same_upgrades() -> String:
	var model: HubModel = _model(Fixtures.rich_profile())
	var hub: HubText = HubText.new(model)
	hub.page = model.pages().find(HubConfig.CRAFT)
	var expected: Array[String] = model.craftable()
	for entry: Dictionary in model.locked():
		expected.append(entry["id"])
	var seen: Array[String] = []
	for i: int in 200:
		var action: Dictionary = hub.selected()
		if action.get("action") == HubText.ACTION_CRAFT and not seen.has(action["id"]):
			seen.append(action["id"])
		hub.move(1)
	if seen != expected:
		return "the rows build %s, the model offers %s" % [seen, expected]
	return ""


func test_no_id_reaches_any_page_or_station() -> String:
	var ids: Array[String] = _shipped_ids()
	for model: HubModel in _states():
		var hub: HubText = HubText.new(model)
		var screens: Array[Array] = []
		for page: int in model.pages().size():
			hub.page = page
			screens.append(hub.lines())
		for station: String in HubStationPages.STATIONS:
			hub.choose_station(station)
			screens.append(hub.lines())
		hub.leave_station()
		hub.page = model.pages().find(HubConfig.CRAFT)
		hub.row = 0
		screens.append([hub.press()])
		for lines: Array in screens:
			for line: Variant in lines:
				var found: String = _id_in(str(line), ids)
				if found != "":
					return "\"%s\" shows the id \"%s\"" % [line, found]
	return ""


## An empty profile, a partly filled one, and one with everything built, crew
## of every role, the stock weapon, every part slot fitted and a run waiting.
static func _states() -> Array[HubModel]:
	var partial: Profile = Profile.new()
	partial.bank({"cell_salts": 2, "scrap_alloy": 5, "circuit_shards": 1})
	var full: Profile = Fixtures.rich_profile()
	var roles: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROLES_PATH))
	for role: Dictionary in roles["roles"]:
		full.crew.append({Profile.CREW_ID: "crew_%s" % role["id"], Profile.CREW_ROLE: role["id"]})
		full.crew.append({Profile.CREW_ID: "crew_%s_2" % role["id"], Profile.CREW_ROLE: role["id"]})
	var rich: HubModel = _model(full)
	for i: int in 4:
		for id: String in rich.craftable():
			rich.craft(id)
	full.bank({"scrap_alloy": 1, "cell_salts": 1, "circuit_shards": 1, "core_glass": 1})
	rich.fit("shield", "glass_core_shield")
	rich.fit("hull", "layered_plating")
	rich.fit("engine", "torsion_drive")
	rich.fit("primary[1]", "needle_gun")
	rich.fit("utility[0]", "wide_radar")
	var save: RunSave = RunSave.new()
	save.run_seed = 4242
	save.next_level = 2
	rich.set_waiting(save)
	return [_model(), _model(partial), rich]


## Every id the shipped data files use: upgrades, parts, weapons, components,
## crew roles and their stats, slots, and the keys of the part files' numbers.
static func _shipped_ids() -> Array[String]:
	var model: HubModel = _model()
	var ids: Array[String] = []
	for upgrade: UpgradeDef in model.tree.upgrades:
		ids.append_array([upgrade.id, upgrade.grants])
		for entry: Dictionary in model.parts.effects(upgrade):
			# A weapon's damage and rate are plain words, not keys of a file.
			if not [HubPartInfo.DAMAGE, HubPartInfo.RATE].has(entry["key"]):
				ids.append(entry["key"])
		ids.append_array(upgrade.cost.keys())
	ids.append_array(model.parts.weapons.keys())
	for dir: String in [ComponentList.COMPONENTS_DIR]:
		for file: String in DirAccess.get_files_at(dir):
			ids.append(file.get_basename())
	var roles: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROLES_PATH))
	for role: Dictionary in roles["roles"]:
		ids.append_array([role["id"], role["benefit"]["stat"]])
	ids.append_array(Fitting.KEYS)
	ids.append_array(Fitting.PART_KEYS)
	return ids


## The first id that stands as a whole word in `line` (ids are lower case with
## underscores, names are not), or "".
static func _id_in(line: String, ids: Array[String]) -> String:
	var regex: RegEx = RegEx.new()
	for id: String in ids:
		regex.compile("(^|[^a-z0-9_])%s($|[^a-z0-9_])" % id)
		if regex.search(line) != null:
			return id
	return ""
