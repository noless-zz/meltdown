extends RefCounted

## The m6 `hull_warning` step (#1456, AUD-1, CMB-2, DEV-6, decision record
## 0005): the ship is worn down and lost on the `low_hull_test_tunnel`
## replay; the low-hull tone must have been asked for at least twice while the
## ship had hull, and not again under the end screen.

const SUITE_PATH: String = "res://acceptance/suites/m6.json"
const PART_PATH: String = "res://acceptance/suites/m6/sound.json"
const STEP_ID: String = "hull_warning"
const CHECK: GDScript = preload("res://acceptance/checks/hull_warning_check.gd")
const FRAME_LIMIT: int = 20000


func test_the_check_is_registered_and_the_step_is_in_the_sound_part() -> String:
	if not AcceptanceCheckFiles.judges().has(CHECK.CHECK):
		return "no check file judges %s: %s" % [CHECK.CHECK, AcceptanceCheckFiles.problem()]
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	if suite.error != "":
		return suite.error
	if not FileAccess.get_file_as_string(PART_PATH).contains("\"id\": \"%s\"" % STEP_ID):
		return "%s has no step %s" % [PART_PATH, STEP_ID]
	for found: AcceptanceStep in suite.steps:
		if found.id == STEP_ID:
			return "" if found.checks.has(CHECK.CHECK) else "the step checks %s" % [found.checks]
	return "%s has no step %s" % [SUITE_PATH, STEP_ID]


func test_the_judge() -> String:
	var cases: Array[Array] = [
		[[0.2, 0.1, 0.05], 3, 0, AcceptanceReport.RESULT_PASS],
		[[0.2], 1, 0, AcceptanceReport.RESULT_FAIL],
		[[0.2, 0.1], 2, 1, AcceptanceReport.RESULT_FAIL],
		[[0.2, 0.0], 2, 0, AcceptanceReport.RESULT_FAIL],
		[[0.5, 0.2], 2, 0, AcceptanceReport.RESULT_FAIL],
	]
	for case: Array in cases:
		var heard: Array[float] = Array(case[0], TYPE_FLOAT, "", null)
		var verdict: Array = CHECK.judge_beats(heard, case[1], case[2], 0.25)
		if verdict[0] != case[3]:
			return "%s, %d after: judged %s: %s" % [heard, case[2], verdict[0], verdict[1]]
	return ""


func test_the_runner_passes_the_step() -> String:
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	var kept: Array[AcceptanceStep] = []
	for found: AcceptanceStep in suite.steps:
		if found.id == STEP_ID:
			kept.append(found)
	suite.steps = kept
	var suites: Array[AcceptanceSuite] = [suite]
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = func(_code: int) -> void: pass
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	runner.setup(main, suites, null)
	var frames: int = 0
	while not runner.finished and frames < FRAME_LIMIT:
		runner.process_frame()
		frames += 1
	var problem: String = ""
	if not runner.finished or runner.exit_code != AcceptanceRunner.EXIT_PASS or not runner.reports[0].passed():
		problem = "exit %d: %s" % [runner.exit_code, "\n".join(runner.messages)]
	elif int(runner.reports[0].steps[0]["measurements"].get("hull_warning_beats", 0)) < 2:
		problem = "the step measured %s" % [runner.reports[0].steps[0]["measurements"]]
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	if runner.main != null:
		runner.main.free()
	runner.free()
	return problem
