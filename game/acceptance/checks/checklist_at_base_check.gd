extends RefCounted

## The `checklist_at_base` check (#1408, DEV-6, DEV-7, ARC-3, CMF-8), lane-c's
## file under `acceptance/checks/`. In `suites/m6/base.json`:
##
##     {"id": "checklist_at_base", "run": 12345, "replay": "res://...craft_and_fit_idle.replay",
##      "checks": ["no_script_errors", "checklist_at_base"]}
##
## After the replay the ship is lost and restart pressed, so the hub opens in
## the home base room (`hub_room_check.gd`'s `judge_open_room`). With the
## shipped checklist pinned, a tap of the menu button through the scene's own
## `apply_controls` and `advance_frame` must open the dev menu at the base, and
## its Test checklist entry the page (#1450 replaced #1408's tap that opened the
## page directly); a stick push while
## it is open must not move the stations' highlight; A on the first step with
## a `station` action must pin the page and take that station into use. The
## checklist runs on a fresh session under a scratch name, so the owner's
## marks are untouched, and the profile and fitting are kept in scratch files.
## A release build must show no page. It moves the run on, so it is the
## step's last check.

const CHECK: String = "checklist_at_base"
const HubRoomCheck := preload("res://acceptance/checks/hub_room_check.gd")
const PROFILE_FILE: String = "user://meltdown_acceptance_checklist_at_base_profile.json"
const FITTING_FILE: String = "user://meltdown_acceptance_checklist_at_base_fitting.json"
const SCRATCH_PREFIX: String = "user://acceptance_checklist_at_base_"
const FRAME: float = 1.0 / 72.0


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(_step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	if not runner.flown():
		return [AcceptanceReport.RESULT_FAIL, "no replay was flown"]
	var main: Node = runner.main
	var checklist: ChecklistWiring = main.get("checklist") as ChecklistWiring
	var hub: HubWiring = main.get("hub") as HubWiring
	var level_start: LevelStart = main.get("level_start") as LevelStart
	if checklist == null or hub == null or level_start == null or level_start.run == null:
		return [AcceptanceReport.RESULT_FAIL, "the scene has no checklist, hub or run"]
	if not checklist.available:
		return [AcceptanceReport.RESULT_PASS if checklist.page == null else AcceptanceReport.RESULT_FAIL,
			"release build: %s" % ("no checklist page" if checklist.page == null else "a checklist page exists")]
	if checklist.checklist == null or checklist.page == null:
		return [AcceptanceReport.RESULT_FAIL, "no checklist attached; the shipped file was refused or missing"]
	_remove_scratch()
	level_start.run.store = ProfileStore.new(PROFILE_FILE)
	level_start.run.ship.fittings = FittingStore.new(FITTING_FILE)
	var verdict: Array = HubRoomCheck.judge_open_room(main, hub, measurements)
	if verdict[0] == AcceptanceReport.RESULT_PASS and hub.stations == null:
		verdict = [AcceptanceReport.RESULT_FAIL, "the hub opened without stations"]
	if verdict[0] == AcceptanceReport.RESULT_PASS:
		var kept: Array = [checklist.session, checklist.model, checklist.store.prefix]
		checklist.session = ChecklistSession.new(checklist.checklist)
		checklist.model = ChecklistPageModel.new(checklist.session)
		checklist.store.prefix = SCRATCH_PREFIX
		verdict = judge_at_base(main, checklist, hub.stations, measurements)
		checklist.close()
		_frame(main, {})  # Lets go of the page's pause.
		DirAccess.remove_absolute(checklist.store.path_for(checklist.checklist.id))
		checklist.session = kept[0]
		checklist.model = kept[1]
		checklist.store.prefix = kept[2]
	hub.close()
	_remove_scratch()
	return verdict


## Pins the page, taps it open, pushes the stick and runs a station action.
static func judge_at_base(main: Node, checklist: ChecklistWiring, stations: HubStations,
		measurements: Dictionary) -> Array:
	checklist.pin()
	_frame(main, {"buttons": {ControllerSampler.MENU_BUTTON: true}})
	_frame(main, {})
	var menu: DevMenuWiring = main.get("dev_menu") as DevMenuWiring
	if menu == null or not menu.is_open():
		return [AcceptanceReport.RESULT_FAIL, "a tap at the base did not open the dev menu"]
	for press: int in 32:  # The entry is on the top list: down until it is highlighted.
		if menu.menu.model.kind() == DevMenuSpec.KIND_CHECKLIST:
			break
		_frame(main, {"right_stick": Vector2(0.0, -1.0)})
		_frame(main, {})
	_frame(main, {"buttons": {"right_button_lower": true}})
	_frame(main, {})
	if not checklist.is_open():
		return [AcceptanceReport.RESULT_FAIL, "the menu's Test checklist entry at the base did not open the page"]
	var highlighted: String = stations.highlighted_id()
	_frame(main, {"right_stick": Vector2(1.0, 0.0)})
	_frame(main, {})
	if stations.highlighted_id() != highlighted:
		return [AcceptanceReport.RESULT_FAIL, "the stick moved the stations behind the open page (%s to %s)" %
			[highlighted, stations.highlighted_id()]]
	var index: int = -1
	for i: int in checklist.checklist.steps.size():
		if checklist.checklist.steps[i].action == ChecklistStep.ACTION_STATION:
			index = i
			break
	if index < 0:
		return [AcceptanceReport.RESULT_FAIL, "the shipped checklist has no station action"]
	var step: ChecklistStep = checklist.checklist.steps[index]
	checklist.model.show_step(index)
	checklist.model.choice = checklist.model.choices().find(ChecklistPageModel.DO)
	_frame(main, {"buttons": {"right_button_lower": true}})
	_frame(main, {})
	measurements["station_action"] = step.id
	measurements["station_in_use"] = stations.in_use
	if not checklist.is_pinned() or stations.in_use != step.action_value:
		return [AcceptanceReport.RESULT_FAIL, "%s's action left the page %s and %s in use, want %s" %
			[step.id, "pinned" if checklist.is_pinned() else "unpinned", stations.in_use, step.action_value]]
	return [AcceptanceReport.RESULT_PASS, "the menu's entry at the base opened the pinned page, the stick stayed off the stations, and %s opened the %s station" %
		[step.id, step.action_label]]


static func _frame(main: Node, changes: Dictionary) -> void:
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
