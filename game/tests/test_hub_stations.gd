extends RefCounted

## The hub's pages on the home base room's stations (#1299, CRW-2, CRF-3, CRF-4,
## RUN-8, PLT-5, ARC-3, MP-2): the stick steps through the six stations in
## order and wraps, A takes the highlighted one into use and shows its rows
## from the same hub text, stick left goes back, and crafting and fitting
## through the stations leaves the same profile and fitting as through the
## flat panel. Pointing is in `test_hub_station_aim.gd`.

const SHIP_PATH: String = "res://data/ships/default_ship.json"
const ROLES_PATH: String = "res://data/crew/roles.json"
const ORDER: Array[String] = ["crew", "logbook", "craft", "fit", "resume", "launch"]
const STATION_FILES: Array[String] = ["res://xr/hub_stations.gd", "res://xr/hub_station_screen.gd"]


static func _texts(dir: String) -> Dictionary:
	var texts: Dictionary = {}
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".json"):
			texts[file] = FileAccess.get_file_as_string(dir.path_join(file))
	return texts


static func _rich_profile() -> Profile:
	var profile: Profile = Profile.new()
	profile.bank({"scrap_alloy": 20, "cell_salts": 20, "circuit_shards": 20, "core_glass": 20})
	return profile


static func _hub(profile: Profile) -> HubText:
	return HubText.new(HubModel.create(
		HubConfig.load_shipped(),
		profile,
		CrewRoles.parse_json(FileAccess.get_file_as_string(ROLES_PATH)),
		ComponentList.parse(_texts(ComponentList.COMPONENTS_DIR)),
		UpgradeTree.parse(_texts(UpgradeTree.UPGRADES_DIR)),
		Fitting.new(),
		JSON.parse_string(FileAccess.get_file_as_string(SHIP_PATH))))


## The shipped room with open stations over `hub`, the opening frame gone by.
static func _open(hub: HubText) -> HubStations:
	var room: HubRoom = HubRoom.new()
	var stations: HubStations = HubStations.new(room)
	room.add_child(stations)
	stations.open(hub)
	stations.update({})
	return stations


static func _free(stations: HubStations) -> void:
	stations.get_parent().free()


static func _tap(stations: HubStations, action: String) -> Dictionary:
	var result: Dictionary = stations.update({action: true})
	stations.update({})
	return result


## Steps right to station `id` and presses A.
static func _use(stations: HubStations, id: String) -> void:
	if stations.in_use != "":
		_tap(stations, DevMenuModel.LEFT)
	for i: int in ORDER.size():
		if stations.highlighted_id() == id:
			break
		_tap(stations, DevMenuModel.RIGHT)
	_tap(stations, DevMenuModel.CONFIRM)


## Moves down from the top until the selected row does `want` and presses A;
## a fit takes its slot on the bay's ship first (#1366).
static func _press(stations: HubStations, hub: HubText, want: Dictionary) -> Dictionary:
	if want.get("action", "") != HubFitBay.ACTION_SLOT and want.has("slot") and hub.station == HubFitBay.STATION and hub.fit_slot == "":
		_press(stations, hub, {"action": HubFitBay.ACTION_SLOT, "slot": want["slot"]})
	hub.move(-1000)
	for i: int in 200:
		if hub.selected() == want:
			return _tap(stations, DevMenuModel.CONFIRM)
		var before: int = hub.selected_line()
		_tap(stations, DevMenuModel.DOWN)
		if hub.selected_line() == before:
			return {}
	return {}


func test_the_stick_steps_through_all_six_in_order_and_wraps() -> String:
	var stations: HubStations = _open(_hub(Profile.new()))
	var result: String = ""
	if stations.ids != ORDER:
		result = "stations in order %s" % [stations.ids]
	var seen: Array[String] = []
	for i: int in ORDER.size() + 1:
		seen.append(stations.highlighted_id())
		_tap(stations, DevMenuModel.RIGHT)
	var expected: Array[String] = ORDER.duplicate()
	expected.append(ORDER[0])
	if result == "" and seen != expected:
		result = "stick right steps %s" % [seen]
	_tap(stations, DevMenuModel.LEFT)
	_tap(stations, DevMenuModel.LEFT)
	if result == "" and stations.highlighted_id() != ORDER[ORDER.size() - 1]:
		result = "stick left from %s wraps to %s" % [ORDER[0], stations.highlighted_id()]
	_tap(stations, DevMenuModel.DOWN)
	if result == "" and (stations.in_use != "" or stations.highlighted_id() != "launch"):
		result = "stick down while choosing did something"
	_free(stations)
	return result


