extends RefCounted

## The acceptance launch switch and runner (DEV-6, PLT-4, #165): the m1 suite
## flown in the flat main scene, a wrong hash, an unknown suite, skipped and
## required checks. The scene is instantiated outside the tree, so `_ready`
## does not run and no XR session or renderer is needed.

const M1_HASH: int = 861662111
const REPLAY: String = "res://acceptance/replays/basic_flight.replay"
## More frames than any suite here needs; a runner still going after this hangs.
const FRAME_LIMIT: int = 20000  # m1 flies flight_axes three times (#686, #687).
const FLIGHT_FRAME_SECONDS: float = 0.25

var _quit_codes: Array[int] = []


func _main() -> Node:
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	return scene.instantiate() if scene != null else null


func _on_quit(code: int) -> void:
	_quit_codes.append(code)


## Runs `suites` in a fresh main scene with no OpenXR runtime until the runner
## finishes. Returns the runner; the caller frees it and its scene.
func _run(suites: Array[AcceptanceSuite]) -> AcceptanceRunner:
	_quit_codes.clear()
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = _on_quit
	runner.setup(_main(), suites, null)
	var frames: int = 0
	while not runner.finished and frames < FRAME_LIMIT:
		# The flight test step (#762) is timed by the scene's own frames, which
		# `main._process` runs in the game; out of a tree they are run here.
		var checks: AcceptanceChecks = runner.get("_checks")
		var flight: AcceptanceFlightTestCheck = checks.flight if checks != null else null
		if flight != null and not flight.done():
			runner.main.call("apply_controls", {})
			runner.main.call("advance_frame", FLIGHT_FRAME_SECONDS)
			runner.process_frame(FLIGHT_FRAME_SECONDS)
		else:
			runner.process_frame()
		frames += 1
	return runner


func _done(runner: AcceptanceRunner) -> void:
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	if runner.main != null:
		runner.main.free()
	runner.free()


func _suite(step_json: String) -> Array[AcceptanceSuite]:
	var suite: AcceptanceSuite = AcceptanceSuite.parse_json(
		"{\"name\": \"t165\", \"steps\": [%s]}" % step_json)
	var found: Array[AcceptanceSuite] = [suite]
	return found


func test_switch_is_off_without_argument_or_extra() -> String:
	if AcceptanceRunner.requested_suite(PackedStringArray(["--comfort-preset=2"]), "") != "":
		return "an unrelated argument asked for a suite"
	if AcceptanceRunner.requested_suite(PackedStringArray(), "  ") != "":
		return "a blank intent extra asked for a suite"
	return ""


func test_switch_reads_the_argument_then_the_intent_extra() -> String:
	if AcceptanceRunner.requested_suite(PackedStringArray(["--acceptance=m1"]), "") != "m1":
		return "--acceptance=m1 was not read"
	if AcceptanceRunner.requested_suite(PackedStringArray(), " m0 ") != "m0":
		return "the intent extra was not read"
	if AcceptanceRunner.requested_suite(PackedStringArray(["--acceptance=m1"]), "m0") != "m1":
		return "the intent extra won over the command line"
	return ""


func test_m1_suite_passes_in_the_flat_main_scene() -> String:
	var runner: AcceptanceRunner = _run(AcceptanceSuite.load_named("m1"))
	var problem: String = ""
	if not runner.finished:
		problem = "the runner did not finish within %d frames" % FRAME_LIMIT
	elif runner.exit_code != AcceptanceRunner.EXIT_PASS or _quit_codes != [AcceptanceRunner.EXIT_PASS]:
		problem = "exit %d, quit with %s: %s" % [runner.exit_code, _quit_codes, "\n".join(runner.messages)]
	elif runner.reports.size() != 1 or not runner.reports[0].passed():
		problem = "the m1 report did not pass"
	else:
		var step: Dictionary = runner.reports[0].steps[0]
		# Found by id: later steps (flight_axes, #686) follow it in the suite.
		var frame_step: Dictionary = {"id": "", "result": "missing"}
		for entry: Dictionary in runner.reports[0].steps:
			if entry["id"] == "frame_budget":
				frame_step = entry
		if step["measurements"].get("final_hash") != M1_HASH:
			problem = "final hash %s, expected %d" % [step["measurements"].get("final_hash"), M1_HASH]
		elif frame_step["id"] != "frame_budget" or frame_step["result"] != AcceptanceReport.RESULT_SKIPPED:
			# Frame times off the headset prove nothing about PRF-1 (#643).
			problem = "the frame_budget step is %s off the headset" % frame_step["result"]
	if problem == "":
		problem = _check_report_file(runner)
	if problem == "" and not runner.main.is_processing():
		problem = "the scene was left with its processing switched off"
	_done(runner)
	return problem


## The m2 replay starts with weapons and robots; the runner must give its
## session both, or the bot's shots and the robots are missing and the hash
## differs on every device (#270).
func test_m2_suite_passes_in_the_flat_main_scene() -> String:
	var runner: AcceptanceRunner = _run(AcceptanceSuite.load_named("m2"))
	var problem: String = ""
	if runner.exit_code != AcceptanceRunner.EXIT_PASS or runner.reports.size() != 1 \
			or not runner.reports[0].passed():
		problem = "exit %d: %s" % [runner.exit_code, "\n".join(runner.messages)]
	elif not (runner.main.get("session") as LocalSession).sim.robots.is_empty():
		problem = "robots are left after the m2 replay"
	_done(runner)
	return problem


