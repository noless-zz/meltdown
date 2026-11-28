extends RefCounted

## The `level_load` check's judging and its plan (#1445, PRF-7, ARC-1, ARC-4).
## The judging tests use fake timings, so they pass on any machine's speed.

const CHECK_SCRIPT: String = "res://acceptance/checks/level_load_check.gd"
const GOOD_PLAN: String = '{"budget_seconds": 8.0, "run_seeds": [4, 8, 12], "shaft": "deep", "levels": ["stress"]}'


static func _timing(label: String, generate: float, build_view: float, first_tick: float) -> Dictionary:
	return {"label": label, "generate_s": generate, "build_view_s": build_view, "first_tick_s": first_tick,
		"total_s": generate + build_view + first_tick}


static func _judge(timings: Array[Dictionary], budget: float, measurements: Dictionary) -> Array:
	return (load(CHECK_SCRIPT) as GDScript).call("judge_timings", timings, budget, measurements)


static func _shafts() -> ShaftOffer:
	return ShaftOffer.build(SeedLevel.read_text(RunWiring.SHAFTS_FILE))


func test_loads_within_the_budget_pass_and_report_every_phase() -> String:
	var measurements: Dictionary = {}
	var timings: Array[Dictionary] = [_timing("run 4 level 5 seed 11", 1.0, 2.0, 0.1),
		_timing("level stress", 0.5, 3.0, 0.2)]
	var outcome: Array = _judge(timings, 8.0, measurements)
	if outcome[0] != AcceptanceReport.RESULT_PASS:
		return "judged %s" % [outcome]
	if not str(outcome[1]).contains("level stress") or not str(outcome[1]).contains("build_view_s"):
		return "the message does not name the worst load and its slowest phase: %s" % outcome[1]
	var rows: Array = measurements.get("level_loads", [])
	if rows.size() != 2 or not (rows[1] as Dictionary).has("first_tick_s") or measurements.get("worst_total_s") != 3.7:
		return "measured %s" % measurements
	return ""


func test_a_load_over_the_budget_fails_naming_the_seed_and_slowest_phase() -> String:
	var timings: Array[Dictionary] = [_timing("run 4 level 5 seed 11", 6.5, 2.0, 0.1),
		_timing("level stress", 0.5, 3.0, 0.2)]
	var outcome: Array = _judge(timings, 8.0, {})
	if outcome[0] != AcceptanceReport.RESULT_FAIL:
		return "judged %s" % [outcome]
	for part: String in ["seed 11", "generate_s", "8.0 s"]:
		if not str(outcome[1]).contains(part):
			return "the message lacks '%s': %s" % [part, outcome[1]]
	return ""


func test_a_load_exactly_on_the_budget_passes() -> String:
	var outcome: Array = _judge([_timing("level stress", 4.0, 4.0, 0.0)] as Array[Dictionary], 8.0, {})
	return "" if outcome[0] == AcceptanceReport.RESULT_PASS else "judged %s" % [outcome]


func test_no_loads_fail() -> String:
	var outcome: Array = _judge([] as Array[Dictionary], 8.0, {})
	return "" if outcome[0] == AcceptanceReport.RESULT_FAIL else "judged %s" % [outcome]


func test_the_slowest_phase_is_the_longest_one() -> String:
	var slowest: String = (load(CHECK_SCRIPT) as GDScript).call("slowest_phase", _timing("x", 0.1, 0.2, 0.9))
	return "" if slowest == "first_tick_s" else "slowest phase %s" % slowest


func test_the_shipped_plan_loads_each_runs_deepest_level_through_the_shaft() -> String:
	var plan: LevelLoadPlan = LevelLoadPlan.load_file()
	var loads: Array[Dictionary] = plan.loads(SeedLevel.read_text(RunWiring.RUN_FILE), _shafts())
	if plan.error != "":
		return plan.error
	if plan.budget_seconds != 8.0 or loads.size() != plan.run_seeds.size() + plan.levels.size():
		return "budget %s, loads %s" % [plan.budget_seconds, loads]
	var run_text: String = SeedLevel.read_text(RunWiring.RUN_FILE)
	for index: int in plan.run_seeds.size():
		var run: RunPlan = RunPlan.build(plan.run_seeds[index], run_text)
		var deepest: int = run.level_seed_through(run.level_count() - 1, _shafts(), plan.shaft)
		var robot_scale: float = float((_shafts().risks[plan.shaft] as Dictionary)["robot_count"])
		if loads[index]["source"] != LevelSwitch.seed_source(deepest, robot_scale):
			return "run %d loads %s" % [plan.run_seeds[index], loads[index]]
	if loads[-1]["source"] != LevelSwitch.path_for("stress") or loads[-1]["shaft"] != "":
		return "the stress level is not loaded alone: %s" % loads[-1]
	return ""


