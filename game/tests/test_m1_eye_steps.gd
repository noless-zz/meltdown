extends RefCounted

## The m1 `eyes_same_frame`, `eyes_same_frame_base` and `view_not_magnified`
## steps (#1513, CMF-8, DEV-6, decision record 0005). Run through the
## acceptance runner in the main scene without a stereo runtime and with
## nothing drawn, each reports skipped, not passed, and the magnify target
## leaves the scene with the step.

const SUITE_PATH: String = "res://acceptance/suites/m1.json"
const STEP_IDS: Array[String] = ["eyes_same_frame", "eyes_same_frame_base", "view_not_magnified"]
const MAGNIFY_SCRIPT: GDScript = preload("res://acceptance/checks/view_not_magnified_check.gd")
## The base step flies the idle replay first.
const FRAME_LIMIT: int = 20000


func test_m1_lists_the_steps() -> String:
	var found: Dictionary = {}
	for step: AcceptanceStep in AcceptanceSuite.load_file(SUITE_PATH).steps:
		found[step.id] = step
	for id: String in STEP_IDS:
		if not found.has(id):
			return "m1 has no step %s" % id
		if (found[id] as AcceptanceStep).required:
			return "%s is required: it must be skipped where there is no headset" % id
	return ""


func test_the_shipped_target_values_are_read() -> String:
	var values: Dictionary = MAGNIFY_SCRIPT.read_values("res://acceptance/checks/eye_frames.json")
	return "" if not values.has("error") and float(values["distance_m"]) > 0.0 else "gave %s" % values


func test_without_a_headset_each_step_is_skipped() -> String:
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	var kept: Array[AcceptanceStep] = []
	for id: String in STEP_IDS:
		for step: AcceptanceStep in suite.steps:
			if step.id == id:
				kept.append(step)
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
	if runner.reports.is_empty() or runner.reports[0].steps.size() != STEP_IDS.size():
		problem = "exit %d: %s" % [runner.exit_code, "\n".join(runner.messages)]
	else:
		for entry: Dictionary in runner.reports[0].steps:
			if entry["result"] != AcceptanceReport.RESULT_SKIPPED:
				problem = "%s gave %s: %s" % [entry["id"], entry["result"], entry["message"]]
				break
	if problem == "" and runner.main.find_child(MAGNIFY_SCRIPT.TARGET_NAME, true, false) != null:
		problem = "the magnify target stayed in the scene"
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	if runner.main != null:
		runner.main.free()
	runner.free()
	return problem
