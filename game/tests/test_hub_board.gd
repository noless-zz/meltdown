extends RefCounted

## The Crew Quarters and Logbook boards (#1368, CRW-1, CRW-2, ARC-4): crew
## cards, attribute bars against stock from the ship summary (#1357), Logbook
## figures, the selection followed by the board, few words, no ids, and the
## hub file's `boards` section. On the shipped data files.

const Stations: GDScript = preload("res://tests/test_hub_stations.gd")


static func _crewed() -> Profile:
	var profile: Profile = Profile.new()
	var roles: Array[String] = ["shield_tech", "shield_tech", "surveyor", "cargo_rigger", "reactor_hand"]
	for i: int in roles.size():
		profile.crew.append({Profile.CREW_ID: "crew-%d" % i, Profile.CREW_ROLE: roles[i]})
	return profile


static func _at(profile: Profile, station: String) -> HubText:
	var hub: HubText = Stations._hub(profile)
	hub.model.parts = HubPartInfo.load_shipped()  # So the summary has every ship number.
	hub.choose_station(station)
	return hub


## Moves the selection until the board marks item `id`; false when it never does.
static func _select(hub: HubText, id: String) -> bool:
	hub.move(-1000)
	for i: int in 100:
		if _chosen(hub) == id:
			return true
		hub.move(1)
	return false


static func _chosen(hub: HubText) -> String:
	for item: Dictionary in hub.drawing().get("items", []):
		if item["selected"]:
			return item["id"]
	return ""


static func _item(hub: HubText, id: String) -> Dictionary:
	for item: Dictionary in hub.drawing().get("items", []):
		if item["id"] == id:
			return item
	return {}


func test_the_shipped_file_draws_boards_on_crew_and_logbook_only() -> String:
	var hub: HubText = _at(_crewed(), HubBoard.CREW_STATION)
	var layout: HubBoardLayout = hub.model.config.boards
	if not layout.has_boards():
		return "the shipped hub file has no boards: %s" % layout.error
	for station: String in HubStationPages.STATIONS:
		var drawn: bool = station in [HubBoard.CREW_STATION, HubBoard.LOG_STATION]
		if HubBoard.shows(hub.model, station) != drawn:
			return "station %s draws a board: %s" % [station, not drawn]
	if hub.rows_shown() != layout.rows_visible or hub.drawing().get("kind", "") != "board":
		return "the Crew Quarters shows %d rows and draws %s" % [hub.rows_shown(), hub.drawing().get("kind", "")]
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(HubConfig.CONFIG_PATH))
	data.erase(HubConfig.KEY_BOARDS)
	hub.model.config = HubConfig.parse_json(JSON.stringify(data))
	hub.choose_station(HubBoard.CREW_STATION)
	if hub.drawing() != {} or hub.rows_shown() != hub.model.config.max_rows_visible:
		return "without a boards section the Crew Quarters still draws one"
	return ""


func test_each_crew_role_is_a_card_with_its_icon_name_and_effect() -> String:
	var hub: HubText = _at(_crewed(), HubBoard.CREW_STATION)
	var items: Array = hub.drawing()["items"]
	if items.size() != 4:
		return "expected 4 cards, one per role, got %d" % items.size()
	var shield: Dictionary = _item(hub, "crew:shield_tech")
	if shield.is_empty() or shield["type"] != HubBoard.CARD:
		return "no card for the shield technicians: %s" % [items]
	if shield["icon"] != {"group": "crew", "id": "shield_tech"}:
		return "the card's icon is %s" % shield["icon"]
	if shield["name"] != "Shield Technician ×2":
		return "the card's name is \"%s\"" % shield["name"]
	if shield["figure"] != "+10" or shield["figure_icon"] != {"group": "attribute", "id": "shield"}:
		return "the card gives %s %s, expected the shield icon and +10" % [shield["figure_icon"], shield["figure"]]
	var surveyor: Dictionary = _item(hub, "crew:surveyor")
	if surveyor["figure_icon"] != {"group": "attribute", "id": "map_reveal"}:
		return "the surveyor's effect icon is %s" % surveyor["figure_icon"]
	return ""


func test_the_board_marks_the_selected_row_and_crew_notes_go() -> String:
	var hub: HubText = _at(_crewed(), HubBoard.CREW_STATION)
	for role: String in ["shield_tech", "surveyor", "cargo_rigger", "reactor_hand"]:
		if not _select(hub, "crew:" + role):
			return "the stick never marks %s's card" % role
		if hub.note() != "":
			return "the crew row keeps its note \"%s\" next to its card" % hub.note()
	var flat: HubText = Stations._hub(_crewed())
	flat.page = flat.model.pages().find(HubConfig.CREW)
	if flat.note() == "":
		return "the flat panel lost the crew row's note"
	return ""


