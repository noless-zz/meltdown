extends RefCounted

## The m6 `step_label` step (#1438, DEV-6, CMF-8): the weapons replay flies
## with screenshots at tick 12 and the end, and the cockpit's step label must
## name the suite, the step's number and count and the step, fixed in view.

const SUITE_PATH: String = "res://acceptance/suites/m6.json"
const PART_PATH: String = "res://acceptance/suites/m6/effects.json"
const STEP_ID: String = "step_label"
const CHECK: GDScript = preload("res://acceptance/checks/step_label_check.gd")
const FRAME_LIMIT: int = 2000


func test_the_check_is_registered_and_the_step_is_in_the_effects_part() -> String:
	if not AcceptanceCheckFiles.judges().has(CHECK.CHECK):
		return "no check file judges %s: %s" % [CHECK.CHECK, AcceptanceCheckFiles.problem()]
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	if suite.error != "":
		return suite.error
	if not FileAccess.get_file_as_string(PART_PATH).contains("\"id\": \"%s\"" % STEP_ID):
		return "%s has no step %s" % [PART_PATH, STEP_ID]
	for found: AcceptanceStep in suite.steps:
		if found.id == STEP_ID:
			if not found.checks.has(CHECK.CHECK) or not found.screenshot_at_end:
				return "the step checks %s and screenshots at the end: %s" % [found.checks, found.screenshot_at_end]
			return ""
	return "%s has no step %s" % [SUITE_PATH, STEP_ID]


func test_the_judge_wants_the_right_text_in_view() -> String:
	var label: AcceptanceStepLabel = AcceptanceStepLabel.new()
	var rig: Node3D = Node3D.new()
	rig.add_child(label)
	var cockpit: Transform3D = Transform3D(Basis(Vector3.UP, 0.3), Vector3(0.0, 1.1, 0.0))
	label.place(cockpit)
	label.show_text("m6  4/9  step_label")
	var problem: String = ""
	var measurements: Dictionary = {}
	var verdict: Array = CHECK.judge_label(label, "m6  4/9  step_label", cockpit, measurements)
	if verdict[0] != AcceptanceReport.RESULT_PASS:
		problem = "in view with the right text: %s" % verdict[1]
	if problem == "":
		verdict = CHECK.judge_label(label, "m6  5/9  other", cockpit, measurements)
		if verdict[0] != AcceptanceReport.RESULT_FAIL:
			problem = "the wrong text passed"
	if problem == "":
		var behind: Transform3D = cockpit * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
		verdict = CHECK.judge_label(label, "m6  4/9  step_label", behind, measurements)
		if verdict[0] != AcceptanceReport.RESULT_FAIL:
			problem = "a label behind the eye passed"
	if problem == "":
		label.show_text("")
		verdict = CHECK.judge_label(label, "m6  4/9  step_label", cockpit, measurements)
		if verdict[0] != AcceptanceReport.RESULT_FAIL:
			problem = "a hidden label passed"
	rig.free()
	return problem


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
	AcceptanceStepLabelWiring.attach(main, runner)  # As `main.gd` does when the switch started the runner.
	var frames: int = 0
	while not runner.finished and frames < FRAME_LIMIT:
		runner.process_frame()
		frames += 1
	var problem: String = ""
	if not runner.finished or runner.exit_code != AcceptanceRunner.EXIT_PASS or not runner.reports[0].passed():
		problem = "exit %d: %s" % [runner.exit_code, "\n".join(runner.messages)]
	else:
		var shown: String = str(runner.reports[0].steps[0]["measurements"].get("step_label", ""))
		if shown != "m6  1/1  step_label":
			problem = "the label said '%s'" % shown
		var wiring: AcceptanceStepLabelWiring = AcceptanceStepLabelWiring.find(main)
		wiring.refresh()
		if problem == "" and wiring.label.visible:
			problem = "the label still shows after the run ended"
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	if runner.main != null:
		runner.main.free()
	runner.free()
	return problem
