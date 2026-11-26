extends RefCounted

## The m6 `hub_boards` step (#1368, CRW-1, CRW-2, DEV-6, decision record 0005):
## m4's craft-and-fit flight from a scratch profile with crew and logged runs,
## then the Crew Quarters' cards and bars and the Logbook's figures, with
## scripted stick and A presses. The pilot's own files are never touched.

const TreeStep: GDScript = preload("res://tests/test_m6_workbench_tree_step.gd")
const STEP_ID: String = "hub_boards"
const CHECK_SCRIPT: String = "res://acceptance/checks/hub_boards_check.gd"
const PROFILE_PATH: String = "res://acceptance/fittings/hub_boards_profile.json"


static func _step() -> AcceptanceStep:
	var suites: Array[AcceptanceSuite] = AcceptanceSuite.load_named("m6")
	if suites.size() != 1 or suites[0].error != "":
		return null
	for found: AcceptanceStep in suites[0].steps:
		if found.id == STEP_ID:
			return found
	return null


func test_the_step_flies_from_a_profile_with_crew_and_logged_runs() -> String:
	var found: AcceptanceStep = _step()
	if found == null:
		return "m6 base has no %s step" % STEP_ID
	if found.profile_path != PROFILE_PATH or found.checks[-1] != STEP_ID:
		return "the step flies with %s and checks %s" % [found.profile_path, found.checks]
	var profile: Profile = Profile.parse_json(FileAccess.get_file_as_string(PROFILE_PATH))
	if profile.error != "" or profile.crew.size() < 3 or profile.stats.runs_won < 1:
		return "the step's profile has %d crew and %d won runs: %s" % [profile.crew.size(), profile.stats.runs_won, profile.error]
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
	while not runner.finished and frames < TreeStep.FRAME_LIMIT:
		runner.process_frame()
		frames += 1
	var problem: String = ""
	if not runner.finished or runner.exit_code != AcceptanceRunner.EXIT_PASS:
		problem = "exit %d: %s" % [runner.exit_code, "\n".join(runner.messages)]
	else:
		var measured: Dictionary = runner.reports[0].steps[0]["measurements"]
		if int(measured.get("cards_drawn", 0)) != 3 or int(measured.get("bars_drawn", 0)) < 1 \
				or int(measured.get("figures_drawn", 0)) != ProfileStats.KEYS.size():
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