func test_ship_numbers_are_bars_against_stock() -> String:
	var hub: HubText = _at(_crewed(), HubBoard.CREW_STATION)
	if not _select(hub, "summary:max_shield"):
		return "the stick never reaches the shield's bar"
	var bar: Dictionary = _item(hub, "summary:max_shield")
	if bar["type"] != HubBoard.BAR or bar["icon"] != {"group": "attribute", "id": "shield"}:
		return "the shield is drawn as %s" % bar
	# Stock 50, two technicians +10, crew cap 25: the bar is 75 long.
	if not is_equal_approx(bar["mark"], 50.0 / 75.0) or not is_equal_approx(bar["fill"], 60.0 / 75.0):
		return "the shield bar is filled %.3f with stock at %.3f" % [bar["fill"], bar["mark"]]
	if bar["figure"] != "60 / 50":
		return "the shield bar says \"%s\"" % bar["figure"]
	if not _select(hub, "summary:max_speed"):
		return "the stick never reaches the speed's bar"
	var speed: Dictionary = _item(hub, "summary:max_speed")
	if not is_equal_approx(speed["fill"], speed["mark"]) or not is_equal_approx(speed["mark"], 1.0 / 1.5):
		return "an unchanged number should fill to its stock mark at 1/headroom: %s" % speed
	for item: Dictionary in hub.drawing()["items"]:
		if item["type"] != HubBoard.BAR:
			return "a ship number's row draws a %s" % item["type"]
	return ""


func test_the_bars_window_follows_the_selection() -> String:
	var hub: HubText = _at(_crewed(), HubBoard.CREW_STATION)
	var layout: HubBoardLayout = hub.model.config.boards
	var seen: Dictionary = {}
	hub.move(-1000)
	for i: int in 60:
		var drawing: Dictionary = hub.drawing()
		var items: Array = drawing["items"]
		if items.size() > layout.strips_visible:
			return "the board draws %d strips, over %d" % [items.size(), layout.strips_visible]
		var chosen: String = _chosen(hub)
		if chosen == "":
			return "row %d has no item on the board" % hub.selected_line()
		seen[chosen] = true
		for item: Dictionary in items:
			var bottom: float = (item["at"] as Vector2).y - layout.strip_height_m * 0.5
			if bottom < -0.112 + 0.004:
				return "strip %s runs off the face at %.3f" % [item["id"], bottom]
		hub.move(1)
	for entry: Dictionary in hub.model.summary():
		if HubSummaryRows.value_text(hub.model.config.words, entry) != "" and not seen.has("summary:" + str(entry["stat"])):
			return "the bar for %s was never shown selected" % entry["stat"]
	return ""


func test_the_logbook_is_figures_with_won_and_lost_as_bars() -> String:
	var profile: Profile = Profile.new()
	profile.stats.runs_started = 8
	profile.stats.runs_won = 2
	profile.stats.runs_lost = 6
	profile.stats.deepest_level = 3
	var hub: HubText = _at(profile, HubBoard.LOG_STATION)
	var items: Array = hub.drawing()["items"]
	if items.size() != ProfileStats.KEYS.size():
		return "expected a figure per counter, got %d" % items.size()
	var won: Dictionary = _item(hub, "stats:runs_won")
	if won["figure"] != "2" or won["caption"] != "Won" or not is_equal_approx(won["fill"], 0.25):
		return "the won figure is %s" % won
	var deepest: Dictionary = _item(hub, "stats:deepest_level")
	if deepest["figure"] != "3" or deepest["fill"] != -1.0:
		return "the deepest figure is %s" % deepest
	if not _select(hub, "stats:runs_lost"):
		return "the stick never marks the lost figure"
	var fresh: HubText = _at(Profile.new(), HubBoard.LOG_STATION)
	if _item(fresh, "stats:runs_won")["fill"] != 0.0:
		return "with no runs the won bar should be empty"
	return ""


func test_few_words_and_no_ids_on_the_boards() -> String:
	var hub: HubText = _at(_crewed(), HubBoard.CREW_STATION)
	var ids: Array[String] = ["shield_tech", "surveyor", "cargo_rigger", "reactor_hand"]
	ids.append_array(ProfileStats.KEYS)
	for entry: Dictionary in hub.model.summary():
		ids.append(str(entry["stat"]))
	for station: String in [HubBoard.CREW_STATION, HubBoard.LOG_STATION]:
		hub.choose_station(station)
		hub.move(-1000)
		for i: int in 40:
			var named: int = 0
			for item: Dictionary in hub.drawing()["items"]:
				var texts: Array[String] = []
				for key: String in ["name", "figure", "caption"]:
					if item.has(key):
						texts.append(str(item[key]))
				named += 1 if item.has("name") else 0
				for text: String in texts:
					for id: String in ids:
						if text.contains(id):
							return "board text \"%s\" shows the id %s" % [text, id]
			var lines: int = hub.rows_shown() + (1 if hub.note() != "" else 0) + named
			if station == HubBoard.LOG_STATION:
				lines += ceili(float(ProfileStats.KEYS.size()) / float(hub.model.config.boards.tile_columns))
			if lines > 5:
				return "the %s station shows %d lines of words" % [station, lines]
			hub.move(1)
	return ""


func test_the_boards_section_is_checked() -> String:
	var good: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(HubConfig.CONFIG_PATH))[HubConfig.KEY_BOARDS]
	var cases: Dictionary = {"unknown key": {"size": 1}, "rows_visible": {"rows_visible": 1.5},
		"top_y_m": {"top_y_m": "low"}, "log_captions": {"log_captions": {"runs_started": "Runs"}},
		"log_bars": {"log_bars": {"runs_won": "nothing"}}}
	for case: String in cases:
		var bad: Dictionary = good.duplicate(true)
		bad.merge(cases[case], true)
		var layout: HubBoardLayout = HubBoardLayout.parse(bad)
		var word: String = case if case != "unknown key" else "size"
		if layout.has_boards() or not layout.error.contains(word):
			return "%s: expected an error naming it, got \"%s\"" % [case, layout.error]
	if not HubBoardLayout.parse(good).has_boards():
		return "the shipped section is refused: %s" % HubBoardLayout.parse(good).error
	return ""
