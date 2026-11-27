extends RefCounted

## The `menu_at_base` and `menu_at_shaft` checks (#1450, CRW-2, CMF-6, DEV-8,
## decision record 0005), lane-c's file under `acceptance/checks/`. In
## `suites/m6/base.json`:
##
##     {"id": "menu_at_base", "run": 12345, "replay": "res://...craft_and_fit_idle.replay",
##      "checks": ["no_script_errors", "menu_at_base"]}
##     {"id": "menu_at_shaft", "run": 12345, "replay": "res://...run_advances.replay",
##      "checks": ["outcome", "no_script_errors", "menu_at_shaft"], "expected_outcome": "ESCAPED"}
##
## `menu_at_base`: the ship is lost and restart pressed, so the hub opens in the
## room (`hub_room_check.gd`). A build is faked waiting, the Launch station is
## taken into use, and scripted controller values go through the scene's own
## `apply_controls` and `advance_frame`: the update sign must name the build,
## a tap must open the menu at the base with the Update entry and without Level,
## Restart level, Flight test or Return to base, A in the open menu must not
## launch, and a second tap must close it with the hub still open. The profile
## and fitting are kept in scratch files.
##
## `menu_at_shaft`: the step's run has the shipped shafts. After the escape, A
## on the escape screen opens the shaft choice; a tap must open the menu there,
## the stick and A in it must leave the shaft panel's highlight and the choice
## alone, and a second tap must close it with the choice still open. Whether the
## menu reads well in front of the room stays a headset check.

const CHECK_BASE: String = "menu_at_base"
const CHECK_SHAFT: String = "menu_at_shaft"
const HubRoomCheck := preload("res://acceptance/checks/hub_room_check.gd")
const PROFILE_FILE: String = "user://meltdown_acceptance_menu_at_base_profile.json"
const FITTING_FILE: String = "user://meltdown_acceptance_menu_at_base_fitting.json"
const FAKE_VERSION: String = "a1b2c3d"
const MINE_ONLY: Array[String] = [DevMenuSpec.KIND_LEVEL, DevMenuSpec.KIND_RESTART,
	DevMenuSpec.KIND_FLIGHT_TEST, DevMenuSpec.KIND_RETURN]
## The escape screen's fade and hold are a few seconds; 30 s of frames is ample.
const WAIT_FRAMES: int = 1800
const FRAME: float = 1.0 / 72.0
const A: String = "right_button_lower"


## An update wiring that reports a newer build waiting, without a check or a download.
class WaitingUpdate:
	extends UpdateWiring

	func waiting_version() -> String:
		return "a1b2c3d"  # FAKE_VERSION; an inner class reads no outer constant here.


static func judges() -> Dictionary[String, Callable]:
	return {CHECK_BASE: _judge_base, CHECK_SHAFT: _judge_shaft}


