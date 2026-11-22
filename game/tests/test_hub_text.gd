extends RefCounted

## The hub as text lines with a selected row (CRW-2, CRF-3, CRF-4, ARC-4, MP-2,
## NAM-3, #1058): page lines from data, a clamped selection, wrapping pages, and
## presses that pass the model's reasons through unchanged.

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


static func _hub(profile: Profile = Profile.new(), config: HubConfig = HubConfig.load_shipped()) -> HubText:
	return HubText.new(HubModel.create(
		config,
		profile,
		CrewRoles.parse_json(FileAccess.get_file_as_string(ROLES_PATH)),
		ComponentList.parse(_texts(ComponentList.COMPONENTS_DIR)),
		UpgradeTree.parse(_texts(UpgradeTree.UPGRADES_DIR)),
		Fitting.new(),
		_ship_data()))


## Turns `hub` to page `id`.
static func _to_page(hub: HubText, id: String) -> void:
	while hub.page_id() != id:
		hub.turn_page(1)


## Moves the selection to the row whose action names `key` = `value`; false if none.
static func _select(hub: HubText, key: String, value: String, action: String = "") -> bool:
	hub.move(-1000)
	for i: int in 200:
		var picked: Dictionary = hub.selected()
		if picked.get(key, null) == value and (action == "" or picked.get("action") == action):
			return true
		var before: int = hub.selected_line()
		hub.move(1)
		if hub.selected_line() == before:
			return false
	return false


func test_the_shipped_words_load() -> String:
	var config: HubConfig = HubConfig.load_shipped()
	if config.error != "":
		return config.error
	for key: String in HubWords.PLACEHOLDERS:
		var pattern: String = config.words.rows[key]
		var allowed: Array = HubWords.PLACEHOLDERS[key]
		var regex: RegEx = RegEx.create_from_string("\\{([a-z_]+)\\}")
		for found: RegExMatch in regex.search_all(pattern):
			if not allowed.has(found.get_string(1)):
				return "text.%s uses {%s}, which is never filled" % [key, found.get_string(1)]
	return ""


func test_an_empty_profile_shows_the_empty_crew_and_store_texts() -> String:
	var hub: HubText = _hub()
	var config: HubConfig = hub.model.config
	_to_page(hub, HubConfig.CREW)
	if hub.lines() != ([config.title(HubConfig.CREW), config.empty_crew] as Array[String]):
		return "crew page is %s" % [hub.lines()]
	if hub.selected_line() != -1 or hub.selected() != {} or hub.press() != "":
		return "the empty crew page has a selectable row"
	_to_page(hub, HubConfig.STORE)
	if hub.lines() != ([config.title(HubConfig.STORE), config.empty_store] as Array[String]):
		return "store page is %s" % [hub.lines()]
	return ""


func test_crew_and_store_lines_come_from_the_patterns() -> String:
	var profile: Profile = Profile.new()
	profile.crew.append({"id": "crew-1", "role": "shield_tech"})
	profile.bank({"cell_salts": 2})
	var hub: HubText = _hub(profile)
	var words: HubWords = hub.model.config.words
	_to_page(hub, HubConfig.CREW)
	var crew: String = words.row("crew_row", {"role": "Shield Technician", "amount": 5, "stat": words.stat_name("shield_max")})
	if hub.lines() != ([hub.model.page_title(HubConfig.CREW), crew] as Array[String]) or hub.selected() != {}:
		return "crew page is %s" % [hub.lines()]
	_to_page(hub, HubConfig.STORE)
	var store: String = words.row("store_row", {"name": "Cell Salts", "tier": 1, "count": 2})
	if hub.lines()[1] != store:
		return "store line is %s, expected %s" % [hub.lines()[1], store]
	return ""


func test_moving_past_the_last_row_stays_on_it() -> String:
	var hub: HubText = _hub()
	_to_page(hub, HubConfig.FIT)
	hub.move(1000)
	var last: int = hub.selected_line()
	if last != hub.lines().size() - 1 or hub.selected() != {"action": HubText.ACTION_LAUNCH}:
		return "the last row is line %d of %d: %s" % [last, hub.lines().size(), hub.selected()]
	hub.move(1)
	if hub.selected_line() != last:
		return "moving past the last row left it"
	hub.move(-1000)
	if hub.selected_line() != 1:
		return "moving before the first row selected line %d" % hub.selected_line()
	return ""


