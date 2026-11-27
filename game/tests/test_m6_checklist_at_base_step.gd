extends RefCounted

## The m6 `checklist_at_base` step (#1408, DEV-6, DEV-7, decision record
## 0005): run through the acceptance runner on the real scene, a tap at the
## base opens the pinned checklist, the stick stays off the stations, and a
## station action opens its station. The pilot's own files are never touched.

const TreeStep: GDScript = preload("res://tests/test_m6_workbench_tree_step.gd")
const STEP_ID: String = "checklist_at_base"
const CHECK: String = "res://acceptance/checks/checklist_at_base_check.gd"


static func _step() -> AcceptanceStep:
	var suites: Array[AcceptanceSuite] = AcceptanceSuite.load_named("m6")
	if suites.size() != 1 or suites[0].error != "":
		return null
	for found: AcceptanceStep in suites[0].steps:
		if found.id == STEP_ID:
			return found
	return null


func test_the_base_suite_has_the_step() -> String:
	var found: AcceptanceStep = _step()
	if found == null:
		return "m6 base has no %s step" % STEP_ID
	return "" if found.checks.has(STEP_ID) else "the step checks %s" % [found.checks]


func test_the_runner_passes_the_step() -> String:
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
		if str(measured.get("station_in_use", "")) == "":
			problem = "the step measured no station in use: %s" % [measured]
	var check: GDScript = load(CHECK)
	for path: String in [check.PROFILE_FILE, check.FITTING_FILE]:
		if FileAccess.file_exists(path):
			problem = "the step left %s behind" % path
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	if runner.main != null:
		runner.main.free()
	runner.free()
	return problem
