extends RefCounted

## The m6 `craft_moment` step (#1402, CRF-3, CRW-2, DEV-6, decision record
## 0005): m4's craft-and-fit flight, then building at the Workbench through the
## scene's own controls must play the crafting moment to its end, with the
## built node and the node it unlocked drawn at rest. The pilot's own files
## are never touched.

const TreeStep: GDScript = preload("res://tests/test_m6_workbench_tree_step.gd")
const STEP_ID: String = "craft_moment"
const CHECK_SCRIPT: String = "res://acceptance/checks/craft_moment_check.gd"


static func _step() -> AcceptanceStep:
	var suites: Array[AcceptanceSuite] = AcceptanceSuite.load_named("m6")
	if suites.size() != 1 or suites[0].error != "":
		return null
	for found: AcceptanceStep in suites[0].steps:
		if found.id == STEP_ID:
			return found
	return null


func test_the_step_flies_the_workbench_flight_with_a_bank_for_two_builds() -> String:
	var found: AcceptanceStep = _step()
	var tree: AcceptanceStep = TreeStep._step()
	if found == null or tree == null:
		return "steps found: %s %s, workbench_tree %s" % [STEP_ID, found, tree]
	if found.run_seed != tree.run_seed or found.replay_path != tree.replay_path or found.checks[-1] != STEP_ID:
		return "the step flies run %d from %s and checks %s" % [found.run_seed, found.replay_path, found.checks]
	var check: GDScript = load(CHECK_SCRIPT)
	var bank: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(found.profile_path))["banked"]
	var needed: Dictionary = {}
	for upgrade: String in [check.BUILD, "arc_lance"]:
		var cost: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/upgrades/%s.json" % upgrade))["cost"]
		for component: String in cost:
			needed[component] = int(needed.get(component, 0)) + int(cost[component])
	for component: String in needed:
		if int(bank.get(component, 0)) < int(needed[component]):
			return "the profile banks %s, not enough for %s and what it unlocks (%s)" % [bank, check.BUILD, needed]
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
		if str(measured.get("unlocked", "")).find("arc_lance") < 0 or int(measured.get("components_flying", 0)) < 1 \
				or float(measured.get("fill_at_screenshot", 0.0)) <= 0.0 or float(measured.get("fill_at_screenshot", 1.0)) >= 1.0:
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