func test_turning_the_page_from_fit_wraps_to_crew_and_resets_the_row() -> String:
	var hub: HubText = _hub()
	_to_page(hub, HubConfig.FIT)
	hub.move(1000)
	hub.turn_page(1)
	if hub.page_id() != HubConfig.CREW:
		return "after fit came %s" % hub.page_id()
	hub.turn_page(-1)
	if hub.page_id() != HubConfig.FIT or hub.selected_line() != 1:
		return "back from crew: page %s line %d" % [hub.page_id(), hub.selected_line()]
	return ""


func test_pressing_a_locked_upgrade_returns_the_models_reason() -> String:
	var hub: HubText = _hub()
	_to_page(hub, HubConfig.CRAFT)
	var picked: Dictionary = hub.selected()
	if picked.get("action") != HubText.ACTION_CRAFT:
		return "first craft row does %s" % picked
	var expected: String = hub.model.tree.missing(picked["id"], [], {})
	var reason: String = hub.press()
	if reason == "" or reason != expected:
		return "pressing gave \"%s\", the model says \"%s\"" % [reason, expected]
	if not hub.lines()[hub.selected_line()].contains(expected):
		return "the locked line does not show the reason: %s" % hub.lines()[hub.selected_line()]
	return ""


func test_crafting_moves_the_row_and_lowers_the_store() -> String:
	var profile: Profile = Profile.new()
	profile.bank({"scrap_alloy": 5, "cell_salts": 4})
	var hub: HubText = _hub(profile)
	_to_page(hub, HubConfig.STORE)
	var store_before: Array[String] = hub.lines()
	_to_page(hub, HubConfig.CRAFT)
	var craft_before: Array[String] = hub.lines()
	if not _select(hub, "id", "needle_gun"):
		return "no needle_gun row on %s" % [hub.lines()]
	var reason: String = hub.press()
	if reason != "":
		return "craft refused: %s" % reason
	if not profile.crafted.has("needle_gun"):
		return "the press did not craft"
	var built: String = hub.model.config.words.row("built_row", {"name": hub.model.tree.get_upgrade("needle_gun").display_name})
	if hub.lines() == craft_before or not hub.lines().has(built):
		return "craft page after crafting is %s" % [hub.lines()]
	_to_page(hub, HubConfig.STORE)
	var words: HubWords = hub.model.config.words
	var scrap: String = words.row("store_row", {"name": "Scrap Alloy", "tier": 1, "count": profile.banked["scrap_alloy"]})
	if hub.lines() == store_before or not hub.lines().has(scrap) or profile.banked["scrap_alloy"] >= 5:
		return "store after crafting is %s" % [hub.lines()]
	return ""


func test_fit_then_launch_returns_the_models_loadout() -> String:
	var profile: Profile = Profile.new()
	profile.bank({"scrap_alloy": 20, "cell_salts": 20, "circuit_shards": 20, "core_glass": 20})
	var hub: HubText = _hub(profile)
	for id: String in ["needle_gun", "look_aim"]:
		if hub.model.craft(id) != "":
			return "could not craft %s" % id
	_to_page(hub, HubConfig.FIT)
	if not _select(hub, "id", "needle_gun", HubText.ACTION_FIT) or hub.selected()["slot"] != "primary[0]":
		return "no row fits needle_gun in primary[0]: %s" % [hub.lines()]
	if hub.press() != "":
		return "fitting needle_gun refused"
	if not _select(hub, "id", "look_aim", HubText.ACTION_FIT) or hub.press() != "":
		return "fitting look_aim failed: %s" % [hub.lines()]
	if not _select(hub, "action", HubText.ACTION_LAUNCH) or hub.press() != "":
		return "launch refused"
	var expected: Dictionary = hub.model.launch()
	if hub.launched != expected or hub.launched.get("primary") != ["needle_gun", ""] or hub.launched.get("utility") != ["look_aim"]:
		return "launch gave %s, the model %s" % [hub.launched, expected]
	# The slot row now shows the fitted name, and a strip row empties it again.
	if not _select(hub, "id", "", HubText.ACTION_FIT) or hub.press() != "" or hub.model.fitting.primary[0] != "":
		return "stripping primary[0] failed: %s" % [hub.model.fitting.to_json()]
	return ""


