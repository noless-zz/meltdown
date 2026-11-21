extends RefCounted

## The m1 steps `refresh_rate_120` and `frame_budget_120` and the suite field
## `refresh_120` they use (#851, PRF-1, PRF-2, CMF-1, DEV-6): the field is
## read and checked; the 120 Hz option is on for that step only and the
## pilot's saved choice is neither replaced nor written; the frame budget
## follows the rate in use; and where no 120 Hz rate is offered both checks
## are skipped, never passed.

const FakeRuntime := preload("res://tests/fake_refresh_runtime.gd")
const FakeXr := preload("res://tests/fake_initialized_xr.gd")
const FRAME_LIMIT: int = 5000
const STEP_120: String = "{\"id\": \"r120\", \"preset\": 4, \"refresh_120\": true, \"checks\": [\"refresh_rate\"]}"
const STEP_PLAIN: String = "{\"id\": \"r\", \"preset\": 4, \"checks\": [\"refresh_rate\"]}"


static func _suite(steps: String) -> AcceptanceSuite:
	return AcceptanceSuite.parse_json("{\"name\": \"t851\", \"steps\": [%s]}" % steps)


func test_the_field_parses() -> String:
	var suite: AcceptanceSuite = _suite(STEP_120 + ", " + STEP_PLAIN)
	if suite.error != "":
		return suite.error
	if not suite.steps[0].refresh_120 or suite.steps[1].refresh_120:
		return "refresh_120 read as %s and %s" % [suite.steps[0].refresh_120, suite.steps[1].refresh_120]
	var cases: Dictionary = {
		STEP_120.replace("true", "1"): "refresh_120: must be true or false",
		STEP_120.replace("\"refresh_rate\"", "\"no_script_errors\""): "only used by the refresh_rate or frame_budget",
		STEP_120.replace("\"preset\": 4, ", ""): "needs a numbered preset",
	}
	for step_json: String in cases:
		var bad: AcceptanceSuite = _suite(step_json)
		if not bad.error.contains(cases[step_json]):
			return "%s gave '%s', expected %s" % [step_json, bad.error, cases[step_json]]
	return ""


func test_the_m1_suite_has_both_steps_and_keeps_the_90_hz_ones() -> String:
	var suite: AcceptanceSuite = AcceptanceSuite.load_named("m1")[0]
	if suite.error != "":
		return suite.error
	var by_id: Dictionary = {}
	for step: AcceptanceStep in suite.steps:
		by_id[step.id] = step
	for id: String in ["refresh_rate", "frame_budget", "refresh_rate_120", "frame_budget_120"]:
		if not by_id.has(id):
			return "m1 has no %s step" % id
	var rate_120: AcceptanceStep = by_id["refresh_rate_120"]
	if rate_120.preset != 4 or not rate_120.refresh_120 or rate_120.checks != [AcceptanceStep.CHECK_REFRESH_RATE]:
		return "refresh_rate_120: preset %d, 120 %s, checks %s" % [rate_120.preset, rate_120.refresh_120, rate_120.checks]
	var budget: AcceptanceStep = by_id["frame_budget"]
	var budget_120: AcceptanceStep = by_id["frame_budget_120"]
	if budget_120.preset != 4 or not budget_120.refresh_120 or budget_120.checks != budget.checks \
			or budget_120.replay_path != budget.replay_path or budget_120.settle_seconds != budget.settle_seconds \
			or budget_120.measure_seconds != budget.measure_seconds \
			or budget_120.max_over_budget_share != budget.max_over_budget_share \
			or budget_120.budget_slack_ms != budget.budget_slack_ms:
		return "frame_budget_120 does not fly frame_budget's replay and timings at preset 4 with 120 Hz"
	for id: String in ["refresh_rate", "frame_budget"]:
		var plain: AcceptanceStep = by_id[id]
		if plain.refresh_120 or plain.preset != AcceptanceStep.NO_PRESET:
			return "%s changed: 120 %s, preset %d" % [id, plain.refresh_120, plain.preset]
	if not ComfortPresetFiles.load_number(4).allow_120_hz:
		return "preset 4 does not allow 120 Hz"
	return ""


