extends RefCounted

## The `loop_replay` step field and the soak suite (#788, PRF-3, DEV-6): the
## field parses, a looping step cannot list final_hash, a looping source feeds
## a short replay's inputs again in order, `soak.json` loads, and the runner
## on a stand-in headset loops a replay through a short measured period.

const FakeXr := preload("res://tests/fake_initialized_xr.gd")
const FRAME_90: float = 1.0 / 90.0
const FRAME_LIMIT: int = 20000
const SHORT_REPLAY: String = "res://acceptance/replays/basic_flight.replay"
const BUDGET_KEYS: String = "\"settle_seconds\": 1, \"measure_seconds\": 9, " \
	+ "\"max_over_budget_share\": 0.01, \"budget_slack_ms\": 1"


func _step_json(extra: String, checks: String = "[\"frame_budget\"]") -> String:
	return "{\"name\": \"x\", \"steps\": [{\"id\": \"soak_step\", \"replay\": \"%s\", \"checks\": %s, %s, %s}]}" % [
		SHORT_REPLAY, checks, BUDGET_KEYS, extra]


func test_loop_replay_parses_and_defaults_to_false() -> String:
	var looping: AcceptanceSuite = AcceptanceSuite.parse_json(_step_json("\"loop_replay\": true"))
	if looping.error != "" or not looping.steps[0].loop_replay:
		return "loop_replay true gave '%s'" % looping.error
	var plain: AcceptanceSuite = AcceptanceSuite.parse_json(_step_json("\"loop_replay\": false"))
	if plain.error != "" or plain.steps[0].loop_replay:
		return "loop_replay false gave '%s'" % plain.error
	var unset: AcceptanceSuite = AcceptanceSuite.parse_json(
		"{\"name\": \"x\", \"steps\": [{\"id\": \"a\", \"checks\": [\"no_script_errors\"]}]}")
	if unset.error != "" or unset.steps[0].loop_replay:
		return "a step without loop_replay loops (%s)" % unset.error
	return ""


func test_loop_replay_with_final_hash_is_rejected_naming_the_step() -> String:
	var suite: AcceptanceSuite = AcceptanceSuite.parse_json(_step_json(
		"\"loop_replay\": true, \"expected_hash\": 1", "[\"frame_budget\", \"final_hash\"]"))
	if suite.error == "" or not suite.error.contains("soak_step") or not suite.error.contains("loop_replay"):
		return "gave '%s'" % suite.error
	return ""


func test_bad_loop_replay_values_are_rejected() -> String:
	var cases: Dictionary = {
		_step_json("\"loop_replay\": 1"): "loop_replay: must be true or false",
		_step_json("\"loop_replay\": true", "[\"frame_budget\", \"no_script_errors\"]").replace(
			"\"replay\": \"%s\", " % SHORT_REPLAY, ""): "lists no replay",
		"{\"name\": \"x\", \"steps\": [{\"id\": \"s\", \"replay\": \"%s\", \"checks\": [\"ship_alive\"], " % SHORT_REPLAY
			+ "\"loop_replay\": true}]}": "needs the frame_budget check",
	}
	for text: String in cases:
		var suite: AcceptanceSuite = AcceptanceSuite.parse_json(text)
		if suite.error == "" or not suite.error.contains(cases[text]):
			return "%s gave '%s', expected %s" % [text, suite.error, cases[text]]
	return ""


func test_a_looping_source_feeds_a_three_tick_replay_in_order() -> String:
	var replay: Replay = Replay.new(788)
	for index: int in 3:
		var inputs: Array[ShipInput] = [ShipInput.new(Vector3i(0, 0, -(index + 1) * 100))]
		replay.add_tick(inputs)
	var source: ReplayInputSource = ReplayInputSource.new(replay, true)
	var fed: Array[int] = []
	for tick: int in 10:
		fed.append(-source.next_input(tick).thrust_q.z / 100)
	if fed != [1, 2, 3, 1, 2, 3, 1, 2, 3, 1]:
		return "fed %s" % [fed]
	if source.overrun_ticks != 0:
		return "a looping source counted %d overrun ticks" % source.overrun_ticks
	var once: ReplayInputSource = ReplayInputSource.new(replay)
	once.next_input(3)
	if once.overrun_ticks != 1:
		return "a plain source still loops"
	return ""