func test_a_refused_fit_passes_the_reason_through() -> String:
	var profile: Profile = Profile.new()
	profile.crafted.append("needle_gun")
	var hub: HubText = _hub(profile)
	_to_page(hub, HubConfig.FIT)
	if not _select(hub, "id", "needle_gun", HubText.ACTION_FIT) or hub.press() != "":
		return "first fit failed"
	# The same weapon is now offered only for primary[1], where Fitting.check refuses it.
	if not _select(hub, "id", "needle_gun", HubText.ACTION_FIT) or hub.selected()["slot"] != "primary[1]":
		return "no needle_gun row for primary[1]: %s" % [hub.lines()]
	var picked: Dictionary = hub.selected()
	var direct: String = hub.model.fit(picked["slot"], picked["id"])
	var reason: String = hub.press()
	if reason == "" or reason != direct:
		return "pressing gave \"%s\", the model says \"%s\"" % [reason, direct]
	return ""


func test_every_word_comes_from_the_data_file() -> String:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(HubConfig.CONFIG_PATH))
	data["text"]["launch_row"] = "LAUNCH-WORD"
	data["text"]["slot_names"]["primary"] = "GUN-{number}"
	var config: HubConfig = HubConfig.parse_json(JSON.stringify(data))
	if config.error != "":
		return config.error
	var hub: HubText = _hub(Profile.new(), config)
	_to_page(hub, HubConfig.FIT)
	var lines: Array[String] = hub.lines()
	if lines[lines.size() - 1] != "LAUNCH-WORD" or not lines[1].begins_with("GUN-1"):
		return "fit page ignores the file: %s" % [lines]
	return ""


func test_the_hub_text_touches_no_simulation() -> String:
	var source: String = FileAccess.get_file_as_string("res://meta/hub_text.gd")
	for forbidden: String in ["Sim", "ShipState", "LocalSession", "save(", "Store."]:
		if source.find(forbidden) >= 0:
			return "hub_text.gd uses %s" % forbidden
	return ""


func test_the_fitting_bay_offers_only_parts_of_each_slots_kind() -> String:
	var profile: Profile = Profile.new()
	profile.bank({"scrap_alloy": 20, "cell_salts": 20, "circuit_shards": 20, "core_glass": 20})
	var hub: HubText = _hub(profile)
	for id: String in ["shield_capacitor", "layered_plating"]:
		if hub.model.craft(id) != "":
			return "could not craft %s" % id
	_to_page(hub, HubConfig.FIT)
	var words: HubWords = hub.model.config.words
	var stock: String = words.row("slot_row", {"slot": words.slot_name("shield", 0), "fitted": words.row("slot_stock")})
	if not hub.lines().has(stock) or words.slot_name("engine", 0) != "Engine":
		return "no stock shield row on %s" % [hub.lines()]
	if not _select(hub, "id", "shield_capacitor", HubText.ACTION_FIT) or hub.selected()["slot"] != "shield":
		return "shield_capacitor is not offered for the shield slot: %s" % [hub.selected()]
	if hub.press() != "" or hub.model.fitting.parts["shield"] != "shield_capacitor":
		return "pressing did not fit the shield"
	if not _select(hub, "id", "layered_plating", HubText.ACTION_FIT) or hub.selected()["slot"] != "hull":
		return "layered_plating is not offered for the hull slot: %s" % [hub.selected()]
	# Walk every fit row: each part is offered only for its own slot.
	hub.move(-1000)
	for i: int in 200:
		var picked: Dictionary = hub.selected()
		if picked.get("action") == HubText.ACTION_FIT and picked["id"] != "":
			var kind: String = hub.model.tree.get_upgrade(picked["id"]).kind
			if Fitting.PART_KEYS.has(kind) and picked["slot"] != kind:
				return "%s offered for %s" % [picked["id"], picked["slot"]]
		var before: int = hub.selected_line()
		hub.move(1)
		if hub.selected_line() == before:
			break
	return ""
