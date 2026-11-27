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
