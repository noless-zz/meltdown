extends RefCounted

## The hub closes the dev menu (#1170, CRW-2, DEV-6, PLT-5, decision record
## 0009): a menu open when the hub opens closes and a restart it was fading to
## is dropped; a tap with the hub open is ignored; once the hub closes the tap
## opens the menu again. No scene: the hub is a flag the test sets.

const SCRATCH_DIR: String = "user://test_dev_menu_hub"
const FRAME: float = 1.0 / 72.0


## Whether the stand-in hub is open; the wiring reads it through `is_open`.
class HubFlag:
	var open: bool = false

	func is_open() -> bool:
		return open


static func _wired(hub: HubFlag, restarts: Array[String]) -> DevMenuWiring:
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	var level_start: LevelStart = LevelStart.new()
	level_start.source = "res://data/levels/g2_level.json"
	var wiring: DevMenuWiring = DevMenuWiring.new()
	wiring.corner_store = PanelCorner.new(SCRATCH_DIR + "/panel.json")
	var restart: Callable = func() -> void: restarts.append(level_start.source)
	var levels: Array[String] = ["res://data/levels/g2_level.json"]
	wiring.attach(null, null, level_start, restart, null, null,
		DevMenu.new(DevMenuSpec.load_file(), levels), hub.is_open)
	return wiring


static func _values(buttons: Dictionary = {}) -> Dictionary:
	var values: Dictionary = ControllerSampler.idle_values()
	values["buttons"] = buttons
	return values


## A tap of the menu button at `at`: down, then up a fifth of a second later.
static func _tap(wiring: DevMenuWiring, at: float) -> void:
	wiring.read(_values({ControllerSampler.MENU_BUTTON: true}), at)
	wiring.read(_values(), at + 0.2)


## Idle frames from `from` for `seconds`.
static func _idle(wiring: DevMenuWiring, from: float, seconds: float) -> float:
	var now: float = from
	while now < from + seconds:
		wiring.read(_values(), now)
		now += FRAME
	return now


func test_the_hub_opening_closes_an_open_menu() -> String:
	var hub: HubFlag = HubFlag.new()
	var restarts: Array[String] = []
	var wiring: DevMenuWiring = _wired(hub, restarts)
	_tap(wiring, 1.0)
	if not wiring.is_open():
		wiring.menu.free()
		return "the tap did not open the menu before the hub"
	hub.open = true
	_idle(wiring, 1.5, 0.1)
	var open: bool = wiring.is_open()
	wiring.menu.free()
	if open:
		return "the menu stayed open over the hub"
	return ""


func test_a_restart_waiting_when_the_hub_opens_is_dropped() -> String:
	var hub: HubFlag = HubFlag.new()
	var restarts: Array[String] = []
	var wiring: DevMenuWiring = _wired(hub, restarts)
	_tap(wiring, 1.0)
	var now: float = 1.5
	while wiring.menu.model.kind() != DevMenuSpec.KIND_RESTART:
		var down: Dictionary = _values()
		down["right_stick"] = Vector2(0.0, -1.0)
		wiring.read(down, now)
		wiring.read(_values(), now + FRAME)
		now += 0.1
	wiring.read(_values({"right_button_lower": true}), now)
	wiring.read(_values(), now + FRAME)
	now = _idle(wiring, now + 2.0 * FRAME, DevMenuWiring.FADE_SECONDS * 0.3)
	var fading: bool = wiring.alpha > 0.0
	hub.open = true
	_idle(wiring, now, DevMenuWiring.FADE_SECONDS * 3.0)
	var open: bool = wiring.is_open()
	wiring.menu.free()
	if not fading:
		return "the restart did not start its fade (test setup)"
	if not restarts.is_empty():
		return "a restart picked before the hub opened flew behind it: %s" % [restarts]
	if wiring.alpha != 0.0:
		return "the menu's fade did not end with the hub open (alpha %.2f)" % wiring.alpha
	if open:
		return "the menu stayed open over the hub"
	return ""


func test_a_tap_with_the_hub_open_does_not_open_the_menu() -> String:
	var hub: HubFlag = HubFlag.new()
	hub.open = true
	var restarts: Array[String] = []
	var wiring: DevMenuWiring = _wired(hub, restarts)
	_tap(wiring, 1.0)
	_tap(wiring, 2.0)
	var open: bool = wiring.is_open()
	var blocked: bool = wiring.blocked()
	wiring.menu.free()
	if open:
		return "a tap opened the menu over the hub"
	if not blocked:
		return "blocked() is false with the hub open"
	return ""


func test_once_the_hub_closes_the_tap_opens_the_menu_again() -> String:
	var hub: HubFlag = HubFlag.new()
	hub.open = true
	var restarts: Array[String] = []
	var wiring: DevMenuWiring = _wired(hub, restarts)
	_tap(wiring, 1.0)
	hub.open = false  # Launch or resume closes the hub.
	_tap(wiring, 2.0)
	var open: bool = wiring.is_open()
	wiring.menu.free()
	if not open:
		return "after the hub closed, the tap did not open the menu"
	return ""


func test_without_a_hub_nothing_is_blocked() -> String:
	var wiring: DevMenuWiring = DevMenuWiring.new()
	wiring.attach(null, null, null, Callable(), null, null, DevMenu.new(DevMenuSpec.load_file(), []))
	var blocked: bool = wiring.hub_is_open() or wiring.blocked()
	wiring.menu.free()
	if blocked:
		return "a wiring with no hub reports the hub open"
	return ""


func test_the_main_scene_hands_the_hub_to_the_menu() -> String:
	var text: String = FileAccess.get_file_as_string("res://main.gd")
	if not text.contains("destroyed, null, hub.is_open"):  # Then the session the menu pauses (#1245).
		return "main.gd does not pass hub.is_open to dev_menu.attach"
	var lines: int = text.split("\n").size() - 1
	if lines > 300:
		return "main.gd has %d lines, more than 300" % lines
	return ""