func _check_report_file(runner: AcceptanceRunner) -> String:
	var expected: String = "user://acceptance/m1-%s.json" % BuildInfo.UNKNOWN
	if runner.report_paths != [expected]:
		return "report written to %s, expected %s" % [runner.report_paths, expected]
	var text: String = FileAccess.get_file_as_string(expected)
	if text.strip_edges() != runner.reports[0].to_json():
		return "the report file does not hold the report"
	if not runner.messages.has(AcceptanceReport.LOG_BEGIN) or not runner.messages.has(AcceptanceReport.LOG_END):
		return "the log markers were not printed"
	return ""


func test_wrong_expected_hash_fails_and_names_both_hashes() -> String:
	var runner: AcceptanceRunner = _run(_suite(
		"{\"id\": \"fly\", \"replay\": \"%s\", \"checks\": [\"final_hash\"], \"expected_hash\": 12345}" % REPLAY))
	var problem: String = ""
	if runner.exit_code != AcceptanceRunner.EXIT_FAIL or _quit_codes != [AcceptanceRunner.EXIT_FAIL]:
		problem = "exit %d with a wrong hash" % runner.exit_code
	else:
		var step: Dictionary = runner.reports[0].steps[0]
		var message: String = step["message"]
		if step["result"] != AcceptanceReport.RESULT_FAIL:
			problem = "the step is %s" % step["result"]
		elif not message.contains("12345") or not message.contains(str(M1_HASH)):
			problem = "the message does not name both hashes: '%s'" % message
	_done(runner)
	return problem


func test_unknown_suite_exits_1_with_a_message() -> String:
	var runner: AcceptanceRunner = _run(AcceptanceSuite.load_named("no_such_suite"))
	var problem: String = ""
	if runner.exit_code != AcceptanceRunner.EXIT_FAIL or _quit_codes != [AcceptanceRunner.EXIT_FAIL]:
		problem = "exit %d for an unknown suite" % runner.exit_code
	elif not "\n".join(runner.messages).contains("no_such_suite"):
		problem = "no message names the suite: %s" % runner.messages
	elif not runner.reports.is_empty():
		problem = "an unknown suite produced a report"
	_done(runner)
	return problem


func test_xr_check_is_skipped_without_a_runtime_unless_required() -> String:
	var runner: AcceptanceRunner = _run(_suite(
		"{\"id\": \"fly\", \"replay\": \"%s\", \"checks\": [\"final_hash\"], \"expected_hash\": %d}, " % [REPLAY, M1_HASH]
		+ "{\"id\": \"xr\", \"checks\": [\"xr_session\"]}"))
	var problem: String = ""
	if runner.exit_code != AcceptanceRunner.EXIT_PASS:
		problem = "a skipped xr_session step failed the run: %s" % "\n".join(runner.messages)
	elif runner.reports[0].steps[1]["result"] != AcceptanceReport.RESULT_SKIPPED:
		problem = "the xr_session step is %s" % runner.reports[0].steps[1]["result"]
	_done(runner)
	if problem != "":
		return problem
	runner = _run(_suite("{\"id\": \"xr\", \"checks\": [\"xr_session\"], \"required\": true}"))
	if runner.exit_code != AcceptanceRunner.EXIT_FAIL:
		problem = "a required xr_session step passed without a runtime"
	elif runner.reports[0].steps[0]["result"] != AcceptanceReport.RESULT_FAIL:
		problem = "the required step is %s" % runner.reports[0].steps[0]["result"]
	_done(runner)
	return problem


func test_preset_is_set_and_no_script_errors_passes() -> String:
	var runner: AcceptanceRunner = _run(_suite(
		"{\"id\": \"calm\", \"replay\": \"%s\", \"preset\": 1, \"checks\": [\"no_script_errors\", \"final_hash\"], \"expected_hash\": %d}"
		% [REPLAY, M1_HASH]))
	var problem: String = ""
	var comfort: ComfortWiring = runner.main.get("comfort")
	if runner.exit_code != AcceptanceRunner.EXIT_PASS:
		problem = "exit %d: %s" % [runner.exit_code, "\n".join(runner.messages)]
	elif comfort.number != 1:
		problem = "the scene flew under preset %d, not 1" % comfort.number
	elif runner.reports[0].steps[0]["measurements"].get("script_errors") != 0:
		problem = "script errors counted: %s" % runner.reports[0].steps[0]["measurements"]
	_done(runner)
	return problem


func test_error_log_counts_only_script_errors() -> String:
	var error_log: AcceptanceErrorLog = AcceptanceErrorLog.new()
	var traces: Array[ScriptBacktrace] = []
	error_log._log_error("f", "res://x.gd", 3, "code", "boom", false, Logger.ERROR_TYPE_ERROR, traces)
	error_log._log_error("f", "res://x.gd", 4, "code", "boom", false, Logger.ERROR_TYPE_WARNING, traces)
	if error_log.count() != 0:
		return "an engine error or warning was counted"
	error_log._log_error("f", "res://x.gd", 5, "code", "boom", false, Logger.ERROR_TYPE_SCRIPT, traces)
	if error_log.count() != 1 or not error_log.errors()[0].contains("x.gd:5"):
		return "the script error was not counted with its place: %s" % error_log.errors()
	return ""


func test_replay_source_feeds_recorded_inputs_by_tick() -> String:
	var replay: Replay = Replay.load_file(REPLAY)
	var source: ReplayInputSource = ReplayInputSource.new(replay)
	var recorded: ShipInput = replay.frames[0][0]
	var given: ShipInput = source.next_input(0)
	if given == recorded or given.thrust_q != recorded.thrust_q:
		return "tick 0 is not a copy of the recorded input"
	source.next_input(replay.frames.size())
	if source.overrun_ticks != 1:
		return "a tick past the end was not counted"
	return ""
