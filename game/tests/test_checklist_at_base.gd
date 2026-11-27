extends RefCounted

## The test checklist at the home base (#1408, DEV-6, DEV-7, ARC-3, CMF-8,
## MP-2): with a checklist pinned, the menu tap the hub ignores opens the page
## and a second tap pins it; without one it does nothing; in the mine the tap
## still opens the dev menu. While the page is open the stations get no stick
## input. A `station` step action takes the station into use with the stick's
## own presses at the base, says so on the page elsewhere, and an unknown id
## is refused when the file is read.

const Menu := preload("res://tests/test_dev_menu_wiring.gd")
const Stations := preload("res://tests/test_hub_stations.gd")
const SCRATCH: String = "user://test_checklist_at_base_"
const TEXT: String = '{"id": "t2", "title": "T", "parts": [{"title": "Base", "steps": [' \
	+ '{"id": "a", "do": "A", "look_for": "a", "action": {"station": "craft"}}, ' \
	+ '{"id": "b", "do": "B", "look_for": "b"}]}]}'
const MENU_BUTTON: String = ControllerSampler.MENU_BUTTON


## A checklist and dev menu over a hub; with `open_hub` the hub is open on
## real stations, as when the pilot sits in the base. [menu, checklist, hub].
static func wired(open_hub: bool) -> Array:
	var restarts: Array[String] = []
	var menu: DevMenuWiring = Menu.wired("seed:5", restarts)
	var hub: HubWiring = HubWiring.new()
	hub.panel = HubPanel.new()
	if open_hub:
		hub.text = Stations._hub(Stations._rich_profile())
		hub.stations = Stations._open(hub.text)
	menu._hub_open = hub.is_open
	var checklist: ChecklistWiring = ChecklistWiring.new()
	checklist.available = true
	checklist.store.prefix = SCRATCH
	DirAccess.remove_absolute(checklist.store.path_for("t2"))
	var path: String = Menu.scratch("checklist_t2.json")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(TEXT)
	file.close()
	checklist.attach(null, menu, null, LevelStart.new(), Callable(), "abc123", path, hub)
	return [menu, checklist, hub]


static func done(wired_up: Array) -> void:
	Menu.done(wired_up[0])
	var checklist: ChecklistWiring = wired_up[1]
	if checklist.page != null:
		checklist.page.free()
	var hub: HubWiring = wired_up[2]
	if hub.stations != null:
		Stations._free(hub.stations)
	hub.panel.free()
	DirAccess.remove_absolute(checklist.store.path_for("t2"))


## One frame as `main.gd` reads it: the dev menu, the checklist, then the hub.
static func frame(wired_up: Array, values: Dictionary, at: float) -> void:
	var hub: HubWiring = wired_up[2]
	var checklist: ChecklistWiring = wired_up[1]
	hub.read(checklist.read((wired_up[0] as DevMenuWiring).read(values, at)))
	hub.update(checklist.is_open(), Transform3D.IDENTITY, 1.0 / 60.0)  # The open page pauses the session the hub waits on.


static func tap(wired_up: Array, at: float) -> void:
	frame(wired_up, Menu.pad_values({MENU_BUTTON: true}), at)
	frame(wired_up, Menu.pad_values(), at + 0.2)


static func stick_right(wired_up: Array, at: float) -> void:
	var values: Dictionary = Menu.pad_values()
	values["right_stick"] = Vector2(1.0, 0.0)
	frame(wired_up, values, at)
	frame(wired_up, Menu.pad_values(), at + 0.1)


func test_at_the_base_a_tap_opens_the_pinned_page_and_a_second_tap_pins_it() -> String:
	var wired_up: Array = wired(true)
	var menu: DevMenuWiring = wired_up[0]
	var checklist: ChecklistWiring = wired_up[1]
	checklist.pin()
	tap(wired_up, 1.0)
	var opened: bool = checklist.is_open() and not menu.is_open()
	var shows: String = checklist.page.text()
	tap(wired_up, 2.0)
	var pinned: bool = checklist.is_pinned() and not menu.is_open()
	done(wired_up)
	if not opened or not shows.contains("Do: A"):
		return "the tap did not open the page: open %s, menu %s, text %s" % [opened, menu.is_open(), shows]
	return "" if pinned else "the second tap did not pin the page"


func test_at_the_base_without_a_pinned_page_the_tap_does_nothing() -> String:
	var wired_up: Array = wired(true)
	var menu: DevMenuWiring = wired_up[0]
	var checklist: ChecklistWiring = wired_up[1]
	tap(wired_up, 1.0)
	var problem: String = ""
	if checklist.page.visible or menu.is_open():
		problem = "page shown %s, menu open %s" % [checklist.page.visible, menu.is_open()]
	done(wired_up)
	return problem


func test_in_the_mine_the_tap_opens_the_dev_menu_and_the_page_stays_pinned() -> String:
	var wired_up: Array = wired(false)
	var menu: DevMenuWiring = wired_up[0]
	var checklist: ChecklistWiring = wired_up[1]
	checklist.pin()
	tap(wired_up, 1.0)
	var problem: String = ""
	if not menu.is_open() or not checklist.is_pinned() or menu.ignored_tap:
		problem = "menu open %s, page pinned %s" % [menu.is_open(), checklist.is_pinned()]
	done(wired_up)
	return problem