static func _judge_base(_step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	if not runner.flown():
		return [AcceptanceReport.RESULT_FAIL, "no replay was flown"]
	var main: Node = runner.main
	var menu: DevMenuWiring = main.get("dev_menu") as DevMenuWiring
	var hub: HubWiring = main.get("hub") as HubWiring
	var level_start: LevelStart = main.get("level_start") as LevelStart
	if menu == null or hub == null or level_start == null or level_start.run == null:
		return [AcceptanceReport.RESULT_FAIL, "the scene has no dev menu, hub or run"]
	_remove_scratch()
	level_start.run.store = ProfileStore.new(PROFILE_FILE)
	level_start.run.ship.fittings = FittingStore.new(FITTING_FILE)
	var verdict: Array = HubRoomCheck.judge_open_room(main, hub, measurements)
	if verdict[0] == AcceptanceReport.RESULT_PASS and hub.stations == null:
		verdict = [AcceptanceReport.RESULT_FAIL, "the hub opened without stations"]
	if verdict[0] == AcceptanceReport.RESULT_PASS:
		var kept: UpdateWiring = menu._update
		menu._update = WaitingUpdate.new()
		verdict = judge_at_base(main, menu, hub, measurements)
		if menu.is_open():
			menu.menu.close()
		menu._update = kept
		frame(main, {})
	hub.close()
	_remove_scratch()
	return verdict


## With the hub open on its stations and a build faked waiting.
static func judge_at_base(main: Node, menu: DevMenuWiring, hub: HubWiring, measurements: Dictionary) -> Array:
	frame(main, {})
	var sign: Array[String] = menu.where.sign.texts() if menu.where.sign != null else []
	measurements["update_sign"] = " / ".join(sign)
	if sign.is_empty() or not sign[0].contains(FAKE_VERSION):
		return [AcceptanceReport.RESULT_FAIL, "the base shows no update sign naming the build: %s" % [sign]]
	HubStationSelect.select(hub.stations, "launch")  # A reaching the stations now would launch.
	tap(main)
	if not menu.is_open() or menu.menu.model.place != DevMenuPlaces.BASE:
		return [AcceptanceReport.RESULT_FAIL, "a tap at the base did not open the menu there"]
	var lines: String = " | ".join(menu.menu.texts())
	measurements["menu_rows"] = lines
	if not lines.contains("Update to %s" % FAKE_VERSION):
		return [AcceptanceReport.RESULT_FAIL, "the base's menu has no Update entry: %s" % lines]
	var shown: Array[String] = shown_kinds(menu.menu.model)
	for kind: String in MINE_ONLY:
		if shown.has(kind):
			return [AcceptanceReport.RESULT_FAIL, "the base's menu offers %s" % kind]
	frame(main, {"buttons": {A: true}})
	frame(main, {})
	if hub.launching.is_launching() or not hub.is_open():
		return [AcceptanceReport.RESULT_FAIL, "A in the open menu launched from the base"]
	tap(main)
	if menu.is_open() or not hub.is_open() or hub.launching.is_launching():
		return [AcceptanceReport.RESULT_FAIL, "the second tap left the menu %s, the hub %s" %
			["open" if menu.is_open() else "closed", "open" if hub.is_open() else "closed"]]
	return [AcceptanceReport.RESULT_PASS, "the sign names %s; the menu opened at the base with %s, A did not launch, the tap closed it" %
		[FAKE_VERSION, lines]]


static func _judge_shaft(_step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	if not runner.flown():
		return [AcceptanceReport.RESULT_FAIL, "no replay was flown"]
	var main: Node = runner.main
	var menu: DevMenuWiring = main.get("dev_menu") as DevMenuWiring
	var destroyed: DestroyedWiring = main.get("destroyed") as DestroyedWiring
	if menu == null or destroyed == null:
		return [AcceptanceReport.RESULT_FAIL, "the scene has no dev menu or end screens"]
	var waited: int = 0
	while not destroyed.escape.sequence.prompt_shown() and waited < WAIT_FRAMES:
		frame(main, {})
		waited += 1
	frame(main, {})
	frame(main, {"buttons": {DestroyedWiring.RESTART_BUTTON: true}})
	var choice: ShaftChoiceWiring = destroyed.escape.choice
	if not choice.is_open():
		return [AcceptanceReport.RESULT_FAIL, "A on the escape screen did not open the shaft choice"]
	frame(main, {})
	var highlight: int = choice.model.highlight
	tap(main)
	if not menu.is_open() or menu.menu.model.place != DevMenuPlaces.SHAFT:
		return [AcceptanceReport.RESULT_FAIL, "a tap at the shaft choice did not open the menu there"]
	measurements["menu_rows"] = " | ".join(menu.menu.texts())
	for kind: String in shown_kinds(menu.menu.model):
		if MINE_ONLY.has(kind):
			return [AcceptanceReport.RESULT_FAIL, "the shaft choice's menu offers %s" % kind]
	frame(main, {"right_stick": Vector2(0.0, -1.0)})
	frame(main, {})
	frame(main, {"buttons": {A: true}})
	frame(main, {})
	if not choice.is_open() or choice.model.highlight != highlight:
		return [AcceptanceReport.RESULT_FAIL, "the stick or A in the menu reached the shaft panel"]
	if menu.is_open():
		tap(main)  # A opened a section; the tap closes the menu from there too.
	else:
		return [AcceptanceReport.RESULT_FAIL, "A in the menu closed it"]
	if menu.is_open() or not choice.is_open():
		return [AcceptanceReport.RESULT_FAIL, "the second tap left the menu open or closed the shaft choice"]
	return [AcceptanceReport.RESULT_PASS, "the menu opened and closed at the shaft choice, which kept its highlight"]


## Every entry kind the menu offers now, in any of its lists.
static func shown_kinds(model: DevMenuModel) -> Array[String]:
	var kinds: Array[String] = []
	for index: int in model.spec.entries.size():
		if model.is_shown(index):
			kinds.append(str(model.spec.entries[index]["kind"]))
	return kinds


## A tap of the menu button: a frame down, a frame up.
static func tap(main: Node) -> void:
	frame(main, {"buttons": {ControllerSampler.MENU_BUTTON: true}})
	frame(main, {})


static func frame(main: Node, changes: Dictionary) -> void:
	var values: Dictionary = ControllerSampler.idle_values()
	for key: String in changes:
		values[key] = changes[key]
	main.call("apply_controls", values)
	main.call("advance_frame", FRAME)


static func _remove_scratch() -> void:
	for path: String in [PROFILE_FILE, FITTING_FILE]:
		for each: String in [path, SafeFileWrite.temp_path(path)]:
			if FileAccess.file_exists(each):
				DirAccess.remove_absolute(each)
