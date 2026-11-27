extends RefCounted

## Step time limits, suite reports as each suite ends, the exit file and the step lines' position
## fields (#1444, DEV-6, DEV-7). The scene is instantiated outside the tree, as in
## `test_acceptance_runner.gd`; a fake clock stands in for wall time.

const M1_HASH: int = 861662111
const REPLAY: String = "res://acceptance/replays/basic_flight.replay"
const FRAME_LIMIT: int = 4000
const FakeXr: GDScript = preload("res://tests/fake_initialized_xr.gd")

var _now_msec: int = 0
## Milliseconds the fake clock moves on each frame.
var _step_msec: int = 0


func _clock() -> int:
	_now_msec += _step_msec
	return _now_msec


func _on_quit(_code: int) -> void:
	pass


func _runner(suites: Array[AcceptanceSuite], xr: XRInterface = null) -> AcceptanceRunner:
	_now_msec = 0
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = _on_quit
	runner.clock_msec = _clock
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	runner.setup(scene.instantiate(), suites, xr)
	return runner


func _finish(runner: AcceptanceRunner) -> void:
	var frames: int = 0
	while not runner.finished and frames < FRAME_LIMIT:
		runner.process_frame()
		frames += 1


func _done(runner: AcceptanceRunner) -> void:
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	if runner.exit_path != "":
		DirAccess.remove_absolute(runner.exit_path)
	runner.main.free()
	runner.free()


func _suite(name: String, steps_json: String, extra: String = "") -> AcceptanceSuite:
	return AcceptanceSuite.parse_json("{\"name\": \"%s\", %s\"steps\": [%s]}" % [name, extra, steps_json])


func _fly_step(id: String) -> String:
	return "{\"id\": \"%s\", \"replay\": \"%s\", \"checks\": [\"final_hash\"], \"expected_hash\": %d}" \
		% [id, REPLAY, M1_HASH]


## With an initialized runtime whose session never begins, an xr_session step waits: the stuck
## wait of #1439 in miniature.
func test_a_step_that_never_finishes_fails_at_its_limit_and_the_next_runs() -> String:
	var suite: AcceptanceSuite = _suite("t1444",
		"{\"id\": \"stuck\", \"checks\": [\"xr_session\"], \"time_limit_seconds\": 5}, " + _fly_step("after"))
	if suite.error != "":
		return suite.error
	var suites: Array[AcceptanceSuite] = [suite]
	_step_msec = 1000
	var runner: AcceptanceRunner = _runner(suites, FakeXr.new())
	var frames: int = 0
	while not runner.finished and frames < FRAME_LIMIT:
		runner.process_frame()
		frames += 1
		if not runner.reports.is_empty() and not runner.reports[0].steps.is_empty():
			_step_msec = 0  # The clock stops once the stuck step is failed, so the next has time.
	var problem: String = ""
	var steps: Array[Dictionary] = runner.reports[0].steps if not runner.reports.is_empty() else []
	if not runner.finished:
		problem = "the runner never finished: %s" % "\n".join(runner.messages)
	elif steps.size() != 2:
		problem = "%d steps reported, expected 2" % steps.size()
	elif steps[0]["result"] != AcceptanceReport.RESULT_FAIL or steps[0]["message"] != "timed out after 5 s at tick 0":
		problem = "the stuck step is %s: '%s'" % [steps[0]["result"], steps[0]["message"]]
	elif steps[1]["result"] != AcceptanceReport.RESULT_PASS:
		problem = "the step after it is %s: %s" % [steps[1]["result"], steps[1]["message"]]
	elif runner.exit_code != AcceptanceRunner.EXIT_FAIL:
		problem = "exit %d with a timed-out step" % runner.exit_code
	elif not runner.main.is_processing():
		problem = "the scene was left with its processing switched off"
	_done(runner)
	return problem


