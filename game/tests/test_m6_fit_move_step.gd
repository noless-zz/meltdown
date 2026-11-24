extends RefCounted

## The m6 `fit_move` step (#1336, CRF-3, CRF-4, DEV-6, decision record 0005):
## m4's craft-and-fit flight from the same scratch profile, then the built
## weapon moved from Primary 1 to Primary 2 with scripted stick and A presses,
## and the launch flying it there. The pilot's own files are never touched.

const PART_PATH: String = "res://acceptance/suites/m6/base.json"
const M4_PATH: String = "res://acceptance/suites/m4.json"
const STEP_ID: String = "fit_move"
const CHECK_SCRIPT: String = "res://acceptance/checks/fit_move_check.gd"
## The replay is two seconds of idle input; the runner flies one tick per frame.
const FRAME_LIMIT: int = 5000


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


func test_the_step_flies_m4s_craft_and_fit_flight_from_its_profile() -> String:
	var found: AcceptanceStep = _step()
	var m4: AcceptanceStep = null
	for each: AcceptanceStep in AcceptanceSuite.load_file(M4_PATH).steps:
		if each.id == "craft_and_fit":
			m4 = each
	if found == null or m4 == null:
		return "steps found: m6 %s, m4 %s" % [found, m4]
	if found.run_seed != m4.run_seed or found.replay_path != m4.replay_path or found.profile_path != m4.profile_path:
		return "the step flies run %d from %s with %s" % [found.run_seed, found.replay_path, found.profile_path]
	if found.checks[-1] != STEP_ID:
		return "the step's checks are %s" % [found.checks]
	return ""


func test_the_runner_passes_the_step_and_leaves_no_scratch_files() -> String:
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
	while not runner.finished and frames < FRAME_LIMIT:
		runner.process_frame()
		frames += 1
	var problem: String = ""
	if not runner.finished or runner.exit_code != AcceptanceRunner.EXIT_PASS:
		problem = "exit %d: %s" % [runner.exit_code, "\n".join(runner.messages)]
	else:
		var measured: Dictionary = runner.reports[0].steps[0]["measurements"]
		if measured.get("fitted", "") != ",needle_gun" or not str(measured.get("primary", "")).ends_with(",needle_gun"):
			problem = "the step measured %s" % measured
	var check: GDScript = load(CHECK_SCRIPT)
	for path: String in [check.PROFILE_FILE, check.FITTING_FILE]:
		if FileAccess.file_exists(path):
			problem = "the step left %s behind" % path
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	if runner.main != null:
		runner.main.free()
	runner.free()
	return problem
