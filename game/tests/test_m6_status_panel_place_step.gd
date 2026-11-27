extends RefCounted

## The m6 `status_panel_place` step (#1452, CMF-8, PLT-5, DEV-6, decision
## record 0005): on each of the four presets the status panel sits where the
## corner setting puts it against the cockpit, bottom left by default, and no
## drawn row comes into the middle of the view. Run through the acceptance
## runner in the main scene, as the suite runs it.

const PART_PATH: String = "res://acceptance/suites/m6/look.json"
const STEP_ID: String = "status_panel_place"
const CHECK_SCRIPT: String = "res://acceptance/checks/status_panel_place_check.gd"
const FRAME_LIMIT: int = 600


static func _step() -> AcceptanceStep:
	if not FileAccess.get_file_as_string(PART_PATH).contains("\"%s\"" % STEP_ID):
		return null
	var suites: Array[AcceptanceSuite] = AcceptanceSuite.load_named("m6")
	if suites.size() != 1 or suites[0].error != "":
		return null
	for found: AcceptanceStep in suites[0].steps:
		if found.id == STEP_ID:
			return found
	return null


func test_the_step_is_in_the_look_part() -> String:
	var found: AcceptanceStep = _step()
	if found == null:
		return "m6 look has no %s step" % STEP_ID
	var want: Array[String] = ["no_script_errors", STEP_ID]
	if found.checks != want:
		return "the step checks %s" % [found.checks]
	return ""


func test_the_runner_passes_the_step_on_every_preset() -> String:
	var found: AcceptanceStep = _step()
	if found == null:
		return "m6 look has no %s step" % STEP_ID
	var suite: AcceptanceSuite = AcceptanceSuite.new()
	suite.name = "m6"
	suite.steps.append(found)
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
	if not runner.finished or runner.exit_code != AcceptanceRunner.EXIT_PASS:
		problem = "exit %d: %s" % [runner.exit_code, "\n".join(runner.messages)]
	else:
		var measured: Dictionary = runner.reports[0].steps[0]["measurements"]
		for number: int in [1, 2, 3, 4]:
			if float(measured.get("preset%d_nearest_deg" % number, 0.0)) < StatusPanelBounds.CENTRAL_CONE_DEG:
				problem = "the step measured %s" % measured
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	main.free()
	runner.free()
	return problem


func test_the_check_fails_a_panel_in_the_middle_of_the_view() -> String:
	var check: GDScript = load(CHECK_SCRIPT)
	var frame: CockpitFrame = CockpitFrame.new(CockpitSpec.for_preset(ComfortPresetFiles.load_number(1)))
	var panel: StatusPanel = StatusPanel.new()
	var saved: String = PanelCorner.current
	PanelCorner.current = PanelCorner.CENTRE
	var verdict: Array = check.judge_presets(panel, frame, {}, func(_n: int) -> String: return "")
	PanelCorner.current = saved
	panel.free()
	frame.free()
	if verdict[0] != AcceptanceReport.RESULT_FAIL or not str(verdict[1]).contains("straight ahead"):
		return "the centre place gave %s" % [verdict]
	return ""
