extends RefCounted

## The dev menu at the home base, the shaft choice and the end screens (#1450,
## CRW-2, CMF-6, DEV-8, ARC-3, MP-2, decision record 0009): a tap opens it over
## the hub's stations; while it is open no stick or A reaches them, so a confirm
## never launches, fits or crafts; a waiting build is its Update entry; the
## Test checklist entry opens the page over the hub; the place is read from the
## hub, the shaft panel and the end screens; and the base's update sign names a
## waiting build only at the base.

const Menu := preload("res://tests/test_dev_menu_wiring.gd")
const Choices := preload("res://tests/test_dev_menu_wiring_choices.gd")
const AtBase := preload("res://tests/test_checklist_at_base.gd")
const MENU_BUTTON: String = ControllerSampler.MENU_BUTTON
const A: String = "right_button_lower"


## One frame as `main.gd` reads it, the session pause left out, so only the
## menu's taking of the controls keeps the stations still.
static func frame(wired_up: Array, values: Dictionary, at: float) -> void:
	var hub: HubWiring = wired_up[2]
	var checklist: ChecklistWiring = wired_up[1]
	hub.read(checklist.read((wired_up[0] as DevMenuWiring).read(values, at)))
	hub.update(false, Transform3D.IDENTITY, 1.0 / 60.0)


static func tap(wired_up: Array, at: float) -> void:
	frame(wired_up, Menu.pad_values({MENU_BUTTON: true}), at)
	frame(wired_up, Menu.pad_values(), at + 0.2)


static func press(wired_up: Array, values: Dictionary, at: float) -> void:
	frame(wired_up, values, at)
	frame(wired_up, Menu.pad_values(), at + Menu.FRAME)


static func stick(direction: Vector2) -> Dictionary:
	var values: Dictionary = Menu.pad_values()
	values["right_stick"] = direction
	return values


func test_a_tap_at_the_base_opens_the_menu_over_the_stations() -> String:
	var wired_up: Array = AtBase.wired(true)
	var menu: DevMenuWiring = wired_up[0]
	tap(wired_up, 1.0)
	var problem: String = ""
	if not menu.is_open() or menu.ignored_tap or menu.menu.model.place != DevMenuPlaces.BASE:
		problem = "open %s, ignored %s, place %s" % [menu.is_open(), menu.ignored_tap, menu.menu.model.place]
	AtBase.done(wired_up)
	return problem


func test_a_confirm_in_the_open_menu_at_the_base_never_launches_fits_or_crafts() -> String:
	var wired_up: Array = AtBase.wired(true)
	var menu: DevMenuWiring = wired_up[0]
	var hub: HubWiring = wired_up[2]
	var stations: HubStations = hub.stations
	HubStationSelect.select(stations, "launch")  # A here would launch.
	var crafted: int = hub.text.model.profile.crafted.size()
	tap(wired_up, 1.0)
	var at: float = 2.0
	for values: Dictionary in [Menu.pad_values({A: true}), stick(Vector2(1.0, 0.0)), stick(Vector2(0.0, -1.0)),
			Menu.pad_values({A: true}), Menu.pad_values({A: true}), stick(Vector2(-1.0, 0.0))]:
		press(wired_up, values, at)
		at += 0.5
	var problem: String = ""
	if hub.launching.is_launching() or not hub.is_open():
		problem = "a press in the open menu launched"
	elif stations.in_use != "launch" or hub.text.model.profile.crafted.size() != crafted:
		problem = "a press reached the stations: in use %s, crafted %d" % [stations.in_use, hub.text.model.profile.crafted.size()]
	if problem == "":  # The same A with the menu closed does launch: the setup can.
		Menu.select(menu, DevMenuSpec.KIND_CLOSE, at)
		press(wired_up, Menu.pad_values({A: true}), at + 1.0)
		frame(wired_up, Menu.pad_values(), at + 1.5)
		press(wired_up, Menu.pad_values({A: true}), at + 2.0)
		if menu.is_open() or not hub.launching.is_launching():
			problem = "after Close, A did not launch (menu open %s)" % menu.is_open()
	AtBase.done(wired_up)
	return problem


