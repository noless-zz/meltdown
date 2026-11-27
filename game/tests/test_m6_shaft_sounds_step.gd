extends RefCounted

## The m6 `shaft_sounds` step (#1455, AUD-1, RUN-1, DEV-6, decision record
## 0005): run 12345's first level escapes on the `run_advances` replay, A on
## the escape screen opens the shaft choice, the stick moves across two shafts
## and A chooses one; the requested-sound log must hold point, point, select.

const SUITE_PATH: String = "res://acceptance/suites/m6.json"
const PART_PATH: String = "res://acceptance/suites/m6/sound.json"
const STEP_ID: String = "shaft_sounds"
const CHECK: GDScript = preload("res://acceptance/checks/shaft_sounds_check.gd")
## The escape takes about 7,200 ticks and the escape screen a few seconds more.
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
			if found.run_seed != 12345 or found.checks.is_empty() or found.checks[-1] != CHECK.CHECK:
				return "the step flies run %d and checks %s; shaft_sounds must be last" % [found.run_seed,
					found.checks]
			return ""
	return "%s has no step %s" % [SUITE_PATH, STEP_ID]


func test_the_judge_wants_point_point_select_in_order() -> String:
	var cases: Array[Array] = [
		[["point", "point", "select", "launch"], AcceptanceReport.RESULT_PASS],
		[["point", "refused", "point", "select"], AcceptanceReport.RESULT_PASS],
		[["point", "select", "launch"], AcceptanceReport.RESULT_FAIL],
		[["select", "point", "point"], AcceptanceReport.RESULT_FAIL],
		[[], AcceptanceReport.RESULT_FAIL],
	]
	for case: Array in cases:
		var heard: Array[String] = Array(case[0], TYPE_STRING, "", null)
		var verdict: Array = CHECK.judge_heard(heard)
		if verdict[0] != case[1]:
			return "%s judged %s: %s" % [heard, verdict[0], verdict[1]]
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
	else:
		var heard: String = str(runner.reports[0].steps[0]["measurements"].get("shaft_sounds", ""))
		if not heard.begins_with("point,point,select"):
			problem = "the step measured sounds '%s'" % heard
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	if runner.main != null:
		runner.main.free()
	runner.free()
	return problem