func test_soak_suite_loads_and_names_its_step() -> String:
	var found: Array[AcceptanceSuite] = AcceptanceSuite.load_named("soak")
	if found.size() != 1 or found[0].error != "":
		return "soak gave %s" % (found[0].error if found.size() == 1 else str(found.size()))
	var steps: Array[AcceptanceStep] = found[0].steps
	if steps.size() != 1 or steps[0].id != "frame_budget_25min":
		return "soak steps: %d, first '%s'" % [steps.size(), steps[0].id]
	var step: AcceptanceStep = steps[0]
	if not step.loop_replay or step.measure_seconds != 1500.0 or step.settle_seconds != 5.0 \
			or step.max_over_budget_share != 0.01 or step.checks != [AcceptanceStep.CHECK_FRAME_BUDGET,
			AcceptanceStep.CHECK_NO_SCRIPT_ERRORS] or step.replay_path != "res://acceptance/replays/frame_budget_flight.replay":
		return "frame_budget_25min is not the step #788 names"
	return ""


## On a stand-in headset at 90 Hz the 600-tick replay is flown again until the
## 10 seconds (900 frames) are measured, with no ticks counted past its end.
func test_the_runner_loops_the_replay_while_measuring() -> String:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	(main.get("refresh_rate") as RefreshRate).in_use_hz = 90.0
	var suites: Array[AcceptanceSuite] = [AcceptanceSuite.parse_json(_step_json("\"loop_replay\": true"))]
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = func(_code: int) -> void: pass
	runner.on_headset = true
	runner.setup(main, suites, FakeXr.new())
	var frames: int = 0
	while not runner.finished and frames < FRAME_LIMIT:
		runner.process_frame(FRAME_90)
		frames += 1
	var problem: String = ""
	var session: LocalSession = main.get("session")
	if not runner.finished or runner.reports.is_empty():
		problem = "the runner did not finish: %s" % "\n".join(runner.messages)
	elif runner.reports[0].steps[0]["result"] != AcceptanceReport.RESULT_PASS:
		problem = "step %s: %s" % [runner.reports[0].steps[0]["result"], runner.reports[0].steps[0]["message"]]
	elif session.sim.tick < 850:
		problem = "flew %d ticks; the 600-tick replay did not loop" % session.sim.tick
	elif not main.is_processing():
		problem = "the scene was left with its processing switched off"
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	main.free()
	runner.free()
	return problem


## Off the headset nothing measures frames: the looping replay flies once and
## its frame_budget check is skipped, so CI and the simulator do not spend the soak on it.
func test_off_the_headset_the_replay_flies_once_and_is_skipped() -> String:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	var suites: Array[AcceptanceSuite] = AcceptanceSuite.load_named("soak")
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = func(_code: int) -> void: pass
	runner.setup(main, suites, null)
	var frames: int = 0
	while not runner.finished and frames < FRAME_LIMIT:
		runner.process_frame()
		frames += 1
	var problem: String = ""
	if not runner.finished or runner.reports.is_empty():
		problem = "the runner did not finish within %d frames" % FRAME_LIMIT
	else:
		var step: Dictionary = runner.reports[0].steps[0]
		var ticks: int = (main.get("session") as LocalSession).sim.tick
		# The step's no_script_errors check still runs; its frame_budget check is skipped.
		if step["result"] == AcceptanceReport.RESULT_FAIL \
				or not str(step["message"]).contains("frame_budget: not on the headset"):
			problem = "frame_budget_25min off the headset: %s: %s" % [step["result"], step["message"]]
		elif ticks != Replay.load_file("res://acceptance/replays/frame_budget_flight.replay").frames.size():
			problem = "flew %d ticks off the headset" % ticks
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	main.free()
	runner.free()
	return problem
