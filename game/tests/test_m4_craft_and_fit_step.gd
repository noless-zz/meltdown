extends RefCounted

## The m4 suite's `craft_and_fit` step (#1093, CRW-2, CRF-3, CRF-4, DEV-6,
## decision record 0005): run 12345's first level flown from a scratch profile
## with components banked, then the hub opened on the run, the first weapon
## the Workbench offers built and mounted with scripted stick and A presses,
## and the launch flying it. The pilot's own profile and fitting are never touched.

const SUITE_PATH: String = "res://acceptance/suites/m4.json"
const STEP_ID: String = "craft_and_fit"
## The replay takes about 7,200 ticks; the runner flies one per frame.
const FRAME_LIMIT: int = 20000

var _quit_codes: Array[int] = []


static func step(step_id: String = STEP_ID) -> AcceptanceStep:
	for found: AcceptanceStep in AcceptanceSuite.load_file(SUITE_PATH).steps:
		if found.id == step_id:
			return found
	return null


func test_the_step_flies_run_12345_from_a_scratch_profile() -> String:
	var found: AcceptanceStep = step()
	if found == null:
		return "m4 lacks %s" % STEP_ID
	if found.run_seed != 12345 or found.profile_path == "" or found.checks[-1] != AcceptanceStep.CHECK_CRAFT_AND_FIT:
		return "the step flies run %d from '%s' with checks %s" % [found.run_seed, found.profile_path, found.checks]
	var profile: Profile = ProfileStore.new(found.profile_path).load_profile()
	if profile.banked.is_empty() or not profile.crafted.is_empty():
		return "the scratch profile banks %s and has crafted %s" % [profile.banked, profile.crafted]
	return ""


func test_the_runner_passes_the_step_and_leaves_no_scratch_files() -> String:
	var runner: AcceptanceRunner = _run()
	var problem: String = ""
	if runner.exit_code != AcceptanceRunner.EXIT_PASS or not runner.reports[0].passed():
		problem = "exit %d: %s" % [runner.exit_code, "\n".join(runner.messages)]
	else:
		var measured: Dictionary = runner.reports[0].steps[0]["measurements"]
		if measured.get("crafted", "") != "needle_gun" or not str(measured.get("primary", "")).begins_with("needle_gun"):
			problem = "the step measured %s" % measured
		elif FileAccess.file_exists(AcceptanceCraftAndFitCheck.PROFILE_FILE) \
				or FileAccess.file_exists(AcceptanceCraftAndFitCheck.FITTING_FILE):
			problem = "the step left its scratch files behind"
	_done(runner)
	return problem


func test_the_check_needs_a_profile_and_a_run_and_comes_last() -> String:
	var cases: Dictionary[String, String] = {
		"\"run\": 5, \"replay\": \"r\", \"checks\": [\"craft_and_fit\"]": "steps[0].profile: needed by the craft_and_fit check",
		"\"replay\": \"r\", \"checks\": [\"craft_and_fit\"]": "steps[0].run: needed by the craft_and_fit check",
		"\"run\": 5, \"replay\": \"r\", \"profile\": \"p\", \"checks\": [\"craft_and_fit\", \"no_script_errors\"]":
			"craft_and_fit must be the last check",
		"\"run\": 5, \"replay\": \"r\", \"profile\": \"p\", \"checks\": [\"craft_and_fit\"], \"expected_next_level_hash\": 3":
			"steps[0].expected_next_level_hash: only used by",
	}
	for fields: String in cases:
		var suite: AcceptanceSuite = AcceptanceSuite.parse_json(
			"{\"name\": \"t\", \"steps\": [{\"id\": \"a\", %s}]}" % fields)
		if not suite.error.contains(cases[fields]):
			return "%s gave '%s', expected it to say %s" % [fields, suite.error, cases[fields]]
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
