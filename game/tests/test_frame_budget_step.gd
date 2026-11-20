extends RefCounted

## The m1 `frame_budget` step (#643, PRF-1, CMF-1, DEV-6, gate G1): synthetic
## frame times pass, fail on the 99th percentile, fail on the share over
## budget and fail below 90 Hz; off the headset the step is skipped, never
## passed; the suite keys are checked; and the runner measures frames on a
## stand-in headset.

const FakeXr := preload("res://tests/fake_initialized_xr.gd")
const FRAME_90: float = 1.0 / 90.0
const FRAME_LIMIT: int = 20000


func _step(share: float = 0.01, slack_ms: float = 1.0) -> AcceptanceStep:
	var step: AcceptanceStep = AcceptanceStep.new()
	step.id = "frame_budget"
	step.checks.append(AcceptanceStep.CHECK_FRAME_BUDGET)
	step.settle_seconds = 2.0
	step.measure_seconds = 30.0
	step.max_over_budget_share = share
	step.budget_slack_ms = slack_ms
	return step


## 2700 frames of about 11.1 ms with a little jitter, `slow` of them `slow_ms` long.
func _frames(slow: int, slow_ms: float) -> Array[float]:
	var frames: Array[float] = []
	for index: int in 2700:
		var jitter: float = 0.0003 if index % 2 == 0 else -0.0003
		frames.append(slow_ms / 1000.0 if index < slow else FRAME_90 + jitter)
	return frames


func test_steady_90_hz_passes_with_every_number_reported() -> String:
	var measurements: Dictionary = {}
	var outcome: Array = AcceptanceFrameBudgetCheck.judge(_frames(5, 30.0), 90.0, _step(), measurements)
	if outcome[0] != AcceptanceReport.RESULT_PASS:
		return "steady 90 Hz: %s" % [outcome]
	for key: String in ["refresh_rate_in_use_hz", "frame_count", "mean_ms", "p95_ms", "p99_ms", "over_budget",
			"over_budget_share", "max_over_budget_share", "budget_slack_ms", "dropped", "summary"]:
		if not measurements.has(key):
			return "measurement %s missing: %s" % [key, measurements]
	if measurements["frame_count"] != 2700 or measurements["over_budget"] != 5 or measurements["dropped"] != 5:
		return "counts wrong: %s" % measurements
	if not str(measurements["summary"]).contains("p99") or outcome[1] != measurements["summary"]:
		return "the pass message does not carry the numbers: %s" % outcome[1]
	return ""


func test_a_slow_99th_percentile_fails() -> String:
	# 3% of frames at 13 ms: over the 12.1 ms limit, though no display refresh was missed.
	var outcome: Array = AcceptanceFrameBudgetCheck.judge(_frames(81, 13.0), 90.0, _step(), {})
	if outcome[0] != AcceptanceReport.RESULT_FAIL or not str(outcome[1]).begins_with("p99 13.00 ms"):
		return "3%% slow frames: %s" % [outcome]
	return ""


func test_too_many_frames_over_budget_fails() -> String:
	# 0.5% over budget keeps the p99 within it, but the step allows only 0.2%.
	var outcome: Array = AcceptanceFrameBudgetCheck.judge(_frames(14, 25.0), 90.0, _step(0.002), {})
	if outcome[0] != AcceptanceReport.RESULT_FAIL or not str(outcome[1]).contains("of frames over budget, allowed 0.2%"):
		return "0.5%% over with 0.2%% allowed: %s" % [outcome]
	return ""


func test_72_hz_fails_with_the_rate_as_the_reason() -> String:
	var frames: Array[float] = []
	for index: int in 2160:
		frames.append(1.0 / 72.0)
	var outcome: Array = AcceptanceFrameBudgetCheck.judge(frames, 72.0, _step(), {})
	if outcome[0] != AcceptanceReport.RESULT_FAIL or not str(outcome[1]).begins_with("72.0 Hz in use"):
		return "72 Hz: %s" % [outcome]
	outcome = AcceptanceFrameBudgetCheck.judge(frames, RefreshRate.UNKNOWN, _step(), {})
	if outcome[0] != AcceptanceReport.RESULT_FAIL:
		return "an unknown rate: %s" % [outcome]
	return ""


func test_no_frames_fails() -> String:
	var outcome: Array = AcceptanceFrameBudgetCheck.judge([] as Array[float], 90.0, _step(), {})
	return "" if outcome[0] == AcceptanceReport.RESULT_FAIL else "no frames: %s" % [outcome]


func test_off_the_headset_it_is_skipped_never_passed() -> String:
	var main: Node = Node.new()
	var problem: String = ""
	for case: Array in [[false, false], [false, true], [true, false]]:
		var outcome: Array = AcceptanceFrameBudgetCheck.run(main, case[0], case[1], _step(), null, {})
		if outcome[0] != AcceptanceReport.RESULT_SKIPPED or not str(outcome[1]).begins_with("not on the headset"):
			problem = "xr %s, headset %s: %s" % [case[0], case[1], outcome]
	var required: AcceptanceStep = _step()
	required.required = true
	if problem == "" and AcceptanceFrameBudgetCheck.run(main, true, false, required, null, {})[0] \
			!= AcceptanceReport.RESULT_FAIL:
		problem = "a required step was not failed off the headset"
	main.free()
	return problem


