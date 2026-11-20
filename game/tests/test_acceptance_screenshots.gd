extends RefCounted

## Acceptance screenshots at named steps (#718, DEV-6, GFX-2): the step keys
## are parsed and checked, the report lists each path or why it was skipped,
## a skipped screenshot never fails its step, and taking screenshots never
## changes the replay's final hash (ARC-2).

const REPLAY: String = "res://acceptance/replays/basic_flight.replay"
const M1_HASH: int = 861662111
const DIR: String = "user://test_acceptance_screenshots"
const FRAME_LIMIT: int = 20000


func _parse(step_json: String) -> AcceptanceSuite:
	return AcceptanceSuite.parse_json("{\"name\": \"t718\", \"steps\": [%s]}" % step_json)


func _step_with(extra: String) -> String:
	return "{\"id\": \"fly\", \"replay\": \"%s\", \"checks\": [\"final_hash\"], \"expected_hash\": %d%s}" % [
		REPLAY, M1_HASH, extra]


static func _image() -> Variant:
	return Image.create(4, 4, false, Image.FORMAT_RGB8)


static func _no_image() -> Variant:
	return "dummy renderer"


func _run(step_json: String, grab: Callable) -> AcceptanceRunner:
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = func(_code: int) -> void: pass
	var shots: AcceptanceScreenshots = AcceptanceScreenshots.new()
	shots.grab = grab
	shots.dir = DIR
	runner.screenshots = shots
	var suites: Array[AcceptanceSuite] = [_parse(step_json)]
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	runner.setup(scene.instantiate(), suites, null)
	var frames: int = 0
	while not runner.finished and frames < FRAME_LIMIT:
		runner.process_frame()
		frames += 1
	return runner


func _done(runner: AcceptanceRunner) -> void:
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	var folder: String = DIR.path_join("t718")
	if DirAccess.dir_exists_absolute(folder):
		for file: String in DirAccess.get_files_at(folder):
			DirAccess.remove_absolute(folder.path_join(file))
		DirAccess.remove_absolute(folder)
	if DirAccess.dir_exists_absolute(DIR):
		DirAccess.remove_absolute(DIR)
	runner.main.free()
	runner.free()


func test_step_parses_ticks_and_end() -> String:
	var suite: AcceptanceSuite = _parse(_step_with(", \"screenshot_at_ticks\": [0, 30], \"screenshot_at_end\": true"))
	if suite.error != "":
		return suite.error
	var step: AcceptanceStep = suite.steps[0]
	if step.screenshot_ticks != [0, 30] or not step.screenshot_at_end:
		return "parsed ticks %s, end %s" % [step.screenshot_ticks, step.screenshot_at_end]
	var plain: AcceptanceSuite = _parse(_step_with(""))
	if not plain.steps[0].screenshot_ticks.is_empty() or plain.steps[0].screenshot_at_end:
		return "a step without the keys wants screenshots"
	return ""


func test_bad_ticks_are_rejected_naming_them() -> String:
	var length: int = AcceptanceScreenshots.replay_length(REPLAY)
	if length <= 0 or length >= AcceptanceScreenshots.MAX_TICK:
		return "the test replay's length %d was not read" % length
	var cases: Dictionary[String, String] = {
		", \"screenshot_at_ticks\": [3, -1]": "steps[0].screenshot_at_ticks[1]: -1 is negative",
		", \"screenshot_at_ticks\": [%d]" % (length + 1): "steps[0].screenshot_at_ticks[0]: %d is past the end" % (length + 1),
		", \"screenshot_at_ticks\": [2.5]": "steps[0].screenshot_at_ticks[0]: must be a whole number",
		", \"screenshot_at_ticks\": [true]": "steps[0].screenshot_at_ticks[0]: must be a whole number",
		", \"screenshot_at_ticks\": [4, 4]": "steps[0].screenshot_at_ticks[1]: 4 is listed twice",
		", \"screenshot_at_ticks\": []": "steps[0].screenshot_at_ticks: must be a list",
		", \"screenshot_at_end\": 1": "steps[0].screenshot_at_end: must be true or false",
	}
	for extra: String in cases:
		var suite: AcceptanceSuite = _parse(_step_with(extra))
		if not suite.error.begins_with(cases[extra]):
			return "%s gave '%s'" % [extra, suite.error]
	if _parse(_step_with(", \"screenshot_at_ticks\": [%d]" % length)).error != "":
		return "the replay's last tick was rejected"
	var no_replay: AcceptanceSuite = _parse("{\"id\": \"x\", \"checks\": [\"xr_session\"], \"screenshot_at_end\": true}")
	if not no_replay.error.begins_with("steps[0].replay: needed by screenshots"):
		return "a screenshot without a replay gave '%s'" % no_replay.error
	return ""