func test_a_bad_plan_names_its_field() -> String:
	var cases: Dictionary = {
		'{"budget_seconds": 0, "run_seeds": [4, 8, 12], "shaft": "deep", "levels": []}': "budget_seconds",
		'{"budget_seconds": 8, "run_seeds": [4, 8], "shaft": "deep", "levels": []}': "run_seeds",
		'{"budget_seconds": 8, "run_seeds": [4, 8, -1], "shaft": "deep", "levels": []}': "run_seeds",
		'{"budget_seconds": 8, "run_seeds": [4, 8, 12], "shaft": "", "levels": []}': "shaft",
		'{"budget_seconds": 8, "run_seeds": [4, 8, 12], "shaft": "deep", "levels": ["../x"]}': "levels",
		'{"budget_seconds": 8, "run_seeds": [4, 8, 12], "shaft": "deep", "levels": [], "extra": 1}': "extra",
		'{"run_seeds": [4, 8, 12], "shaft": "deep", "levels": []}': "budget_seconds",
	}
	for text: String in cases:
		var plan: LevelLoadPlan = LevelLoadPlan.parse_json(text)
		if not plan.error.begins_with(cases[text]):
			return "%s gave '%s'" % [text, plan.error]
	return ""


func test_an_unknown_shaft_or_a_shallow_run_is_refused() -> String:
	var plan: LevelLoadPlan = LevelLoadPlan.parse_json(GOOD_PLAN.replace("\"deep\"", "\"sideways\""))
	plan.loads(SeedLevel.read_text(RunWiring.RUN_FILE), _shafts())
	if not plan.error.begins_with("shaft"):
		return "unknown shaft gave '%s'" % plan.error
	var run_text: String = SeedLevel.read_text(RunWiring.RUN_FILE)
	var shallow: int = 0
	while RunPlan.build(shallow, run_text).level_count() == RunPlan.build(shallow, run_text).max_levels:
		shallow += 1
	plan = LevelLoadPlan.parse_json(GOOD_PLAN.replace("[4, 8, 12]", "[4, 8, %d]" % shallow))
	if not plan.loads(run_text, _shafts()).is_empty() or not plan.error.begins_with("run_seeds: run %d" % shallow):
		return "shallow run %d gave '%s'" % [shallow, plan.error]
	return ""


func test_measuring_a_load_reports_every_phase_and_changes_no_state() -> String:
	var source: String = LevelSwitch.path_for("stress")
	var timing: Dictionary = LevelLoadTiming.measure(source, "")
	if timing.has("error"):
		return timing["error"]
	for key: String in LevelLoadTiming.PHASES + [LevelLoadTiming.TOTAL]:
		if float(timing.get(key, -1.0)) < 0.0:
			return "no %s in %s" % [key, timing]
	var unmeasured: int = LevelLoadTiming.unmeasured_hash(source, "")
	if unmeasured != int(timing["hash"]):
		return "hash %d measured, %d without" % [timing["hash"], unmeasured]
	return ""


func test_a_run_level_measured_gets_the_shafts_rules_and_the_same_hash() -> String:
	var plan: LevelLoadPlan = LevelLoadPlan.load_file()
	var loads: Array[Dictionary] = plan.loads(SeedLevel.read_text(RunWiring.RUN_FILE), _shafts())
	if loads.is_empty():
		return plan.error
	if LevelLoadTiming.rules_for(loads[0]["shaft"]) == null:
		return "no run rules for shaft %s" % loads[0]["shaft"]
	var timing: Dictionary = LevelLoadTiming.measure(loads[0]["source"], loads[0]["shaft"])
	if timing.has("error"):
		return timing["error"]
	var unmeasured: int = LevelLoadTiming.unmeasured_hash(loads[0]["source"], loads[0]["shaft"])
	return "" if unmeasured == int(timing["hash"]) else "hash %d measured, %d without" % [timing["hash"], unmeasured]


func test_a_rejected_level_is_an_error_not_a_time() -> String:
	var timing: Dictionary = LevelLoadTiming.measure("res://data/levels/missing_level.json", "")
	return "" if timing.has("error") else "measured %s" % timing


func test_an_undrawn_first_frame_reports_skipped_not_passed() -> String:
	var timing: Dictionary = _timing("level stress", 0.5, 3.0, 0.2)
	timing[LevelLoadTiming.FIRST_FRAME] = 0.1
	timing[LevelLoadTiming.TOTAL] = 3.8
	timing[LevelLoadTiming.DRAWN] = false
	var measurements: Dictionary = {}
	var outcome: Array = _judge([timing] as Array[Dictionary], 8.0, measurements)
	if outcome[0] != AcceptanceReport.RESULT_SKIPPED or not str(outcome[1]).contains("not the GPU's"):
		return "judged %s" % [outcome]
	if measurements.get("first_frame_drawn") != false or (measurements["level_loads"][0] as Dictionary).get("first_frame_s") != 0.1:
		return "measured %s" % measurements
	timing[LevelLoadTiming.TOTAL] = 9.0
	outcome = _judge([timing] as Array[Dictionary], 8.0, {})
	return "" if outcome[0] == AcceptanceReport.RESULT_FAIL else "over the budget undrawn judged %s" % [outcome]


