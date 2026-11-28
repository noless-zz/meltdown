extends RefCounted

## The m6 `status_panel_place` step (#1452, CMF-8, PLT-5, DEV-6, decision
## record 0005): on each of the four presets the status panel sits where the
## corner setting puts it against the cockpit, bottom left by default, and no
## drawn row comes into the middle of the view. Since #1507 it flies 300
## ticks of a turning replay first and checks the panel lies inside both
## eyes' views. Run through the acceptance runner in the main scene, as the
## suite runs it.

const PART_PATH: String = "res://acceptance/suites/m6/look.json"
const STEP_ID: String = "status_panel_place"
const CHECK_SCRIPT: String = "res://acceptance/checks/status_panel_place_check.gd"
const FRAME_LIMIT: int = 1200
const REPLAY: String = "res://acceptance/replays/status_panel_flight.replay"


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
	var want: Array[String] = ["final_hash", "no_script_errors", STEP_ID]
	if found.checks != want:
		return "the step checks %s" % [found.checks]
	if found.replay_path != REPLAY:
		return "the step flies %s, expected %s" % [found.replay_path, REPLAY]
	var replay: Replay = Replay.load_file(REPLAY)
	if replay.error != "" or replay.frames.size() != 300:
		return "the replay has %d ticks (%s), expected 300" % [replay.frames.size(), replay.error]
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
			if float(measured.get("preset%d_centre_deg" % number, 0.0)) < StatusPanelBounds.CENTRAL_CONE_DEG \
					or float(measured.get("preset%d_nearest_deg" % number, 0.0)) < StatusPanelBounds.ROW_CONE_DEG \
					or str(measured.get("preset%d_both_eyes" % number, "")) != "yes":
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


func test_the_check_fails_a_panel_one_eye_sees_only_in_part() -> String:
	# The bottom-left place before #1507: the right eye lost the panel's left side.
	var check: GDScript = load(CHECK_SCRIPT)
	var frame: CockpitFrame = CockpitFrame.new(CockpitSpec.for_preset(ComfortPresetFiles.load_number(1)))
	var panel: StatusPanel = StatusPanel.new()
	var saved: Dictionary = StatusPanelLook.shared()["corners"].duplicate()
	var corners: Dictionary = StatusPanelLook.shared()["corners"]
	corners["bottom_left"] = Vector3(-0.298, -0.155, -0.497)
	var corner: String = PanelCorner.current
	PanelCorner.current = "bottom_left"
	var measured: Dictionary = {}
	var verdict: Array = check.judge_presets(panel, frame, measured, func(_n: int) -> String: return "")
	PanelCorner.current = corner
	StatusPanelLook.shared()["corners"] = saved
	panel.free()
	frame.free()
	if verdict[0] != AcceptanceReport.RESULT_FAIL or not str(verdict[1]).contains("right eye"):
		return "the old bottom-left place gave %s" % [verdict]
	if not str(measured.get("preset1_both_eyes", "")).contains("left edge"):
		return "the step measured %s" % measured
	return ""