func test_a_uses_the_station_and_stick_left_goes_back() -> String:
	var hub: HubText = _hub(_rich_profile())
	var stations: HubStations = _open(hub)
	var result: String = ""
	_use(stations, "craft")
	if stations.in_use != "craft" or hub.station != "craft":
		result = "A on the craft station left %s in use" % stations.in_use
	elif stations.texts().slice(1) != _window(hub):
		result = "the craft station shows %s, the hub text %s" % [stations.texts(), hub.lines()]
	var first: int = hub.selected_line()
	_tap(stations, DevMenuModel.DOWN)
	if result == "" and hub.selected_line() <= first:
		result = "stick down inside the station kept line %d" % hub.selected_line()
	_tap(stations, DevMenuModel.LEFT)
	if result == "" and (stations.in_use != "" or hub.station != "" or stations.highlighted_id() != "craft"):
		result = "stick left did not go back to choosing on the craft station"
	_free(stations)
	return result


## The hub text's rows the screen shows: its window (#1300), the selected row
## marked as the screen marks it and its note under it.
static func _window(hub: HubText) -> Array[String]:
	var first: int = hub.first_shown()
	var rows: Array[String] = hub.lines().slice(1 + first, 1 + first + hub.rows_shown())
	var chosen: int = hub.selected_line() - 1 - first
	if chosen >= 0:
		rows[chosen] = str(HubPanelLook.load_file()["mark_text"]) + rows[chosen]
		if hub.note() != "":
			rows.insert(chosen + 1, hub.note())
	return rows


## True when `shown` is a run of the window's lines holding the selected row:
## a line that wraps can leave fewer lines on the face than the window (#1359).
static func _in_window(hub: HubText, shown: Array[String]) -> bool:
	var rows: Array[String] = _window(hub)
	var mark: String = str(HubPanelLook.load_file()["mark_text"])
	if not shown.any(func(line: String) -> bool: return line.begins_with(mark)):
		return false
	for start: int in rows.size():
		if rows.slice(start, start + shown.size()) == shown:
			return true
	return false


func test_the_rows_scroll_with_the_selection() -> String:
	var hub: HubText = _hub(_rich_profile())
	var stations: HubStations = _open(hub)
	_use(stations, "craft")
	var result: String = ""
	for i: int in 40:
		_tap(stations, DevMenuModel.DOWN)
		var shown: Array[String] = stations.texts().slice(1)
		var marked: int = 0
		for line: String in shown:
			marked += 1 if line.begins_with(str(HubPanelLook.load_file()["mark_text"])) else 0
		if marked != 1 or shown.size() > hub.rows_shown() + 1 or not _in_window(hub, shown):
			result = "after %d steps down the screen shows %s" % [i + 1, shown]
			break
	_free(stations)
	return result


func test_only_the_station_in_use_shows_rows() -> String:
	var stations: HubStations = _open(_hub(_rich_profile()))
	var result: String = ""
	if stations.texts().size() != ORDER.size():
		result = "while choosing the screens show %s" % [stations.texts()]
	_use(stations, "fit")
	var room: Node = stations.get_parent()
	for id: String in ORDER:
		var words: Node = room.get_node("Station_%s/Screen/%s" % [id, HubStationScreen.NODE_NAME])
		var shown: int = 0
		for label: Node in words.get_children():
			shown += 1 if label is Label3D and (label as Label3D).visible else 0
		if result == "" and id != "fit" and shown != 1:
			result = "%s shows %d lines while fit is in use" % [id, shown]
		if result == "" and id == "fit" and shown < 2:
			result = "the fit station shows %d lines" % shown
	if result == "" and (stations.view("fit") == null or stations.view("fit").slot_nodes.is_empty()):
		result = "the fit station draws no ship with slots"
	_free(stations)
	return result


