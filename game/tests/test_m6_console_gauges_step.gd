extends RefCounted

## The m6 `console_gauges` step (#1461, GFX-2, CMF-8, PLT-5, DEV-6, decision
## record 0005): it flies the low-hull replay through the scene's own frames,
## then on each of the four presets the console's hull, shield and energy read
## the core's values in the same place, and the hull shows its low state. Run
## through the acceptance runner in the main scene, as the suite runs it.

const PART_PATH: String = "res://acceptance/suites/m6/look.json"
const STEP_ID: String = "console_gauges"
const CHECK_SCRIPT: String = "res://acceptance/checks/console_gauges_check.gd"
const REPLAY: String = "res://acceptance/replays/low_hull_test_tunnel.replay"
const FRAME_LIMIT: int = 2400


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
	var want: Array[String] = ["final_hash", "outcome", STEP_ID, "no_script_errors"]
	if found.checks != want:
		return "the step checks %s" % [found.checks]
	if found.replay_path != REPLAY:
		return "the step flies %s, expected %s" % [found.replay_path, REPLAY]
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
		if int(measured.get("hull_low_frames_in_flight", 0)) <= 0:
			problem = "the step measured %s" % measured
		for number: int in [1, 2, 3, 4]:
			var hull: Array = measured.get("preset%d_hull" % number, [])
			if problem == "" and (hull.size() < 2 or hull[1] != "low"):
				problem = "preset %d's hull reads %s at the end of the replay" % [number, hull]
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	main.free()
	runner.free()
	return problem


func test_the_check_fails_a_console_never_fed_in_flight() -> String:
	var check: GDScript = load(CHECK_SCRIPT)
	var frame: CockpitFrame = CockpitFrame.new(CockpitSpec.for_preset(ComfortPresetFiles.load_number(1)))
	var session: LocalSession = LocalSession.new()
	var verdict: Array = check.judge_presets(frame, session, {},
		func(number: int) -> void: frame.set_spec(CockpitSpec.for_preset(ComfortPresetFiles.load_number(number))),
		1, func(_n: int) -> String: return "")
	frame.free()
	if verdict[0] != AcceptanceReport.RESULT_FAIL or not str(verdict[1]).contains("never fed"):
		return "an unfed console gave %s" % [verdict]
	return ""


func test_the_check_fails_an_instrument_out_of_place_on_one_preset() -> String:
	var check: GDScript = load(CHECK_SCRIPT)
	var frame: CockpitFrame = CockpitFrame.new(CockpitSpec.for_preset(ComfortPresetFiles.load_number(1)))
	var session: LocalSession = LocalSession.new()
	var console: ConsoleGauges = ConsoleGauges.of_frame(frame)
	console.show_gauges(ShipGauges.of(0.1, 0.0, 0.5), 0.016)  # A flown frame with the hull low.
	var set_preset: Callable = func(number: int) -> void:
		var spec: CockpitSpec = CockpitSpec.for_preset(ComfortPresetFiles.load_number(number))
		if number == 3:
			spec.instruments[1].yaw_deg += 5.0
		frame.set_spec(spec)
	var verdict: Array = check.judge_presets(frame, session, {}, set_preset, 1, func(_n: int) -> String: return "")
	frame.free()
	if verdict[0] != AcceptanceReport.RESULT_FAIL or not str(verdict[1]).begins_with("preset 3: shield sits at"):
		return "a moved shield gave %s" % [verdict]
	return ""
