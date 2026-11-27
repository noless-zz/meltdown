extends RefCounted

## The m6 `menu_at_base` and `menu_at_shaft` steps (#1450, CRW-2, DEV-8,
## decision record 0005): run through the acceptance runner on the real scene,
## the menu opens at the home base with the Update entry for a faked waiting
## build and without the mine's entries, A in it does not launch, and the sign
## names the build; at the shaft choice the menu opens and closes and leaves the
## shaft panel alone. The pilot's own files are never touched.

const SUITE_PATH: String = "res://acceptance/suites/m6.json"
const PART_PATH: String = "res://acceptance/suites/m6/base.json"
const CHECK: GDScript = preload("res://acceptance/checks/menu_at_base_check.gd")
## The escape takes about 7,200 ticks and the escape screen a few seconds more.
const FRAME_LIMIT: int = 20000


static func _runner_for(step_id: String) -> AcceptanceRunner:
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	var kept: Array[AcceptanceStep] = []
	for found: AcceptanceStep in suite.steps:
		if found.id == step_id:
			kept.append(found)
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
	return runner


static func _done(runner: AcceptanceRunner) -> void:
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	if runner.main != null:
		runner.main.free()
	runner.free()


func test_the_checks_are_registered_and_the_steps_are_in_the_base_part() -> String:
	for check: String in [CHECK.CHECK_BASE, CHECK.CHECK_SHAFT]:
		if not AcceptanceCheckFiles.judges().has(check):
			return "no check file judges %s: %s" % [check, AcceptanceCheckFiles.problem()]
		if not FileAccess.get_file_as_string(PART_PATH).contains("\"id\": \"%s\"" % check):
			return "%s has no step %s" % [PART_PATH, check]
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	if suite.error != "":
		return suite.error
	for found: AcceptanceStep in suite.steps:
		if (found.id == CHECK.CHECK_BASE or found.id == CHECK.CHECK_SHAFT) and found.checks[-1] != found.id:
			return "step %s checks %s; its own check must be last" % [found.id, found.checks]
	return ""


func test_the_runner_passes_the_base_step() -> String:
	var runner: AcceptanceRunner = _runner_for(CHECK.CHECK_BASE)
	var problem: String = ""
	if not runner.finished or runner.exit_code != AcceptanceRunner.EXIT_PASS or not runner.reports[0].passed():
		problem = "exit %d: %s" % [runner.exit_code, "\n".join(runner.messages)]
	else:
		var measured: Dictionary = runner.reports[0].steps[0]["measurements"]
		if not str(measured.get("update_sign", "")).contains(CHECK.FAKE_VERSION):
			problem = "the step measured no sign: %s" % [measured]
	for path: String in [CHECK.PROFILE_FILE, CHECK.FITTING_FILE]:
		if FileAccess.file_exists(path):
			problem = "the step left %s behind" % path
	_done(runner)
	return problem


func test_the_runner_passes_the_shaft_step() -> String:
	var runner: AcceptanceRunner = _runner_for(CHECK.CHECK_SHAFT)
	var problem: String = ""
	if not runner.finished or runner.exit_code != AcceptanceRunner.EXIT_PASS or not runner.reports[0].passed():
		problem = "exit %d: %s" % [runner.exit_code, "\n".join(runner.messages)]
	_done(runner)
	return problem