func test_the_check_has_frame_work_and_fails_without_it() -> String:
	if not AcceptanceCheckFiles.frame_work().has("level_load"):
		return "no frame work for level_load: %s" % AcceptanceCheckFiles.problem()
	var outcome: Array = AcceptanceCheckFiles.judges()["level_load"].call(AcceptanceStep.new(), null, {})
	return "" if outcome[0] == AcceptanceReport.RESULT_FAIL else "judged %s with no frame work" % [outcome]


func test_a_load_begun_in_the_scene_counts_its_first_frame_and_leaves() -> String:
	var parent: Node3D = Node3D.new()
	var timing: Dictionary = LevelLoadTiming.begin(LevelSwitch.path_for("stress"), "", parent)
	if timing.has("error"):
		parent.free()
		return timing["error"]
	if parent.get_child_count() != 1 or parent.get_child(0).name != LevelLoadTiming.WORLD_NAME:
		parent.free()
		return "the load was not built in the parent"
	var done: Dictionary = LevelLoadTiming.finish(timing, true, int(timing["flown_usec"]) + 500000)
	var left: int = parent.get_child_count()
	parent.free()
	if left != 0:
		return "the load stayed in the scene"
	var phases: float = 0.0
	for key: String in LevelLoadTiming.PHASES:
		phases += float(done[key])
	if done[LevelLoadTiming.FIRST_FRAME] != 0.5 or done[LevelLoadTiming.DRAWN] != true \
			or absf(phases - float(done[LevelLoadTiming.TOTAL])) > 0.000005 or done.has("world"):
		return "finished %s" % done
	return ""


func test_the_frame_work_draws_each_load_in_turn_and_leaves_the_scene() -> String:
	var parent: Node3D = Node3D.new()
	var frames: AcceptanceFrameHook = AcceptanceFrameHook.new()
	var loads: Array[Dictionary] = [{"label": "a", "source": LevelSwitch.path_for("stress"), "shaft": ""},
		{"label": "b", "source": LevelSwitch.path_for("stress"), "shaft": ""}]
	var work: LevelLoadFrames = LevelLoadFrames.start_loads(loads, 8.0, "", parent, frames)
	var problem: String = ""
	if work.done or parent.get_child_count() != 1:
		problem = "the first load is not in the scene waiting for its frame"
	frames.still_waiting()
	if problem == "" and (work.timings.size() != 1 or parent.get_child_count() != 1):
		problem = "after one frame: %d timings, %d in the scene" % [work.timings.size(), parent.get_child_count()]
	frames.still_waiting()
	if problem == "" and (not work.done or work.error != "" or work.timings.size() != 2 or parent.get_child_count() != 0):
		problem = "after two frames: done %s, error '%s', %d timings" % [work.done, work.error, work.timings.size()]
	if problem == "" and (work.timings[1]["label"] != "b" or work.timings[1][LevelLoadTiming.DRAWN] != false):
		problem = "timed %s" % [work.timings[1]]
	frames.end()
	parent.free()
	return problem


func test_a_load_still_waiting_leaves_the_scene_when_the_step_ends() -> String:
	var parent: Node3D = Node3D.new()
	var frames: AcceptanceFrameHook = AcceptanceFrameHook.new()
	frames.draws = true
	var loads: Array[Dictionary] = [{"label": "a", "source": LevelSwitch.path_for("stress"), "shaft": ""}]
	LevelLoadFrames.start_loads(loads, 8.0, "", parent, frames)
	frames.end()
	var left: int = parent.get_child_count()
	parent.free()
	return "" if left == 0 else "the waiting load stayed in the scene"


func test_a_plan_error_stops_the_frame_work_naming_the_file() -> String:
	var parent: Node3D = Node3D.new()
	var frames: AcceptanceFrameHook = AcceptanceFrameHook.new()
	var work: LevelLoadFrames = LevelLoadFrames.start_loads([] as Array[Dictionary], 8.0, "shaft: bad", parent, frames)
	var left: int = parent.get_child_count()
	var waited: bool = frames.waiting()
	frames.end()
	parent.free()
	if not work.done or waited or left != 0:
		return "the frame work went on after a plan error"
	return "" if work.error == "level_load.json: shaft: bad" else "error '%s'" % work.error
