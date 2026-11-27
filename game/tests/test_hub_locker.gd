extends RefCounted

## The Parts Locker as the Workbench's second face (#1413, CRF-1, CRF-3, CRW-2,
## ARC-3, ARC-4): a row at the top of the tree switches to it and back, which
## changes no profile or fitting; it shows each held component kind as its icon
## with its count, kinds not held are not shown, and the selected one says which
## robots drop it by their shown names and which upgrades spend it, those the
## bank can build now first and marked. No ids, and at most five rows of words.

const SHIP_PATH: String = "res://data/ships/default_ship.json"
const ROLES_PATH: String = "res://data/crew/roles.json"
const MAX_WORD_ROWS: int = 5


static func _texts(dir: String) -> Dictionary:
	var texts: Dictionary = {}
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".json"):
			texts[file] = FileAccess.get_file_as_string(dir.path_join(file))
	return texts


static func _hub(banked: Dictionary, config: HubConfig = HubConfig.load_shipped()) -> HubText:
	var profile: Profile = Profile.new()
	profile.bank(banked)
	var model: HubModel = HubModel.create(config, profile,
		CrewRoles.parse_json(FileAccess.get_file_as_string(ROLES_PATH)),
		ComponentList.parse(_texts(ComponentList.COMPONENTS_DIR)),
		UpgradeTree.parse(_texts(UpgradeTree.UPGRADES_DIR)), Fitting.new(),
		JSON.parse_string(FileAccess.get_file_as_string(SHIP_PATH)))
	model.parts = HubPartInfo.load_shipped()
	var hub: HubText = HubText.new(model)
	hub.choose_station(HubLocker.STATION)
	return hub


## Opens the Locker face from the Workbench's switch row.
static func _open_locker(hub: HubText) -> String:
	hub.move(-1)
	if hub.selected() != {"action": HubText.ACTION_FACE, "face": HubLocker.LOCKER}:
		return "the row above the first upgrade does %s" % hub.selected()
	var reason: String = hub.press()
	if reason != "" or hub.face != HubLocker.LOCKER:
		return "pressing the switch gave \"%s\", face %s" % [reason, hub.face]
	return ""


func test_the_workbench_opens_on_the_tree_with_the_switch_above_the_first_upgrade() -> String:
	var hub: HubText = _hub({"scrap_alloy": 3})
	if hub.face != HubLocker.TREE or str(hub.selected().get("action", "")) != HubText.ACTION_CRAFT:
		return "the Workbench opened on face %s with %s selected" % [hub.face, hub.selected()]
	if hub.lines()[1] != hub.model.config.words.row("face_locker_row"):
		return "the first row is \"%s\"" % hub.lines()[1]
	if hub.drawing().get("kind", "") != "tree" or hub.lines().has(hub.model.page_title(HubConfig.STORE)):
		return "the tree face draws %s and lines %s" % [hub.drawing().get("kind", ""), hub.lines()]
	return _open_locker(hub)


func test_switching_faces_changes_no_profile_or_fitting() -> String:
	var hub: HubText = _hub({"scrap_alloy": 30, "cell_salts": 30})
	var profile: String = hub.model.profile.to_json()
	var fitting: Array = [hub.model.fitting.primary, hub.model.fitting.secondary, hub.model.fitting.utility,
		hub.model.fitting.parts]
	var problem: String = _open_locker(hub)
	if problem != "":
		return problem
	if hub.drawing().get("kind", "") != HubLocker.LOCKER or hub.selected() != {"action": HubText.ACTION_FACE,
			"face": HubLocker.TREE}:
		return "the Locker face draws %s with %s selected" % [hub.drawing().get("kind", ""), hub.selected()]
	if hub.press() != "" or hub.face != HubLocker.TREE or hub.drawing().get("kind", "") != "tree":
		return "pressing the switch again left face %s" % hub.face
	if hub.model.profile.to_json() != profile or fitting != [hub.model.fitting.primary, hub.model.fitting.secondary,
			hub.model.fitting.utility, hub.model.fitting.parts]:
		return "switching faces changed the profile or the fitting"
	hub.leave_station()
	hub.choose_station(HubLocker.STATION)
	return "" if hub.face == HubLocker.TREE else "the Workbench reopened on face %s" % hub.face


func test_only_held_kinds_are_shown_as_icons_with_counts() -> String:
	var hub: HubText = _hub({"scrap_alloy": 3, "circuit_shards": 2})
	hub.model.profile.banked["cell_salts"] = 0  # Collected once, all spent.
	var problem: String = _open_locker(hub)
	if problem != "":
		return problem
	hub.move(1)
	var tiles: Array = hub.drawing()["board"]["items"]
	var ids: Array = tiles.map(func(tile: Dictionary) -> String: return tile["id"])
	if ids != ["part:scrap_alloy", "part:circuit_shards"]:
		return "the locker draws %s" % [ids]
	for tile: Dictionary in tiles:
		if tile["type"] != HubLocker.PART or tile["icon"] != {"group": "component", "id": str(tile["id"]).trim_prefix("part:")}:
			return "tile %s" % tile
	if tiles[0]["figure"] != "3" or tiles[1]["figure"] != "2" or not tiles[0]["selected"] or tiles[1]["selected"]:
		return "tiles %s" % [tiles]
	var empty: HubText = _hub({})
	problem = _open_locker(empty)
	if problem != "" or not empty.drawing()["board"]["items"].is_empty() or empty.lines()[2] != empty.model.config.empty_store:
		return "an empty locker shows %s (%s)" % [empty.lines(), problem]
	return ""


