extends RefCounted

## The m6 `level_load` step (#1445, #1480, PRF-7, DEV-6, decision record 0005):
## run through the acceptance runner in the main scene, it times every load the
## plan lists up to its first frame, reports each phase, and leaves the scene's
## own level as it was. It does not assert a time: CI's speed is not the
## headset's. Headless, no frame is drawn, so the check says "skipped".

const SUITE_PATH: String = "res://acceptance/suites/m6.json"
const STEP_ID: String = "level_load"
## No replay flies: the step is judged within a few frames.
const FRAME_LIMIT: int = 2000


func test_the_step_times_every_planned_load() -> String:
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	var kept: Array[AcceptanceStep] = []
	for found: AcceptanceStep in suite.steps:
		if found.id == STEP_ID:
			kept.append(found)
	if kept.size() != 1 or kept[0].checks != (["no_script_errors", STEP_ID] as Array[String]):
		return "m6 has %d %s steps" % [kept.size(), STEP_ID]
	suite.steps = kept
	var suites: Array[AcceptanceSuite] = [suite]
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = func(_code: int) -> void: pass
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	var level_before: Node = main.get_node_or_null(LevelView.NODE_NAME)
	runner.setup(main, suites, null)
	var frames: int = 0
	while not runner.finished and frames < FRAME_LIMIT:
		runner.process_frame()
		frames += 1
	var problem: String = ""
	var plan: LevelLoadPlan = LevelLoadPlan.load_file()
	if runner.reports.is_empty() or not runner.reports[0].passed():
		problem = "exit %d: %s" % [runner.exit_code, "\n".join(runner.messages)]
	else:
		var measured: Dictionary = runner.reports[0].steps[0]["measurements"]
		var rows: Array = measured.get("level_loads", [])
		var message: String = runner.reports[0].steps[0]["message"]
		if rows.size() != plan.run_seeds.size() + plan.levels.size() or float(measured.get("worst_total_s", 0.0)) <= 0.0:
			problem = "measured %s" % measured
		elif not (rows[0] as Dictionary).has(LevelLoadTiming.FIRST_FRAME):
			problem = "no %s in %s" % [LevelLoadTiming.FIRST_FRAME, rows[0]]
		elif DisplayServer.get_name() == "headless" \
				and (measured.get("first_frame_drawn") != false or not message.contains("not the GPU's")):
			problem = "headless, the check did not say the frame was not drawn: %s" % message
		else:
			print("  level_load on this machine: %s" % runner.reports[0].steps[0]["message"])
	if main.get_node_or_null(LevelView.NODE_NAME) != level_before:
		problem = "the step changed the scene's level drawing"
	elif main.find_child(LevelLoadTiming.WORLD_NAME, true, false) != null:
		problem = "a load stayed in the scene after the step"
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	if runner.main != null:
		runner.main.free()
	runner.free()
	return problem
