extends RefCounted

## The `menu_sounds` check (#1457, AUD-1, CRW-2, DEV-6, decision record 0005),
## lane-c's file under `acceptance/checks/`. In `suites/m6/menu.json`:
##
##     {"id": "menu_sounds", "replay": "res://acceptance/replays/basic_flight.replay",
##      "checks": ["no_script_errors", "menu_sounds"]}
##
## After the flight, scripted controller values go through the scene's own
## `apply_controls` and `advance_frame`: a tap opens the menu in the mine, the
## stick steps down twice (onto the Mine section), A opens that section, the
## stick changes the Level value, and a second tap closes the menu. The menu's
## requested-sound log (`DevMenuWiring.sounds`) must then hold open, point,
## point, confirm, change and back, in that order and nothing else. The gaps
## run on the steady clock, so the check waits a little longer than the longest
## gap between presses, as a pilot's hand does. Whether the sounds match the
## base's stations and are not tiring stays a headset check.

const CHECK: String = "menu_sounds"
const EXPECTED: Array[String] = ["open", "point", "point", "confirm", "change", "back"]
const FRAME: float = 1.0 / 72.0
const A: String = "right_button_lower"
## Longer than any `min_gap_s` in `menu_sounds.json` between the presses.
const PAUSE_MSEC: int = 300


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(_step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	if not runner.flown():
		return [AcceptanceReport.RESULT_FAIL, "no replay was flown"]
	var main: Node = runner.main
	var menu: DevMenuWiring = main.get("dev_menu") as DevMenuWiring if main != null else null
	if menu == null or menu.sounds == null:
		return [AcceptanceReport.RESULT_FAIL, "the scene's dev menu has no sounds"]
	if menu.sounds.table.error != "":
		return [AcceptanceReport.RESULT_FAIL, "the menu sounds were rejected: %s" % menu.sounds.table.error]
	_frame(main, {})
	menu.sounds.requested.clear()
	_tap(main)
	if not menu.is_open() or menu.menu.model.place != DevMenuPlaces.MINE:
		return [AcceptanceReport.RESULT_FAIL, "a tap after the flight did not open the menu in the mine"]
	var down: Dictionary = {"right_stick": Vector2(0.0, -1.0)}
	for values: Dictionary in [down, down, {"buttons": {A: true}}, {"right_stick": Vector2(1.0, 0.0)}]:
		OS.delay_msec(PAUSE_MSEC)
		_frame(main, values)
		_frame(main, {})
	OS.delay_msec(PAUSE_MSEC)
	_tap(main)
	var heard: Array[String] = menu.sounds.requested.duplicate()
	measurements["menu_sounds"] = ",".join(heard)
	if menu.is_open():
		menu.menu.close()
		_frame(main, {})
		return [AcceptanceReport.RESULT_FAIL, "the second tap left the menu open"]
	if heard != EXPECTED:
		return [AcceptanceReport.RESULT_FAIL, "the menu requested %s, expected %s" % [heard, EXPECTED]]
	return [AcceptanceReport.RESULT_PASS, "open, two steps, a section, a value and close requested %s" % ",".join(heard)]


## A tap of the menu button: a frame down, a frame up.
static func _tap(main: Node) -> void:
	_frame(main, {"buttons": {ControllerSampler.MENU_BUTTON: true}})
	_frame(main, {})


static func _frame(main: Node, changes: Dictionary) -> void:
	var values: Dictionary = ControllerSampler.idle_values()
	for key: String in changes:
		values[key] = changes[key]
	main.call("apply_controls", values)
	main.call("advance_frame", FRAME)