func test_the_selected_kind_says_which_robots_drop_it_by_name() -> String:
	var hub: HubText = _hub({"scrap_alloy": 3, "core_glass": 1})
	var problem: String = _open_locker(hub)
	if problem != "":
		return problem
	hub.move(1)
	var names: Array[String] = hub.model.parts.drops.names("scrap_alloy")
	var words: HubWords = hub.model.config.words
	var want: String = words.row("locker_from_more", {"names": ", ".join(names.slice(0, HubLocker.FROM_SHOWN)),
		"count": names.size() - HubLocker.FROM_SHOWN})
	if names.size() <= HubLocker.FROM_SHOWN or hub.note() != want:
		return "scrap alloy's note is \"%s\", want \"%s\"" % [hub.note(), want]
	hub.move(1)
	if hub.note() != words.row("locker_from_none"):
		return "core glass, which no robot drops, says \"%s\"" % hub.note()
	return ""


func test_the_upgrades_that_spend_it_are_listed_with_those_buildable_now_first() -> String:
	var hub: HubText = _hub({"scrap_alloy": 30, "cell_salts": 30})
	var problem: String = _open_locker(hub)
	if problem != "":
		return problem
	hub.move(1)  # Cell salts, the first kind.
	var details: Array[Dictionary] = HubLocker.uses(hub.model, "cell_salts")
	var ids: Array[String] = HubLocker.spenders(hub.model, "cell_salts")
	var ready: Array[String] = hub.model.craftable().filter(func(id: String) -> bool: return ids.has(id))
	if ready.is_empty() or ready.size() == ids.size() or ids.slice(0, ready.size()) != ready:
		return "spenders %s, buildable now %s" % [ids, ready]
	var room: int = hub.model.config.locker.uses_shown
	if details.size() != room or not details[0]["ready"] or details[0]["icon"].is_empty():
		return "detail rows %s" % [details]
	var words: HubWords = hub.model.config.words
	if details[0]["text"] != words.row("locker_use_ready", {"name": HubCraftRows.upgrade_name(hub.model, ready[0])}):
		return "the first detail row says \"%s\"" % details[0]["text"]
	if ids.size() > room and details[-1]["text"] != words.row("locker_use_more", {"count": ids.size() - room + 1}):
		return "the last detail row says \"%s\"" % details[-1]["text"]
	var shown: Array[String] = hub.lines().slice(1 + hub.first_shown(), 1 + hub.first_shown() + hub.rows_shown())
	if not shown.has(details[0]["text"]):
		return "the window shows %s" % [shown]
	return ""


func test_no_ids_and_at_most_five_rows_of_words_on_any_row() -> String:
	var hub: HubText = _hub({"scrap_alloy": 30, "cell_salts": 12, "circuit_shards": 4, "core_glass": 1})
	var problem: String = _open_locker(hub)
	if problem != "":
		return problem
	var ids: Array[String] = ["scrap_alloy", "cell_salts", "circuit_shards", "core_glass", "part:"]
	for step: int in 8:
		var shown: Array[String] = hub.lines().slice(1 + hub.first_shown(), 1 + hub.first_shown() + hub.rows_shown())
		var count: int = shown.size() + (1 if hub.note() != "" else 0)
		if count > MAX_WORD_ROWS:
			return "row %d shows %d rows of words: %s" % [step, count, shown]
		for text: String in shown + [hub.note()]:
			for id: String in ids:
				if text.contains(id):
					return "\"%s\" shows an id" % text
		hub.move(1)
	return ""


func test_a_hub_file_without_the_locker_keeps_the_rows_under_the_tree() -> String:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(HubConfig.CONFIG_PATH))
	data.erase(HubConfig.KEY_LOCKER)
	var config: HubConfig = HubConfig.parse_json(JSON.stringify(data))
	if config.error != "" or config.locker.has_locker():
		return "the file without a locker: %s" % config.error
	var rows: Array[Dictionary] = HubStationPages.rows(HubModel.create(config, Profile.new(), null, ComponentList.new(),
		UpgradeTree.new(), Fitting.new(), {}), HubLocker.STATION)
	for row: Dictionary in rows:
		if (row["action"] as Dictionary).get("action", "") == HubText.ACTION_FACE:
			return "a Workbench without a locker has a face switch"
	data[HubConfig.KEY_LOCKER] = {"rows_visible": 9}
	if not HubConfig.parse_json(JSON.stringify(data)).error.contains("locker"):
		return "a bad locker section was accepted"
	return ""


static func _tap(stations: HubStations, action: String) -> void:
	stations.update({action: true})
	stations.update({})


func test_the_station_draws_the_locker_tiles_and_back_the_tree() -> String:
	var hub: HubText = _hub({"scrap_alloy": 3, "cell_salts": 2})
	var room: HubRoom = HubRoom.new()
	var stations: HubStations = HubStations.new(room)
	room.add_child(stations)
	stations.open(hub)
	stations.update({})
	while stations.highlighted_id() != HubLocker.STATION:
		_tap(stations, DevMenuModel.RIGHT)
	for action: String in [DevMenuModel.CONFIRM, DevMenuModel.UP, DevMenuModel.CONFIRM, DevMenuModel.DOWN]:
		_tap(stations, action)
	var view: HubTreeView = stations.tree_view(HubLocker.STATION)
	var problem: String = ""
	if view == null or not view.board.visible or view.board.items.size() != 2 \
			or view.board.selected_item != "part:cell_salts" or not view.nodes.is_empty() or view.can_point():
		problem = "the station drew %s" % ([view.board.items.keys(), view.nodes.size()] if view != null else "nothing")
	if problem == "":
		for action: String in [DevMenuModel.UP, DevMenuModel.CONFIRM]:
			_tap(stations, action)
		if view.board.visible or view.nodes.is_empty():
			problem = "back on the tree the station drew %d nodes, tiles shown %s" % [view.nodes.size(), view.board.visible]
	room.free()
	return problem
