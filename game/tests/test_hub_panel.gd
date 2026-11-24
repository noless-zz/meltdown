extends RefCounted

## The hub panel in the headset (#1071, CRW-2, CRF-3, CRF-4, ARC-3, ARC-4,
## MP-2): `HubPanel` draws a `HubText` over a fixture profile, one label per
## line, and drives it with the dev menu's named actions.

const SHIP_PATH: String = "res://data/ships/default_ship.json"
const ROLES_PATH: String = "res://data/crew/roles.json"
const PANEL_FILES: Array[String] = ["res://xr/hub_panel.gd", "res://xr/hub_panel_look.gd"]


static func _texts(dir: String) -> Dictionary:
	var texts: Dictionary = {}
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".json"):
			texts[file] = FileAccess.get_file_as_string(dir.path_join(file))
	return texts


static func _hub(profile: Profile) -> HubText:
	return HubText.new(HubModel.create(
		HubConfig.load_shipped(),
		profile,
		CrewRoles.parse_json(FileAccess.get_file_as_string(ROLES_PATH)),
		ComponentList.parse(_texts(ComponentList.COMPONENTS_DIR)),
		UpgradeTree.parse(_texts(UpgradeTree.UPGRADES_DIR)),
		Fitting.new(),
		JSON.parse_string(FileAccess.get_file_as_string(SHIP_PATH))))


## An open panel over `hub`, with the frame that opened it already gone by.
static func _panel(hub: HubText) -> HubPanel:
	var panel: HubPanel = HubPanel.new(HubPanelLook.load_file())
	panel.open(hub)
	panel.update({})
	return panel


## One press and release of `action`; returns what the press frame returned.
static func _tap(panel: HubPanel, action: String) -> Dictionary:
	var result: Dictionary = panel.update({action: true})
	panel.update({})
	return result


## Turns the panel right until the hub shows page `id`.
static func _to_page(panel: HubPanel, hub: HubText, id: String) -> void:
	for i: int in 10:
		if hub.page_id() == id:
			return
		_tap(panel, DevMenuModel.RIGHT)


func test_the_shipped_look_loads() -> String:
	var look: Dictionary = HubPanelLook.parse(FileAccess.get_file_as_string(HubPanelLook.DEFAULT_FILE))
	if look.has("error"):
		return look["error"]
	if look != HubPanelLook.FALLBACK:
		return "the shipped file and the fallback differ"
	return ""


func test_a_bad_look_names_the_key() -> String:
	var shipped: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(HubPanelLook.DEFAULT_FILE))
	var cases: Dictionary = {
		"line_font_size": 4,
		"selected_color": [1.0, 2.0, 0.0],
		"title_position_m": [0.0, 0.0, -9.0],
		"pixel_size": true,
		"mark_text": "",
	}
	for key: String in cases:
		var data: Dictionary = shipped.duplicate()
		data[key] = cases[key]
		var error: String = HubPanelLook.parse(JSON.stringify(data)).get("error", "")
		if not error.contains("\"%s\"" % key):
			return "a bad %s gave \"%s\"" % [key, error]
	var missing: Dictionary = shipped.duplicate()
	missing.erase("reason_color")
	if not str(HubPanelLook.parse(JSON.stringify(missing)).get("error", "")).contains("reason_color"):
		return "a missing reason_color was not named"
	shipped["typo_key"] = 1
	if not str(HubPanelLook.parse(JSON.stringify(shipped)).get("error", "")).contains("typo_key"):
		return "an unknown key was not named"
	return ""


func test_the_label_count_equals_the_line_count_on_every_page() -> String:
	var profile: Profile = Profile.new()
	profile.bank({"scrap_alloy": 5, "cell_salts": 4})
	var hub: HubText = _hub(profile)
	var panel: HubPanel = _panel(hub)
	var failure: String = ""
	for i: int in hub.model.pages().size():
		var lines: Array[String] = hub.lines()
		if hub.note() != "":
			lines.insert(hub.selected_line() + 1, hub.note())  # The selected row's note (#1300).
		var shown: Array[String] = panel.texts()
		if shown.size() != lines.size():
			failure = "page %s: %d labels for %d lines" % [hub.page_id(), shown.size(), lines.size()]
			break
		var chosen: int = hub.selected_line()
		for line: int in lines.size():
			var expected: String = lines[line]
			if line == chosen:
				expected = panel._look["mark_text"] + expected
			if shown[line] != expected:
				failure = "page %s line %d shows \"%s\", not \"%s\"" % [hub.page_id(), line, shown[line], expected]
		_tap(panel, DevMenuModel.RIGHT)
	panel.free()
	return failure