func test_at_the_base_a_waiting_build_is_the_update_entry() -> String:
	var restarts: Array[String] = []
	var update: UpdateWiring = Choices._update_wiring()
	var version: String = update.waiting_version()
	var wiring: DevMenuWiring = Menu.wired("", restarts, update)
	var hub: HubWiring = HubWiring.new()
	hub.text = AtBase.Stations._hub(AtBase.Stations._rich_profile())
	wiring.where.hub_open = hub.is_open
	Menu.tap(wiring, 1.0)
	var lines: String = " | ".join(wiring.menu.texts())
	var place: String = wiring.menu.model.place
	Menu.done(wiring)
	update.notice.free()
	if version == "" or place != DevMenuPlaces.BASE:
		return "setup: version %s, place %s" % [version, place]
	if not lines.contains("Update to %s" % version) or lines.contains("Mine"):
		return "the base's menu shows %s" % lines
	return ""


func test_the_checklist_entry_at_the_base_opens_the_page_over_the_hub() -> String:
	var wired_up: Array = AtBase.wired(true)
	var menu: DevMenuWiring = wired_up[0]
	var checklist: ChecklistWiring = wired_up[1]
	tap(wired_up, 1.0)
	var at: float = Menu.select(menu, DevMenuSpec.KIND_CHECKLIST, 2.0)
	press(wired_up, Menu.pad_values({A: true}), at)
	var problem: String = ""
	if menu.is_open() or not checklist.is_open() or not checklist.at_base():
		problem = "menu open %s, page open %s, at base %s" % [menu.is_open(), checklist.is_open(), checklist.at_base()]
	AtBase.done(wired_up)
	return problem


func test_the_place_is_read_from_the_hub_the_shaft_panel_and_the_end_screens() -> String:
	var where: DevMenuWhere = DevMenuWhere.new()
	var destroyed: DestroyedWiring = DestroyedWiring.new()
	var hub: HubWiring = HubWiring.new()
	where.attach(null, null, destroyed, hub.is_open)
	var seen: Array[String] = [where.place()]
	destroyed.sequence.update(0.0, 0.0, false)
	seen.append(where.place())
	destroyed.sequence = DestroyedSequence.new()
	destroyed.escape.choice.model = ShaftPanelModel.new()
	seen.append(where.place())
	hub.text = AtBase.Stations._hub(AtBase.Stations._rich_profile())
	seen.append(where.place())
	var want: Array[String] = [DevMenuPlaces.MINE, DevMenuPlaces.END, DevMenuPlaces.SHAFT, DevMenuPlaces.BASE]
	if seen != want:
		return "places %s, want %s" % [seen, want]
	return "" if not where.blocked() else "the base is blocked"


func test_a_menu_open_in_the_mine_closes_when_the_shaft_choice_opens() -> String:
	var restarts: Array[String] = []
	var destroyed: DestroyedWiring = DestroyedWiring.new()
	var wiring: DevMenuWiring = Menu.wired("", restarts, null, null, destroyed)
	Menu.tap(wiring, 1.0)
	var opened: bool = wiring.is_open()
	destroyed.escape.choice.model = ShaftPanelModel.new()
	Menu.wait(wiring, 1.5, 0.05)
	var closed: bool = not wiring.is_open()
	Menu.tap(wiring, 2.0)
	var at_shaft: bool = wiring.is_open() and wiring.menu.model.place == DevMenuPlaces.SHAFT
	var lines: String = " | ".join(wiring.menu.texts())
	Menu.done(wiring)
	if not opened or not closed or not at_shaft:
		return "opened %s, closed by the shaft choice %s, opened there %s" % [opened, closed, at_shaft]
	return "" if not lines.contains("Mine") else "the shaft choice's menu shows %s" % lines


func test_the_update_sign_names_a_waiting_build_only_at_the_base() -> String:
	var hub: HubWiring = HubWiring.new()
	var rig: Node3D = Node3D.new()
	var where: DevMenuWhere = DevMenuWhere.new()
	where.attach(rig, null, null, hub.is_open)
	var problem: String = ""
	if where.sign == null or where.sign.get_parent() != rig:
		problem = "no sign under the rig without a room"
	if problem == "":
		where.show_sign("abc1234")
		var in_mine: bool = where.sign.visible
		hub.text = AtBase.Stations._hub(AtBase.Stations._rich_profile())
		where.show_sign("abc1234")
		var at_base: Array[String] = where.sign.texts()
		where.show_sign("")
		var none: bool = where.sign.visible
		if in_mine or none:
			problem = "the sign shows in the mine %s or with no build %s" % [in_mine, none]
		elif at_base != ["Update available: abc1234", "Update: open the menu"]:
			problem = "the sign at the base says %s" % [at_base]
	rig.free()
	return problem