func test_a_hold_at_the_base_still_passes_the_menu_button_through() -> String:
	var wired_up: Array = wired(true)
	var menu: DevMenuWiring = wired_up[0]
	var checklist: ChecklistWiring = wired_up[1]
	checklist.pin()
	tap(wired_up, 1.0)
	var held: Dictionary = checklist.read(menu.read(Menu.pad_values({MENU_BUTTON: true}), 3.0))
	var after: Dictionary = checklist.read(menu.read(Menu.pad_values({MENU_BUTTON: true}), 3.0 + ResetHold.RESET_HOLD_SECONDS))
	var problem: String = ""
	if not ResetHold.is_held(held) or not ResetHold.is_held(after) or not checklist.is_open():
		problem = "the open page swallowed the held menu button"
	done(wired_up)
	return problem


func test_while_the_page_is_open_the_stations_get_no_stick_and_pin_hands_it_back() -> String:
	var wired_up: Array = wired(true)
	var checklist: ChecklistWiring = wired_up[1]
	var stations: HubStations = (wired_up[2] as HubWiring).stations
	var session: LocalSession = LevelStart.tunnel_session(LatestInputSource.new())
	checklist._session_of = func() -> LocalSession: return session
	checklist.pin()
	tap(wired_up, 1.0)
	var start: String = stations.highlighted_id()
	stick_right(wired_up, 2.0)
	var while_open: String = stations.highlighted_id()
	var paused: bool = session.paused_by(ChecklistWiring.PAUSE_REASON)
	tap(wired_up, 3.0)
	stick_right(wired_up, 4.0)
	var after_pin: String = stations.highlighted_id()
	var unpaused: bool = not session.paused
	done(wired_up)
	if while_open != start or not paused:
		return "open page: highlight %s -> %s, paused %s" % [start, while_open, paused]
	if after_pin == start or not unpaused:
		return "pinned: the stick did not reach the stations (%s), unpaused %s" % [after_pin, unpaused]
	return ""


func test_a_station_action_at_the_base_takes_the_station_into_use_and_pins_the_page() -> String:
	var wired_up: Array = wired(true)
	var checklist: ChecklistWiring = wired_up[1]
	var stations: HubStations = (wired_up[2] as HubWiring).stations
	HubStationSelect.select(stations, "fit")  # Start inside another station.
	var in_fit: String = stations.in_use
	checklist.open()
	checklist.do_action(checklist.checklist.step("a"))
	var problem: String = ""
	if in_fit != "fit" or stations.in_use != "craft" or not checklist.is_pinned():
		problem = "from %s: in use %s, pinned %s" % [in_fit, stations.in_use, checklist.is_pinned()]
	done(wired_up)
	return problem


func test_a_station_action_away_from_the_base_does_nothing_and_says_so() -> String:
	var wired_up: Array = wired(false)
	var checklist: ChecklistWiring = wired_up[1]
	checklist.open()
	checklist.model.choice = checklist.model.choices().find(ChecklistPageModel.DO)
	checklist.read(Menu.pad_values())
	checklist.read(Menu.pad_values({"right_button_lower": true}))
	var text: String = checklist.page.text()
	var problem: String = ""
	if not checklist.is_open() or not text.contains("Only at the home base: open the Workbench station"):
		problem = "open %s, page %s" % [checklist.is_open(), text]
	checklist.read(Menu.pad_values())
	var values: Dictionary = Menu.pad_values()
	values["right_stick"] = Vector2(0.0, -1.0)
	checklist.read(values)
	if problem == "" and checklist.page.text().contains("Only at the home base"):
		problem = "the notice outlived the next press"
	done(wired_up)
	return problem


func test_station_select_refuses_an_unknown_id_and_pressing_nothing() -> String:
	var hub: HubText = Stations._hub(Stations._rich_profile())
	var stations: HubStations = Stations._open(hub)
	var before: String = stations.highlighted_id()
	var picked: bool = HubStationSelect.select(stations, "hangar")
	var problem: String = ""
	if picked or stations.highlighted_id() != before or stations.in_use != "":
		problem = "unknown id: picked %s, highlight %s, in use %s" % [picked, stations.highlighted_id(), stations.in_use]
	for id: String in stations.ids:
		if problem == "" and not HubStationSelect.select(stations, id):
			problem = "could not take %s into use" % id
	Stations._free(stations)
	return problem


func test_a_station_action_is_read_with_its_name_and_an_unknown_id_is_refused() -> String:
	var read: Checklist = Checklist.parse(TEXT)
	var step: ChecklistStep = read.step("a") if read.is_valid() else null
	if step == null or step.action != ChecklistStep.ACTION_STATION or step.action_value != "craft" \
			or step.action_text() != "open the Workbench station":
		return "read %s: %s" % [read.error, step.action_text() if step != null else "no step"]
	for bad: String in ['"hangar"', '7', '""']:
		var refused: Checklist = Checklist.parse(TEXT.replace('"craft"', bad))
		if refused.is_valid() or not refused.error.begins_with("part 1: step 1: \"station\" must be one of"):
			return "%s gave \"%s\"" % [bad, refused.error]
	return ""


func test_the_shipped_g6_base_steps_open_their_stations() -> String:
	var g6: Checklist = Checklist.load_file("res://data/checklists/g6.json")
	var want: Dictionary = {"base_stations": "craft", "workbench_costs": "craft", "one_item_one_slot": "fit"}
	for id: String in want:
		var step: ChecklistStep = g6.step(id)
		if step == null or step.action != ChecklistStep.ACTION_STATION or step.action_value != want[id]:
			return "%s: %s" % [id, "missing" if step == null else "%s %s" % [step.action, step.action_value]]
	return ""