func test_crafting_and_fitting_at_the_stations_match_the_panel() -> String:
	var by_stations: HubText = _hub(_rich_profile())
	var stations: HubStations = _open(by_stations)
	var by_panel: HubText = _hub(_rich_profile())
	var panel: HubPanel = HubPanel.new(HubPanelLook.load_file())
	panel.open(by_panel)
	panel.update({})
	var weapon: String = AcceptanceCraftAndFitCheck.first_weapon(by_stations.model)
	var result: String = "the rich profile builds no weapon" if weapon == "" else ""
	var steps: Array[Dictionary] = [
		{"station": "craft", "page": HubConfig.CRAFT, "want": {"action": HubText.ACTION_CRAFT, "id": weapon}},
		{"station": "fit", "page": HubConfig.FIT, "want": {"action": HubText.ACTION_FIT, "slot": "primary[0]", "id": weapon}},
	]
	for step: Dictionary in steps:
		if result != "":
			break
		_use(stations, step["station"])
		var at_station: Dictionary = _press(stations, by_stations, step["want"])
		while by_panel.page_id() != step["page"]:
			panel.update({DevMenuModel.RIGHT: true})
			panel.update({})
		by_panel.move(-1000)
		while by_panel.selected() != step["want"] and by_panel.selected_line() < by_panel.lines().size() - 1:
			by_panel.move(1)
		var at_panel: Dictionary = panel.update({DevMenuModel.CONFIRM: true})
		panel.update({})
		if at_station != at_panel:
			result = "%s: the station gave %s, the panel %s" % [step["station"], at_station, at_panel]
	if result == "" and by_stations.model.profile.to_json() != by_panel.model.profile.to_json():
		result = "profiles differ: %s / %s" % [by_stations.model.profile.to_json(), by_panel.model.profile.to_json()]
	if result == "" and by_stations.model.fitting.to_json() != by_panel.model.fitting.to_json():
		result = "fittings differ: %s / %s" % [by_stations.model.fitting.to_json(), by_panel.model.fitting.to_json()]
	if result == "" and by_stations.model.fitting.primary[0] != weapon:
		result = "the stations fitted %s" % [by_stations.model.fitting.primary]
	panel.free()
	_free(stations)
	return result


func test_the_launch_station_shows_a_refusal_and_the_resume_station_its_run() -> String:
	var hub: HubText = _hub(Profile.new())
	var stations: HubStations = _open(hub)
	hub.model.fitting.primary[0] = "arc_lance"  # Not crafted: the fitting check refuses it.
	var reason: String = hub.model.launch_check()
	_use(stations, "launch")
	var pressed: Dictionary = _press(stations, hub, {"action": HubText.ACTION_LAUNCH})
	var result: String = ""
	if reason == "" or pressed.get("reason", "") != reason or stations.reason_text() != reason:
		result = "the launch station shows '%s', the check says '%s'" % [stations.reason_text(), reason]
	elif not stations.texts().has(reason):
		result = "the refusal is not on the launch screen: %s" % [stations.texts()]
	_use(stations, "resume")
	var none: String = hub.model.config.words.row("resume_none")
	var shown: Array[String] = stations.texts()
	if result == "" and (shown.size() != 2 or shown[1] != none or not hub.selected().is_empty()):
		result = "with no run waiting the resume station shows %s" % [stations.texts()]
	_free(stations)
	return result


func test_the_stations_touch_no_simulation_and_read_no_buttons() -> String:
	for path: String in STATION_FILES:
		var source: String = FileAccess.get_file_as_string(path)
		for forbidden: String in ["Sim", "ShipState", "LocalSession", "Input.", "Comfort", "save("]:
			if source.find(forbidden) >= 0:
				return "%s uses %s" % [path, forbidden]
	return ""