func test_moving_down_then_pressing_a_craftable_row_crafts_and_the_store_count_changes() -> String:
	var profile: Profile = Profile.new()
	profile.bank({"scrap_alloy": 5, "cell_salts": 4})
	var hub: HubText = _hub(profile)
	var panel: HubPanel = _panel(hub)
	_to_page(panel, hub, HubConfig.STORE)
	var store_before: Array[String] = panel.texts()
	_to_page(panel, hub, HubConfig.CRAFT)
	var ready: Array[String] = hub.model.craftable()
	var failure: String = ""
	_tap(panel, DevMenuModel.DOWN)
	for i: int in 50:
		if ready.has(str(hub.selected().get("id", ""))):
			break
		_tap(panel, DevMenuModel.UP)
	var picked: Dictionary = hub.selected()
	var result: Dictionary = _tap(panel, DevMenuModel.CONFIRM)
	if ready.is_empty() or not ready.has(str(picked.get("id", ""))):
		failure = "no craftable row reached on %s" % [panel.texts()]
	elif result != {"pressed": picked, "reason": ""}:
		failure = "pressing A returned %s" % result
	elif not profile.crafted.has(picked["id"]):
		failure = "the press did not craft %s" % picked["id"]
	else:
		_to_page(panel, hub, HubConfig.STORE)
		var scrap: String = hub.model.config.words.row("store_row",
			{"name": "Scrap Alloy", "tier": 1, "count": profile.banked["scrap_alloy"]})
		if panel.texts() == store_before or not panel.texts().has(scrap):
			failure = "the store shows %s after crafting, %s before" % [panel.texts(), store_before]
	panel.free()
	return failure


func test_a_locked_row_shows_its_reason_until_the_next_input() -> String:
	var hub: HubText = _hub(Profile.new())
	var panel: HubPanel = _panel(hub)
	_to_page(panel, hub, HubConfig.CRAFT)
	var picked: Dictionary = hub.selected()
	var expected: String = hub.model.tree.missing(str(picked.get("id", "")), [], {})
	var result: Dictionary = _tap(panel, DevMenuModel.CONFIRM)
	var failure: String = ""
	if picked.get("action") != HubText.ACTION_CRAFT or expected == "":
		failure = "the first craft row is %s" % picked
	elif result != {"pressed": picked, "reason": expected}:
		failure = "pressing the locked row returned %s" % result
	elif panel.reason_text() != expected or panel.texts()[hub.selected_line() + 1] != expected:
		failure = "the panel shows \"%s\" under %s" % [panel.reason_text(), panel.texts()]
	else:
		_tap(panel, DevMenuModel.DOWN)
		if panel.reason_text() != "":
			failure = "the reason stayed after the next input"
	panel.free()
	return failure


func test_a_held_stick_moves_one_row_and_nothing_happens_on_its_own() -> String:
	var profile: Profile = Profile.new()
	profile.bank({"scrap_alloy": 20, "cell_salts": 20, "circuit_shards": 20, "core_glass": 20})
	var hub: HubText = _hub(profile)
	var panel: HubPanel = _panel(hub)
	_to_page(panel, hub, HubConfig.CRAFT)
	var failure: String = ""
	var start: int = hub.selected_line()
	for i: int in 30:
		if panel.update({DevMenuModel.DOWN: true}) != {}:
			failure = "moving returned something"
	if failure == "" and hub.selected_line() == start:
		failure = "holding down did not move"
	var after_one: int = hub.selected_line()
	_tap(panel, DevMenuModel.UP)
	_tap(panel, DevMenuModel.DOWN)
	if failure == "" and hub.selected_line() != after_one:
		failure = "holding down for 30 frames moved more than one row"
	var banked: Dictionary = profile.banked.duplicate()
	for i: int in 30:
		if panel.update({}) != {}:
			failure = "an idle frame returned something"
	if failure == "" and (profile.banked != banked or not profile.crafted.is_empty()):
		failure = "idle frames changed the profile"
	panel.free()
	return failure


func test_a_button_held_while_opening_does_not_press() -> String:
	var profile: Profile = Profile.new()
	profile.bank({"scrap_alloy": 5, "cell_salts": 4})
	var hub: HubText = _hub(profile)
	while hub.page_id() != HubConfig.CRAFT:
		hub.turn_page(1)
	var panel: HubPanel = HubPanel.new(HubPanelLook.FALLBACK)
	panel.open(hub)
	var failure: String = ""
	if panel.update({DevMenuModel.CONFIRM: true}) != {} or not profile.crafted.is_empty():
		failure = "the held A pressed on opening"
	elif panel.update({}) != {} or _tap(panel, DevMenuModel.CONFIRM).is_empty():
		failure = "a fresh A after opening did not press"
	panel.close()
	if failure == "" and panel.update({DevMenuModel.DOWN: true}) != {}:
		failure = "the closed panel took input"
	panel.free()
	return failure


func test_the_panel_writes_no_simulation_and_reads_no_comfort() -> String:
	for path: String in PANEL_FILES:
		var source: String = FileAccess.get_file_as_string(path)
		for forbidden: String in ["Sim", "ShipState", "LocalSession", "Comfort", "comfort_", "save(",
				"HubText", "HubModel", "Profile", "Fitting"]:
			var code: String = ""
			for line: String in source.split("\n"):
				if not line.strip_edges().begins_with("#"):
					code += line + "\n"
			if code.find(forbidden) >= 0:
				return "%s uses %s" % [path, forbidden]
	return ""