## A replay stuck mid-flight is failed at the tick it reached, and the scene runs again.
func test_a_timed_out_replay_names_its_tick() -> String:
	var suite: AcceptanceSuite = _suite("t1444", _fly_step("slow"), "\"default_time_limit_seconds\": 3, ")
	if suite.error != "":
		return suite.error
	var suites: Array[AcceptanceSuite] = [suite]
	_step_msec = 100
	var runner: AcceptanceRunner = _runner(suites)
	_finish(runner)
	var problem: String = ""
	var message: String = str(runner.reports[0].steps[0]["message"]) if not runner.reports.is_empty() else ""
	var limit: String = AcceptanceTimeLimit.format_seconds(AcceptanceTimeLimit.seconds_for(suite.steps[0], 3.0))
	if runner.reports.is_empty() or runner.reports[0].steps.size() != 1:
		problem = "no step was reported: %s" % "\n".join(runner.messages)
	elif not message.begins_with("timed out after %s s at tick " % limit) or message.ends_with(" tick 0"):
		problem = "the message does not name the tick reached: '%s'" % message
	elif not runner.main.is_processing():
		problem = "the scene was left with its processing switched off"
	_done(runner)
	return problem


func test_a_suite_report_is_written_before_the_next_suite_starts() -> String:
	var suites: Array[AcceptanceSuite] = [_suite("ta", _fly_step("one")), _suite("tb", _fly_step("two"))]
	_step_msec = 0
	var runner: AcceptanceRunner = _runner(suites)
	var problem: String = "the second suite never started"
	var frames: int = 0
	while not runner.finished and frames < FRAME_LIMIT:
		runner.process_frame()
		frames += 1
		if runner.messages[runner.messages.size() - 1].contains("suite=tb index=1"):
			var expected: String = "user://acceptance/ta-%s.json" % BuildInfo.UNKNOWN
			problem = "" if runner.report_paths == [expected] and FileAccess.file_exists(expected) \
				else "at the start of tb the reports written were %s" % [runner.report_paths]
			break
	_finish(runner)
	if problem == "" and runner.report_paths.size() != 2:
		problem = "%d reports written, expected 2" % runner.report_paths.size()
	_done(runner)
	return problem


func test_the_exit_file_holds_the_result() -> String:
	var suites: Array[AcceptanceSuite] = [_suite("ta", _fly_step("one"))]
	_step_msec = 0
	var runner: AcceptanceRunner = _runner(suites)
	_finish(runner)
	var problem: String = ""
	var expected: String = "user://acceptance/" + AcceptanceRunOutput.EXIT_FILE
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(expected))
	if runner.exit_path != expected or typeof(data) != TYPE_DICTIONARY:
		problem = "no exit file at %s (written: '%s')" % [expected, runner.exit_path]
	elif data["suites"] != ["ta"] or data["passed"] != ["ta"] or data["failed"] != [] or data["skipped"] != []:
		problem = "the exit file's suites are wrong: %s" % data
	elif int(data["exit_code"]) != AcceptanceRunner.EXIT_PASS or data["build"] != BuildInfo.UNKNOWN:
		problem = "the exit file's code or build is wrong: %s" % data
	elif not str(data["finished"]).ends_with("Z") or str(data["finished"]).length() != 20:
		problem = "finished is not a UTC time: %s" % data["finished"]
	_done(runner)
	return problem


func test_exit_data_sorts_suites_by_outcome() -> String:
	var passed: AcceptanceReport = AcceptanceReport.new("a")
	passed.add_step("x", AcceptanceReport.RESULT_PASS)
	var failed: AcceptanceReport = AcceptanceReport.new("b")
	failed.add_step("x", AcceptanceReport.RESULT_FAIL, "timed out after 120 s at tick 4")
	var skipped: AcceptanceReport = AcceptanceReport.new("c")
	var reports: Array[AcceptanceReport] = [passed, failed, skipped]
	var data: Dictionary = AcceptanceRunOutput.exit_data("abc", reports, 1, "2026-11-27T08:00:00Z")
	var expected: Dictionary = {"build": "abc", "suites": ["a", "b", "c"], "passed": ["a"], "failed": ["b"],
		"skipped": ["c"], "exit_code": 1, "finished": "2026-11-27T08:00:00Z"}
	return "" if data == expected else "exit data %s, expected %s" % [data, expected]


func test_step_lines_carry_suite_index_and_count() -> String:
	var suites: Array[AcceptanceSuite] = [_suite("t1444", _fly_step("one") + ", " + _fly_step("two"))]
	_step_msec = 0
	var runner: AcceptanceRunner = _runner(suites)
	_finish(runner)
	var wanted: Array[String] = [
		"Meltdown: acceptance: step one suite=t1444 index=1 count=2",
		"Meltdown: acceptance: step one pass suite=t1444 index=1 count=2",
		"Meltdown: acceptance: step two suite=t1444 index=2 count=2",
		"Meltdown: acceptance: step two pass suite=t1444 index=2 count=2",
	]
	var problem: String = ""
	for line: String in wanted:
		if not runner.messages.has(line):
			problem = "no line '%s' in: %s" % [line, "\n".join(runner.messages)]
			break
	_done(runner)
	return problem