func test_the_settle_period_is_not_measured() -> String:
	var measured: AcceptanceFrameBudgetCheck = AcceptanceFrameBudgetCheck.new(_step())
	var added: int = 0
	while not measured.done() and added < FRAME_LIMIT:
		measured.add(FRAME_90)
		added += 1
	# 32 s at 90 Hz is 2880 frames; the first 180 settle.
	if added < 2879 or added > 2881 or measured.frames.size() < 2699 or measured.frames.size() > 2701:
		return "%d frames added, %d measured" % [added, measured.frames.size()]
	measured.add(FRAME_90)
	return "" if measured.frames.size() <= 2701 else "frames were kept after the measured period"


func test_the_m1_suite_names_the_step_and_its_values() -> String:
	var suite: AcceptanceSuite = AcceptanceSuite.load_named("m1")[0]
	if suite.error != "":
		return suite.error
	var step: AcceptanceStep = suite.steps[suite.steps.size() - 1]
	if step.id != "frame_budget" or step.checks != [AcceptanceStep.CHECK_FRAME_BUDGET] \
			or step.measure_seconds != 30.0 or step.max_over_budget_share != 0.01 or step.settle_seconds <= 0.0:
		return "m1's last step: %s %s %s %s" % [step.id, step.checks, step.measure_seconds, step.max_over_budget_share]
	var replay: Replay = Replay.load_file(step.replay_path)
	if replay.error != "" or not replay.robots.is_empty():
		return "the flight replay: '%s', %d robots" % [replay.error, replay.robots.size()]
	# One tick per frame: the flight lasts the whole measured period at 90 Hz.
	if replay.frames.size() < int((step.settle_seconds + step.measure_seconds) * 90.0):
		return "the flight replay has %d ticks, shorter than the step" % replay.frames.size()
	return ""


func test_the_suite_keys_are_checked() -> String:
	var keys: String = "\"settle_seconds\": 2, \"measure_seconds\": 30, \"max_over_budget_share\": 0.01, \"budget_slack_ms\": 1"
	var cases: Dictionary = {
		"{\"id\": \"f\", \"checks\": [\"frame_budget\"]}": "settle_seconds",
		"{\"id\": \"f\", \"checks\": [\"refresh_rate\"], %s}" % keys: "only used by the frame_budget check",
		"{\"id\": \"f\", \"checks\": [\"frame_budget\"], %s}" % keys.replace("30", "true"): "measure_seconds: must be a number",
		"{\"id\": \"f\", \"checks\": [\"frame_budget\"], %s}" % keys.replace("30", "0"): "measure_seconds",
		"{\"id\": \"f\", \"checks\": [\"frame_budget\"], %s}" % keys.replace("0.01", "1.5"): "max_over_budget_share",
		"{\"id\": \"f\", \"checks\": [\"frame_budget\"], %s}" % keys.replace("\"budget_slack_ms\": 1", "\"budget_slack_ms\": 9"): "budget_slack_ms",
	}
	for step_json: String in cases:
		var suite: AcceptanceSuite = AcceptanceSuite.parse_json("{\"name\": \"x\", \"steps\": [%s]}" % step_json)
		if suite.error == "" or not suite.error.contains(cases[step_json]):
			return "%s gave '%s', expected %s" % [step_json, suite.error, cases[step_json]]
	var good: AcceptanceSuite = AcceptanceSuite.parse_json(
		"{\"name\": \"x\", \"steps\": [{\"id\": \"f\", \"checks\": [\"frame_budget\"], %s}]}" % keys)
	return good.error


## The runner on a stand-in headset at 90 Hz: it flies the replay, measures the
## frames it is handed and records a pass with the numbers; the scene is left running.
func test_the_runner_measures_frames_on_the_headset() -> String:
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	var main: Node = scene.instantiate()
	var rate: RefreshRate = main.get("refresh_rate")
	rate.in_use_hz = 90.0
	var suite: AcceptanceSuite = AcceptanceSuite.parse_json("{\"name\": \"t643\", \"steps\": [{\"id\": \"f\", "
		+ "\"replay\": \"res://acceptance/replays/frame_budget_flight.replay\", \"checks\": [\"frame_budget\"], "
		+ "\"settle_seconds\": 1, \"measure_seconds\": 5, \"max_over_budget_share\": 0.01, \"budget_slack_ms\": 1}]}")
	var suites: Array[AcceptanceSuite] = [suite]
	var xr: XRInterface = FakeXr.new()
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = func(_code: int) -> void: pass
	runner.on_headset = true
	runner.setup(main, suites, xr)
	var frames: int = 0
	while not runner.finished and frames < FRAME_LIMIT:
		runner.process_frame(FRAME_90)
		frames += 1
	var problem: String = ""
	if not runner.finished or runner.reports.is_empty():
		problem = "the runner did not finish: %s" % "\n".join(runner.messages)
	else:
		var step: Dictionary = runner.reports[0].steps[0]
		var count: Variant = step["measurements"].get("frame_count")
		if step["result"] != AcceptanceReport.RESULT_PASS or count == null or int(count) < 449 or int(count) > 451:
			problem = "step %s, %s frames: %s" % [step["result"], count, step["message"]]
		elif not main.is_processing():
			problem = "the scene was left with its processing switched off"
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	main.free()
	runner.free()
	return problem
