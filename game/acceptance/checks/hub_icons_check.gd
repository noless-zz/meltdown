extends RefCounted

## The `hub_icons` check (#1365, CRW-2, GFX-2, ARC-4, DEV-6, decision record
## 0012), lane-c's file under `acceptance/checks/`. In `suites/m6/base.json`:
##
##     {"id": "hub_icons", "run": 12345, "replay": "res://...craft_and_fit_idle.replay",
##      "checks": ["no_script_errors", "hub_icons"]}
##
## After the replay the ship is lost and restart pressed, as a lost run opens
## the hub in the home base room (`hub_room_check.gd`). The shipped icon set
## must be read without error, and the whole set is drawn as a sheet on the
## first station's screen in place of its words: every icon of every group,
## none falling back to the plain marker. The frame is then drawn and saved
## as `<step id>_sheet.png` beside the replay screenshots; a screenshot that
## cannot be taken is noted and never fails the step. The sheet is taken off
## and the hub closed. Whether each icon can be told apart from the seat
## without its label stays human-checked in the headset.

const CHECK: String = "hub_icons"
const PROFILE_FILE: String = "user://meltdown_acceptance_hub_icons_profile.json"
const FITTING_FILE: String = "user://meltdown_acceptance_hub_icons_fitting.json"
const SHOT_FOLDER: String = "m6"
## In front of the screen box's face, past the words' own layer.
const FACE_M: float = 0.02
## Share of the screen's face the sheet may cover.
const FILL: float = 0.9
const ROOM_CHECK: GDScript = preload("res://acceptance/checks/hub_room_check.gd")


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	if not runner.flown():
		return [AcceptanceReport.RESULT_FAIL, "no replay was flown"]
	var main: Node = runner.main
	var level_start: LevelStart = main.get("level_start") as LevelStart
	var hub: HubWiring = main.get("hub") as HubWiring
	if level_start == null or hub == null or level_start.run == null or not level_start.run.active():
		return [AcceptanceReport.RESULT_FAIL, "the scene flies no run"]
	_remove_scratch()
	level_start.run.store = ProfileStore.new(PROFILE_FILE)
	level_start.run.ship.fittings = FittingStore.new(FITTING_FILE)
	var verdict: Array = ROOM_CHECK.judge_open_room(main, hub, measurements)
	if verdict[0] == AcceptanceReport.RESULT_PASS:
		verdict = _judge_sheet(runner, hub, step.id, measurements)
	if hub.is_open():
		hub.close()
	_remove_scratch()
	return verdict


static func _judge_sheet(runner: AcceptanceRunner, hub: HubWiring, step_id: String, measurements: Dictionary) -> Array:
	var icons: HubIcons = HubIcons.load_file()
	if icons.error != "":
		return [AcceptanceReport.RESULT_FAIL, "the icon set was refused: %s" % icons.error]
	if hub.stations == null or hub.stations.ids.is_empty():
		return [AcceptanceReport.RESULT_FAIL, "the room has no station screens"]
	var id: String = hub.stations.ids[0]
	var screen: MeshInstance3D = hub.room.get_node_or_null("Station_%s/Screen" % id) as MeshInstance3D
	if screen == null:
		return [AcceptanceReport.RESULT_FAIL, "the %s station has no screen" % id]
	var expected: int = 0
	for group: String in HubIcons.GROUPS:
		if icons.ids(group).is_empty():
			return [AcceptanceReport.RESULT_FAIL, "the icon set draws nothing for %s" % group]
		expected += icons.ids(group).size()
	var size: Vector3 = HubRoomParts.SCREEN_SIZE_M
	var sheet: HubIconSheet = HubIconSheet.new(icons, size.x * FILL, size.y * FILL, screen.layers)
	sheet.position = Vector3(0.0, 0.0, FACE_M)
	var words: Node3D = screen.get_node_or_null(HubStationScreen.NODE_NAME) as Node3D
	var words_shown: bool = words != null and words.visible
	if words != null:
		words.visible = false
	screen.add_child(sheet)
	measurements["station"] = id
	measurements["icons"] = sheet.icon_count()
	measurements["fallbacks"] = icons.fell_back.size()
	measurements["screenshot"] = _screenshot(runner, step_id)
	screen.remove_child(sheet)
	sheet.free()
	if words != null:
		words.visible = words_shown
	if sheet_count_problem(expected, measurements["icons"], icons.fell_back) != "":
		return [AcceptanceReport.RESULT_FAIL, sheet_count_problem(expected, measurements["icons"], icons.fell_back)]
	return [AcceptanceReport.RESULT_PASS, "%d icons in %d groups drawn on the %s screen" %
		[expected, HubIcons.GROUPS.size(), id]]


## "" when the sheet drew every icon of the set and none fell back.
static func sheet_count_problem(expected: int, drawn: int, fell_back: Array[String]) -> String:
	if not fell_back.is_empty():
		return "icons fell back to the plain marker: %s" % [fell_back]
	if drawn != expected:
		return "the sheet drew %d icons, the set has %d" % [drawn, expected]
	return ""


## Draws the frame and saves it; returns the path, or why there is none.
static func _screenshot(runner: AcceptanceRunner, step_id: String) -> String:
	if DisplayServer.get_name() == "headless":
		return "skipped: headless display, nothing is drawn"
	RenderingServer.force_draw(true, 0.0)
	var got: Variant = runner.screenshots.grab.call() if runner.screenshots.grab.is_valid() else "nothing to take it with"
	if not got is Image:
		return "skipped: %s" % str(got)
	var folder: String = runner.screenshots.dir.path_join(SHOT_FOLDER)
	DirAccess.make_dir_recursive_absolute(folder)
	var path: String = folder.path_join("%s_sheet.png" % step_id)
	var error: Error = (got as Image).save_png(path)
	return path if error == OK else "skipped: cannot write %s: %s" % [path, error_string(error)]


static func _remove_scratch() -> void:
	for path: String in [PROFILE_FILE, FITTING_FILE]:
		for each: String in [path, SafeFileWrite.temp_path(path)]:
			if FileAccess.file_exists(each):
				DirAccess.remove_absolute(each)
