extends RefCounted

## The m6 `menu_sounds` step (#1457, AUD-1, DEV-6, decision record 0005): it
## is in lane-c's `m6/menu` part, and the runner passes it with the menu's
## requested-sound log in its measurements.

const TreeStep: GDScript = preload("res://tests/test_m6_workbench_tree_step.gd")
const STEP_ID: String = "menu_sounds"


static func _step() -> AcceptanceStep:
	var suites: Array[AcceptanceSuite] = AcceptanceSuite.load_named("m6")
	if suites.size() != 1 or suites[0].error != "":
		return null
	for found: AcceptanceStep in suites[0].steps:
		if found.id == STEP_ID:
			return found
	return null


func test_the_step_is_in_the_menu_part_with_its_check() -> String:
	var text: String = FileAccess.get_file_as_string("res://acceptance/suites/m6/menu.json")
	if not text.contains("\"%s\"" % STEP_ID):
		return "suites/m6/menu.json has no %s step" % STEP_ID
	var found: AcceptanceStep = _step()
	if found == null or not found.checks.has("menu_sounds") or not found.checks.has("no_script_errors"):
		return "the m6 %s step checks %s" % [STEP_ID, found.checks if found != null else []]
	return ""


func test_the_runner_passes_the_step_with_the_expected_sounds() -> String:
	var found: AcceptanceStep = _step()
	if found == null:
		return "m6 has no %s step" % STEP_ID
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
		var heard: String = str(runner.reports[0].steps[0]["measurements"].get("menu_sounds", ""))
		if heard != "open,point,point,confirm,change,back":
			problem = "the step measured sounds %s" % heard
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	if runner.main != null:
		runner.main.free()
	runner.free()
	return problem
