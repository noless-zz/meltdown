extends RefCounted

## The development menu's sounds through `DevMenuWiring.read` (#1457, AUD-1,
## CRW-2, ARC-3, MP-2): open, two steps down, a section, a value change and a
## tap to close request the expected sounds in order; a fast scroll is held to
## the gap; a rejected file leaves the menu silent; the sounds hang under the
## panel and keep playing while the menu pauses the session; and the base's
## menu sounds the same. Nothing here touches the simulation.

const Menu := preload("res://tests/test_dev_menu_wiring.gd")
const AtBase := preload("res://tests/test_checklist_at_base.gd")
const BaseMenu := preload("res://tests/test_dev_menu_at_base.gd")
const A: String = "right_button_lower"
## The sounds of: open, down, down (onto Mine), A (into Mine), right (the Level value), tap.
const WALK: Array[String] = ["open", "point", "point", "confirm", "change", "back"]


static func _stick(direction: Vector2) -> Dictionary:
	var values: Dictionary = Menu.pad_values()
	values["right_stick"] = direction
	return values


## The walk above in the mine, one second between presses.
static func _walk(wiring: DevMenuWiring) -> void:
	Menu.tap(wiring, 1.0)
	Menu.press(wiring, _stick(Vector2(0.0, -1.0)), 2.0)
	Menu.press(wiring, _stick(Vector2(0.0, -1.0)), 3.0)
	Menu.confirm(wiring, 4.0)
	Menu.press(wiring, _stick(Vector2(1.0, 0.0)), 5.0)
	Menu.tap(wiring, 6.0)


func test_a_walk_through_the_menu_requests_each_sound_in_order() -> String:
	var restarts: Array[String] = []
	var wiring: DevMenuWiring = Menu.wired("", restarts)
	_walk(wiring)
	var heard: Array[String] = wiring.sounds.requested.duplicate()
	var still_open: bool = wiring.is_open()
	Menu.done(wiring)
	if still_open:
		return "the second tap left the menu open"
	if heard != WALK:
		return "requested %s, expected %s" % [heard, WALK]
	return ""


func test_a_fast_scroll_is_held_to_the_point_gap() -> String:
	var restarts: Array[String] = []
	var wiring: DevMenuWiring = Menu.wired("", restarts)
	Menu.tap(wiring, 1.0)
	for i: int in 4:  # Four steps 2/72 s apart, well inside point's gap.
		Menu.press(wiring, _stick(Vector2(0.0, -1.0)), 2.0 + i * 2.0 * Menu.FRAME)
	var heard: Array[String] = wiring.sounds.requested.duplicate()
	Menu.done(wiring)
	if heard.count("point") < 1 or heard.count("point") > 2:
		return "four fast steps requested %s" % [heard]
	return ""


func test_a_rejected_file_leaves_the_menu_silent_and_working() -> String:
	var restarts: Array[String] = []
	var wiring: DevMenuWiring = Menu.wired("", restarts)
	wiring.sounds.table = MenuSoundTable.parse('{"voices": 2, "sound": {}}')
	_walk(wiring)
	var heard: Array[String] = wiring.sounds.requested.duplicate()
	var error: String = wiring.sounds.table.error
	var still_open: bool = wiring.is_open()
	Menu.done(wiring)
	if not error.contains("sound") or not heard.is_empty() or still_open:
		return "error %s, requested %s, open %s" % [error, heard, still_open]
	return ""


func test_the_sounds_hang_under_the_panel_and_play_while_paused() -> String:
	var restarts: Array[String] = []
	var wiring: DevMenuWiring = Menu.wired("", restarts)
	var sounds: MenuSounds = wiring.sounds
	var problem: String = ""
	if sounds.get_parent() != wiring.menu or sounds.position != Vector3.ZERO:
		problem = "the sounds are not at the menu panel"
	elif sounds.process_mode != Node.PROCESS_MODE_ALWAYS:
		problem = "the sounds stop while the session is paused"
	for player: Node in sounds.get_children():
		if problem == "" and player.process_mode != Node.PROCESS_MODE_ALWAYS:
			problem = "%s stops while the session is paused" % player.name
	if problem == "" and sounds.get_child_count() != sounds.table.voices:
		problem = "%d voices, the file asks for %d" % [sounds.get_child_count(), sounds.table.voices]
	Menu.done(wiring)
	return problem


func test_the_menu_at_the_base_sounds_the_same() -> String:
	var wired_up: Array = AtBase.wired(true)
	var menu: DevMenuWiring = wired_up[0]
	BaseMenu.tap(wired_up, 1.0)
	BaseMenu.press(wired_up, BaseMenu.stick(Vector2(0.0, -1.0)), 2.0)
	BaseMenu.press(wired_up, Menu.pad_values({A: true}), 3.0)
	BaseMenu.tap(wired_up, 4.0)
	var heard: Array[String] = menu.sounds.requested.duplicate()
	var place: String = menu.menu.model.place
	AtBase.done(wired_up)
	if place != DevMenuPlaces.BASE:
		return "the menu opened at %s, not the base" % place
	if heard.size() != 4 or heard[0] != "open" or heard[1] != "point" or heard[2] != "confirm" or heard[3] != "back":
		return "at the base the menu requested %s" % [heard]
	return ""
