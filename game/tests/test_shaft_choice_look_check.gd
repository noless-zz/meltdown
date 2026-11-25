extends RefCounted

## The m6 `shaft_choice_look` step (#1320, RUN-2, GFX-2, DEV-6, decision record
## 0005): run 12345's first level escapes on the `run_advances` replay, A on
## the escape screen opens the shaft choice, and every offered shaft stands as
## a thing with its gauges. Headless, the screenshot is noted as skipped.

## The m6 suite, which takes in its lanes' parts, `m6/effects` among them.
const SUITE_PATH: String = "res://acceptance/suites/m6.json"
const PART_PATH: String = "res://acceptance/suites/m6/effects.json"
const STEP_ID: String = "shaft_choice_look"
const CHECK: GDScript = preload("res://acceptance/checks/shaft_choice_look_check.gd")
## The escape takes about 7,200 ticks and the escape screen a few seconds more.
const FRAME_LIMIT: int = 20000

var _quit_codes: Array[int] = []


func test_the_check_is_registered_and_the_step_is_in_lane_bs_part() -> String:
	if not AcceptanceCheckFiles.judges().has(CHECK.CHECK):
		return "no check file judges %s: %s" % [CHECK.CHECK, AcceptanceCheckFiles.problem()]
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	if suite.error != "":
		return suite.error
	if not FileAccess.get_file_as_string(PART_PATH).contains("\"id\": \"%s\"" % STEP_ID):
		return "%s, lane-b's part, has no step %s" % [PART_PATH, STEP_ID]
	for found: AcceptanceStep in suite.steps:
		if found.id == STEP_ID:
			return "" if found.run_seed == 12345 and found.checks.has(CHECK.CHECK) else "the step checks %s" % [found.checks]
	return "%s has no step %s" % [SUITE_PATH, STEP_ID]


func test_the_runner_passes_the_step_and_closes_the_choice() -> String:
	var runner: AcceptanceRunner = _run()
	var problem: String = ""
	if runner.exit_code != AcceptanceRunner.EXIT_PASS or not runner.reports[0].passed():
		problem = "exit %d: %s" % [runner.exit_code, "\n".join(runner.messages)]
	else:
		var measured: Dictionary = runner.reports[0].steps[0]["measurements"]
		var destroyed: DestroyedWiring = runner.main.get("destroyed")
		if measured.get("looks") != "drop,vent,lift" or not str(measured.get("screenshot")).begins_with("skipped"):
			problem = "measured %s" % measured
		elif destroyed.escape.choice.is_open():
			problem = "the check left the choice open"
	_done(runner)
	return problem


func test_the_open_choice_fails_without_things() -> String:
	var run: RunWiring = RunWiring.new(12345)
	var choice: ShaftChoiceWiring = ShaftChoiceWiring.new()
	choice.shapes = ShaftPanelShapes.parse(FileAccess.get_file_as_string(ShaftPanelShapes.DEFAULT_FILE)
		.replace("\"hot\": \"vent\"", "\"other\": \"vent\""))
	var rig: Node3D = Node3D.new()
	choice.attach(rig)
	choice.open(run, {})
	choice.update(run, false, Transform3D.IDENTITY, true)
	var verdict: Array = CHECK.judge_open(choice, {})
	rig.free()
	if verdict[0] != AcceptanceReport.RESULT_FAIL or not str(verdict[1]).contains("shaft hot shows 0 parts"):
		return "a shaft shown as text passed: %s" % [verdict]
	return ""


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