## Runs `suite` on a stand-in headset offering `rates`, with the scene's rate
## read back each frame as `main.gd` does. Returns [runner, main, runtime].
static func _fly(suite: AcceptanceSuite, rates: Array, pilot: RefreshChoice) -> Array:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	var rate: RefreshRate = main.get("refresh_rate")
	var runtime: RefCounted = FakeRuntime.new(rates, 90.0)
	rate.choice = pilot
	rate.begin(runtime, (main.get("comfort") as ComfortWiring).preset)
	var suites: Array[AcceptanceSuite] = [suite]
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = func(_code: int) -> void: pass
	runner.setup(main, suites, FakeXr.new())
	var frames: int = 0
	while not runner.finished and frames < FRAME_LIMIT:
		runner.process_frame(1.0 / 90.0)
		rate.advance_frame()
		frames += 1
	return [runner, main, runtime]


static func _done(flown: Array) -> void:
	var runner: AcceptanceRunner = flown[0]
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	(flown[1] as Node).free()
	runner.free()


func test_the_step_asks_for_120_only_for_itself_and_keeps_the_pilots_choice() -> String:
	var pilot: RefreshChoice = RefreshChoice.new()
	pilot.source = RefreshChoice.SOURCE_SAVED
	var saved_before: bool = FileAccess.file_exists(RefreshChoice.DEFAULT_PATH)
	var saved_text: String = FileAccess.get_file_as_string(RefreshChoice.DEFAULT_PATH) if saved_before else ""
	var flown: Array = _fly(_suite(STEP_120 + ", " + STEP_PLAIN), [72.0, 90.0, 120.0], pilot)
	var runner: AcceptanceRunner = flown[0]
	var main: Node = flown[1]
	var problem: String = ""
	if not runner.finished or runner.reports.is_empty():
		problem = "the runner did not finish: %s" % "\n".join(runner.messages)
	else:
		var steps: Array = runner.reports[0].steps
		var in_use: Array = [steps[0]["measurements"].get("refresh_rate_in_use_hz"),
			steps[1]["measurements"].get("refresh_rate_in_use_hz")]
		if steps[0]["result"] != AcceptanceReport.RESULT_PASS or in_use[0] != 120.0 \
				or steps[0]["measurements"].get("refresh_rate_wanted_hz") != 120.0:
			problem = "the 120 Hz step: %s, %s" % [steps[0]["result"], steps[0]["message"]]
		elif steps[1]["result"] != AcceptanceReport.RESULT_PASS or in_use[1] != 90.0 \
				or steps[1]["measurements"].get("refresh_rate_wanted_hz") != 90.0:
			problem = "the step after it: %s, %s" % [steps[1]["result"], steps[1]["message"]]
		elif (main.get("refresh_rate") as RefreshRate).choice != pilot or pilot.on:
			problem = "the pilot's choice was not put back unchanged"
		elif not (flown[2].get("requests") as Array).has(120.0):
			problem = "120 Hz was never asked for: %s" % [flown[2].get("requests")]
	if problem == "" and FileAccess.file_exists(RefreshChoice.DEFAULT_PATH) != saved_before:
		problem = "the step wrote %s" % RefreshChoice.DEFAULT_PATH
	if problem == "" and saved_before and FileAccess.get_file_as_string(RefreshChoice.DEFAULT_PATH) != saved_text:
		problem = "the step changed %s" % RefreshChoice.DEFAULT_PATH
	_done(flown)
	return problem


func test_without_120_offered_the_refresh_check_is_skipped_never_passed() -> String:
	var required: String = STEP_120.replace("\"id\": \"r120\"", "\"id\": \"q\", \"required\": true")
	var flown: Array = _fly(_suite(STEP_120 + ", " + required), [20.0], RefreshChoice.new())
	var runner: AcceptanceRunner = flown[0]
	var problem: String = ""
	if not runner.finished or runner.reports.is_empty():
		problem = "the runner did not finish"
	else:
		var steps: Array = runner.reports[0].steps
		if steps[0]["result"] != AcceptanceReport.RESULT_SKIPPED or not str(steps[0]["message"]).contains("does not offer 120 Hz"):
			problem = "without 120 offered: %s, %s" % [steps[0]["result"], steps[0]["message"]]
		elif steps[1]["result"] != AcceptanceReport.RESULT_FAIL:
			problem = "a required 120 Hz step without 120 offered is %s" % steps[1]["result"]
	_done(flown)
	return problem