func test_limits_are_read_and_bad_values_named() -> String:
	var suite: AcceptanceSuite = _suite("t", "{\"id\": \"a\", \"checks\": [\"xr_session\"], \"time_limit_seconds\": 2.5}",
		"\"default_time_limit_seconds\": 30, ")
	if suite.error != "" or suite.default_time_limit_seconds != 30.0 or suite.steps[0].time_limit_seconds != 2.5:
		return "limits not read: '%s'" % suite.error
	if AcceptanceTimeLimit.seconds_for(suite.steps[0], 30.0) != 2.5:
		return "the step's own limit did not win over the suite's"
	if _suite("t", "{\"id\": \"a\", \"checks\": [\"xr_session\"]}").default_time_limit_seconds \
			!= AcceptanceTimeLimit.DEFAULT_SECONDS:
		return "a suite with no default did not get %s s" % AcceptanceTimeLimit.DEFAULT_SECONDS
	var bad_step: String = _suite("t", "{\"id\": \"a\", \"checks\": [\"xr_session\"], \"time_limit_seconds\": 0}").error
	if not bad_step.contains("steps[0].time_limit_seconds"):
		return "a zero step limit was not named: '%s'" % bad_step
	var bad_suite: String = _suite("t", "{\"id\": \"a\", \"checks\": [\"xr_session\"]}",
		"\"default_time_limit_seconds\": \"long\", ").error
	if not bad_suite.contains("default_time_limit_seconds"):
		return "a bad suite default was not named: '%s'" % bad_suite
	return ""


## The soak measures for 1500 s: the default is counted on top of what the step waits for.
func test_the_default_leaves_room_for_the_steps_own_waiting() -> String:
	var soak: Array[AcceptanceSuite] = AcceptanceSuite.load_named("soak")
	if soak[0].error != "":
		return soak[0].error
	var limit: float = AcceptanceTimeLimit.seconds_for(soak[0].steps[0], soak[0].default_time_limit_seconds)
	if limit != AcceptanceTimeLimit.DEFAULT_SECONDS + 1505.0:
		return "the soak step's limit is %s s" % limit
	if AcceptanceTimeLimit.message(120.0, 7) != "timed out after 120 s at tick 7":
		return "message: '%s'" % AcceptanceTimeLimit.message(120.0, 7)
	return ""


## On the headset a replay flies one tick per frame, at 72 Hz at worst (PRF-1): the m4 steps that fly
## the longest replays get that time on top of the default, or they would time out mid-flight.
func test_the_default_leaves_room_for_the_replays_flight_at_72_hz() -> String:
	var m4: Array[AcceptanceSuite] = AcceptanceSuite.load_named("m4")
	if m4.is_empty() or m4[0].error != "":
		return "m4 did not load: %s" % ("" if m4.is_empty() else m4[0].error)
	# Each step's replay ticks, pinned low so a cut replay still passes but an uncounted one fails.
	var least_ticks: Dictionary[String, int] = {"shaft_rewards": 16000, "crew_joins": 10000}
	var found: int = 0
	for step: AcceptanceStep in m4[0].steps:
		if not least_ticks.has(step.id):
			continue
		found += 1
		var ticks: int = 0
		for path: String in [step.replay_path, step.next_replay_path]:
			if path != "":
				ticks += Replay.load_file(path).frames.size()
		if ticks < least_ticks[step.id]:
			return "%s flies %d ticks, fewer than the %d this test expects" % [step.id, ticks, least_ticks[step.id]]
		var limit: float = AcceptanceTimeLimit.seconds_for(step, m4[0].default_time_limit_seconds)
		var least: float = AcceptanceTimeLimit.DEFAULT_SECONDS + float(ticks) / 72.0
		if limit < least:
			return "%s may run %s s; flying %d ticks at 72 Hz needs %s s" % [step.id, limit, ticks, least]
	return "" if found == least_ticks.size() else "m4 has %d of the steps %s" % [found, least_ticks.keys()]