func test_report_lists_each_screenshot_path() -> String:
	var runner: AcceptanceRunner = _run(_step_with(", \"screenshot_at_ticks\": [5], \"screenshot_at_end\": true"), _image)
	var problem: String = ""
	var length: int = AcceptanceScreenshots.replay_length(REPLAY)
	var step: Dictionary = runner.reports[0].steps[0] if not runner.reports.is_empty() else {}
	var shots: Array = step.get("screenshots", [])
	if step.get("result") != AcceptanceReport.RESULT_PASS:
		problem = "the step is %s: %s" % [step.get("result"), "\n".join(runner.messages)]
	elif shots.size() != 2 or shots[0]["tick"] != 5 or shots[1]["tick"] != length:
		problem = "screenshots listed: %s" % [shots]
	else:
		for index: int in shots.size():
			var expected: String = "%s/t718/fly_%d.png" % [DIR, [5, length][index]]
			if shots[index].get("path") != expected or not FileAccess.file_exists(expected):
				problem = "screenshot %d is %s, expected a file at %s" % [index, shots[index], expected]
			elif shots[index].get("view") != AcceptanceScreenshots.VIEW_FLAT:
				problem = "the view is not named: %s" % shots[index]
		if problem == "" and not runner.reports[0].to_json().contains("fly_5.png"):
			problem = "the report JSON does not list the path"
	_done(runner)
	return problem


func test_screenshot_that_cannot_be_taken_is_skipped_not_failed() -> String:
	var runner: AcceptanceRunner = _run(_step_with(", \"screenshot_at_end\": true"), _no_image)
	var problem: String = ""
	var step: Dictionary = runner.reports[0].steps[0]
	var shots: Array = step.get("screenshots", [])
	if step["result"] != AcceptanceReport.RESULT_PASS or runner.exit_code != AcceptanceRunner.EXIT_PASS:
		problem = "a skipped screenshot failed the step: %s" % step
	elif shots.size() != 1 or shots[0].get("skipped") != "dummy renderer" or shots[0].has("path"):
		problem = "the skip is listed as %s" % [shots]
	_done(runner)
	return problem


func test_screenshots_leave_the_final_hash_unchanged() -> String:
	var hashes: Array = []
	for extra: String in ["", ", \"screenshot_at_ticks\": [0, 1, 7, 40], \"screenshot_at_end\": true"]:
		var runner: AcceptanceRunner = _run(_step_with(extra), _image)
		hashes.append(runner.reports[0].steps[0]["measurements"].get("final_hash"))
		hashes.append((runner.main.get("session") as LocalSession).sim.state_hash())
		_done(runner)
	if hashes[0] != M1_HASH or hashes[2] != M1_HASH or hashes[1] != hashes[3]:
		return "hashes without and with screenshots: %s" % [hashes]
	return ""


func test_unreached_ticks_are_listed_as_skipped() -> String:
	var step: AcceptanceStep = AcceptanceStep.new()
	step.id = "fly"
	step.screenshot_ticks = [9]
	step.screenshot_at_end = true
	var shots: AcceptanceScreenshots = AcceptanceScreenshots.new()
	shots.begin("t718", step)
	var entries: Array[Dictionary] = shots.finish_step()
	if entries.size() != 2 or not entries[0].has("skipped") or not entries[1].has("skipped"):
		return "a step that never flew listed %s" % [entries]
	if not shots.finish_step().is_empty():
		return "finish_step did not clear the step"
	return ""


func test_headless_grab_gives_a_reason() -> String:
	if DisplayServer.get_name() != "headless":
		return ""
	var got: Variant = AcceptanceScreenshots.grab_main_viewport()
	if not got is String or not str(got).contains("headless"):
		return "the headless grab gave %s" % [got]
	return ""


func test_m1_and_m2_take_end_screenshots() -> String:
	var wanted: Dictionary[String, String] = {"m1": "flight_axes", "m2": "ship_destroyed_in_test_tunnel"}
	for suite_name: String in wanted:
		var suite: AcceptanceSuite = AcceptanceSuite.load_named(suite_name)[0]
		if suite.error != "":
			return suite.error
		for step: AcceptanceStep in suite.steps:
			if step.id == wanted[suite_name] and not step.screenshot_at_end:
				return "%s %s takes no end screenshot" % [suite_name, step.id]
		if suite_name == "m2" and suite.steps[0].id != wanted["m2"]:
			return "m2's first step is %s" % suite.steps[0].id
	return ""