func test_without_a_runtime_both_checks_are_skipped() -> String:
	var suite: AcceptanceSuite = AcceptanceSuite.load_named("m1")[0]
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	var problem: String = ""
	for step: AcceptanceStep in suite.steps:
		if not step.refresh_120:
			continue
		var outcome: Array = AcceptanceRefreshCheck.run(main, false, false, {}, true) \
			if step.has_check(AcceptanceStep.CHECK_REFRESH_RATE) \
			else AcceptanceFrameBudgetCheck.run(main, false, false, step, null, {})
		if outcome[0] != AcceptanceReport.RESULT_SKIPPED:
			problem = "%s off the headset: %s" % [step.id, outcome]
	main.free()
	return problem


func test_on_the_headset_without_120_the_frame_budget_is_skipped() -> String:
	var step: AcceptanceStep = _suite(STEP_120.replace("\"refresh_rate\"", "\"frame_budget\"").replace(
		"]}", "], \"settle_seconds\": 1, \"measure_seconds\": 1, \"max_over_budget_share\": 0.01, \"budget_slack_ms\": 1}")).steps[0]
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	var rate: RefreshRate = main.get("refresh_rate")
	rate.offered = [72.0, 90.0] as Array[float]
	rate.in_use_hz = 90.0
	var measured: AcceptanceFrameBudgetCheck = AcceptanceFrameBudgetCheck.new(step)
	for index: int in 200:
		measured.add(1.0 / 90.0)
	var outcome: Array = AcceptanceFrameBudgetCheck.run(main, true, true, step, measured, {})
	var problem: String = ""
	if outcome[0] != AcceptanceReport.RESULT_SKIPPED or not str(outcome[1]).contains("does not offer 120 Hz"):
		problem = "90 Hz frames on a runtime without 120: %s" % [outcome]
	rate.offered = [72.0, 90.0, 120.0] as Array[float]
	rate.in_use_hz = 120.0
	measured = AcceptanceFrameBudgetCheck.new(step)
	for index: int in 300:
		measured.add(1.0 / 120.0)
	outcome = AcceptanceFrameBudgetCheck.run(main, true, true, step, measured, {})
	if problem == "" and outcome[0] != AcceptanceReport.RESULT_PASS:
		problem = "steady 120 Hz frames with 120 offered: %s" % [outcome]
	main.free()
	return problem


func test_the_budget_follows_the_rate_in_use() -> String:
	var step: AcceptanceStep = AcceptanceStep.new()
	step.max_over_budget_share = 0.01
	step.budget_slack_ms = 1.0
	var ten_ms: Array[float] = []
	var at_120: Array[float] = []
	for index: int in 3600:
		ten_ms.append(0.010)
		at_120.append(1.0 / 120.0)
	var measurements: Dictionary = {}
	var outcome: Array = AcceptanceFrameBudgetCheck.judge(at_120, 120.0, step, measurements)
	if outcome[0] != AcceptanceReport.RESULT_PASS:
		return "steady 8.3 ms frames at 120 Hz: %s" % [outcome]
	# 10 ms holds 90 Hz's 11.1 ms but not 120 Hz's 8.3 ms plus 1 ms slack.
	if AcceptanceFrameBudgetCheck.judge(ten_ms, 90.0, step, {})[0] != AcceptanceReport.RESULT_PASS:
		return "10 ms frames failed at 90 Hz"
	outcome = AcceptanceFrameBudgetCheck.judge(ten_ms, 120.0, step, {})
	if outcome[0] != AcceptanceReport.RESULT_FAIL:
		return "10 ms frames at 120 Hz: %s" % [outcome]
	return ""
