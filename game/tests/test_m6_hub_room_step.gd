extends RefCounted

## The m6 `hub_room` step (#1369, CRW-2, GFX-2, decision record 0005): after
## the replay a lost run opens the hub in the home base room, the ship stands on
## the cradle, and the open room is saved as two screenshots, wide from the
## seat and towards the ship (#1397), only once the room's arrival fade is
## clear (#1425). Headless, the screenshots are noted as skipped and never fail
## the step.

const SUITE_PATH: String = "res://acceptance/suites/m6.json"
const STEP_ID: String = "hub_room"
## The idle replay, the destroyed screen's fade and the restart.
const FRAME_LIMIT: int = 20000

var _quit_codes: Array[int] = []


func test_the_step_passes_with_the_ship_and_notes_the_screenshot() -> String:
	var runner: AcceptanceRunner = _run()
	var problem: String = ""
	if runner.reports.is_empty() or not runner.reports[0].passed():
		problem = "exit %d: %s" % [runner.exit_code, "\n".join(runner.messages)]
	else:
		var measured: Dictionary = runner.reports[0].steps[0]["measurements"]
		var shot: String = str(measured.get("screenshot", ""))
		var ship_shot: String = str(measured.get("screenshot_ship", ""))
		if measured.get("ship") != true:
			problem = "no ship measured on the cradle: %s" % measured
		elif not measured.has("room_fade") or float(measured["room_fade"]) != 0.0:
			problem = "the pictures were taken through the arrival fade: %s" % measured.get("room_fade")
		elif DisplayServer.get_name() == "headless" and not (shot.begins_with("skipped") and ship_shot.begins_with("skipped")):
			problem = "a headless run claims a screenshot: %s, %s" % [shot, ship_shot]
		elif DisplayServer.get_name() != "headless" and not (shot.begins_with("skipped") or shot.ends_with("%s_room.png" % STEP_ID)):
			problem = "the screenshot was saved under another name: %s" % shot
		elif DisplayServer.get_name() != "headless" and not (ship_shot.begins_with("skipped") or ship_shot.ends_with("%s_room_ship.png" % STEP_ID)):
			problem = "the ship screenshot was saved under another name: %s" % ship_shot
		elif (runner.main.get("hub") as HubWiring).is_open():
			problem = "the check left the hub open"
	_done(runner)
	return problem


func _on_quit(code: int) -> void:
	_quit_codes.append(code)


func _run() -> AcceptanceRunner:
	_quit_codes.clear()
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	var kept: Array[AcceptanceStep] = []
	for found: AcceptanceStep in suite.steps:
		if found.id == STEP_ID:
			kept.append(found)
	suite.steps = kept
	var suites: Array[AcceptanceSuite] = [suite]
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = _on_quit
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	runner.setup(main, suites, null)
	var frames: int = 0
	while not runner.finished and frames < FRAME_LIMIT:
		runner.process_frame()
		frames += 1
	return runner


func _done(runner: AcceptanceRunner) -> void:
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	if runner.main != null:
		runner.main.free()
	runner.free()
