extends RefCounted

## The m6 `hub_stations` step with its `hub_sounds` check (#1401, AUD-1,
## CRW-2, DEV-6, decision record 0005): the step crafts, mounts and launches
## through the scene's own controls, and the stations' sounds must have been
## requested for each. The pilot's own files are never touched.

const TreeStep: GDScript = preload("res://tests/test_m6_workbench_tree_step.gd")
const STEP_ID: String = "hub_stations"
const STATIONS_CHECK: String = "res://acceptance/checks/hub_stations_check.gd"


static func _step() -> AcceptanceStep:
	var suites: Array[AcceptanceSuite] = AcceptanceSuite.load_named("m6")
	if suites.size() != 1 or suites[0].error != "":
		return null
	for found: AcceptanceStep in suites[0].steps:
		if found.id == STEP_ID:
			return found
	return null


func test_the_sounds_are_checked_after_the_stations_walk() -> String:
	var found: AcceptanceStep = _step()
	if found == null:
		return "m6 base has no %s step" % STEP_ID
	var walk: int = found.checks.find("hub_stations")
	var sounds: int = found.checks.find("hub_sounds")
	if walk < 0 or sounds != walk + 1:
		return "the step checks %s; hub_sounds must follow hub_stations" % [found.checks]
	return ""


func test_the_runner_passes_the_step_with_its_sounds() -> String:
	var found: AcceptanceStep = _step()
	if found == null:
		return "m6 base has no %s step" % STEP_ID
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
	while not runner.finished and frames < TreeStep.FRAME_LIMIT:
		runner.process_frame()
		frames += 1
	var problem: String = ""
	if not runner.finished or runner.exit_code != AcceptanceRunner.EXIT_PASS:
		problem = "exit %d: %s" % [runner.exit_code, "\n".join(runner.messages)]
	else:
		var measured: Dictionary = runner.reports[0].steps[0]["measurements"]
		var heard: String = str(measured.get("hub_sounds", ""))
		for sound_name: String in ["select", "crafted", "mounted", "launch"]:
			if problem == "" and heard.find(sound_name) < 0:
				problem = "the step measured sounds %s, without %s" % [heard, sound_name]
	var check: GDScript = load(STATIONS_CHECK)
	for path: String in [check.PROFILE_FILE, check.FITTING_FILE]:
		if FileAccess.file_exists(path):
			problem = "the step left %s behind" % path
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	if runner.main != null:
		runner.main.free()
	runner.free()
	return problem
