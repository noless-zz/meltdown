extends RefCounted

## The `hub_room` check (#1298, CRW-2, CMF-11, GFX-4, decision record 0012),
## lane-c's file under `acceptance/checks/`. In `suites/m6/base.json`:
##
##     {"id": "hub_room", "run": 12345, "replay": "res://...craft_and_fit_idle.replay",
##      "checks": ["no_script_errors", "hub_room"]}
##
## After the replay the ship is lost and the end screen's restart pressed
## through the scene's own `apply_controls` and `advance_frame`, as a lost run
## opens the hub, with the profile and fitting kept in scratch files. The hub
## must then be open in the home base room, with its six stations present and
## each in reach of the seat, at most 8 lights, and the camera drawing the room
## alone. Closing the hub must hide the room and give the camera back its view.
## The pilot's ship must stand on the cradle. With the room open, the frame is
## drawn and saved as `<step id>_room.png` beside the replay screenshots, so a
## reviewer can see the lit room and ship (decision record 0005); a screenshot
## that cannot be taken is noted and never fails the step. It moves the run on,
## so it is the step's last check. How the room looks and feels stays
## human-checked in the headset.

const CHECK: String = "hub_room"
const PROFILE_FILE: String = "user://meltdown_acceptance_hub_room_profile.json"
const FITTING_FILE: String = "user://meltdown_acceptance_hub_room_fitting.json"
const SHOT_FOLDER: String = "m6"
const FRAME: float = 1.0 / 72.0
## Long enough for the destroyed screen's fade and its restart prompt.
const LOSE_SECONDS: float = 5.0


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
	var verdict: Array = judge_open_room(main, hub, measurements)
	if verdict[0] == AcceptanceReport.RESULT_PASS:
		measurements["ship"] = hub.room.ship() != null
		measurements["screenshot"] = _screenshot(runner, step.id)
		if hub.room.ship() == null:
			verdict = [AcceptanceReport.RESULT_FAIL, "the cradle holds no ship"]
	hub.close()
	if verdict[0] == AcceptanceReport.RESULT_PASS and hub.room.visible:
		verdict = [AcceptanceReport.RESULT_FAIL, "closing the hub left the room showing"]
	_remove_scratch()
	return verdict


## Loses the ship, presses restart and judges the room the hub opens in.
static func judge_open_room(main: Node, hub: HubWiring, measurements: Dictionary) -> Array:
	(main.get("session") as LocalSession).sim.ships[0].hull = 0.0
	for i: int in ceili(LOSE_SECONDS / FRAME):
		_frame(main, {})
	_frame(main, {DestroyedWiring.RESTART_BUTTON: true})
	_frame(main, {})
	if not hub.is_open():
		return [AcceptanceReport.RESULT_FAIL, "losing the ship did not open the hub"]
	var room: HubRoom = hub.room
	if room == null or not room.visible:
		return [AcceptanceReport.RESULT_FAIL, "the hub opened without its room: %s" %
			("no room" if room == null else room.spec.error)]
	if not room.hides_mine():
		return [AcceptanceReport.RESULT_FAIL, "the camera still draws the mine behind the room"]
	var points: Dictionary[String, Vector3] = room.station_points()
	measurements["stations"] = points.size()
	measurements["lights"] = room.light_count()
	for id: String in HubRoomSpec.STATION_IDS:
		if not points.has(id):
			return [AcceptanceReport.RESULT_FAIL, "the room has no %s station" % id]
		var problem: String = room.spec.reach_problem(points[id])
		if problem != "":
			return [AcceptanceReport.RESULT_FAIL, "the %s station is out of reach: %s" % [id, problem]]
	if room.light_count() > HubRoomSpec.MAX_LIGHTS:
		return [AcceptanceReport.RESULT_FAIL, "the room has %d lights, over %d" % [room.light_count(),
			HubRoomSpec.MAX_LIGHTS]]
	return [AcceptanceReport.RESULT_PASS, "a lost run opens the hub in the room; %d stations in reach, %d lights" %
		[points.size(), room.light_count()]]


static func _frame(main: Node, buttons: Dictionary) -> void:
	var values: Dictionary = ControllerSampler.idle_values()
	values["buttons"] = buttons
	main.call("apply_controls", values)
	main.call("advance_frame", FRAME)


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
	var path: String = folder.path_join("%s_room.png" % step_id)
	var error: Error = (got as Image).save_png(path)
	return path if error == OK else "skipped: cannot write %s: %s" % [path, error_string(error)]


static func _remove_scratch() -> void:
	for path: String in [PROFILE_FILE, FITTING_FILE]:
		for each: String in [path, SafeFileWrite.temp_path(path)]:
			if FileAccess.file_exists(each):
				DirAccess.remove_absolute(each)
