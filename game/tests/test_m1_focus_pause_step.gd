extends RefCounted

## The m1 suite's `focus_pause` step (#804, PLT-7, CMF-8, ARC-2): halfway
## through `basic_flight` the headset comes off for three seconds, through the
## scene's own focus calls. Nothing may move while it is off, the flight goes
## on from the next tick, and it ends on `basic_flight`'s own hash.

const SUITE_PATH: String = "res://acceptance/suites/m1.json"
const STEP_ID: String = "focus_pause"
const REPLAY_PATH: String = "res://acceptance/replays/basic_flight.replay"
const FRAME_LIMIT: int = 3000


static func _find(id: String) -> AcceptanceStep:
	for step: AcceptanceStep in AcceptanceSuite.load_file(SUITE_PATH).steps:
		if step.id == id:
			return step
	return null


## A one-step suite flying the basic flight, with `extra` JSON fields added.
static func _suite_text(checks: String, extra: String, replay: bool = true) -> String:
	var replay_field: String = "\"replay\": \"%s\", " % REPLAY_PATH if replay else ""
	return "{\"name\": \"x\", \"steps\": [{\"id\": \"p\", %s\"checks\": %s%s}]}" % [replay_field, checks, extra]


func test_the_step_is_listed_with_its_fields() -> String:
	var step: AcceptanceStep = _find(STEP_ID)
	if step == null:
		return "m1 has no step %s" % STEP_ID
	var wanted: Array[String] = [AcceptanceStep.CHECK_HELD_WHILE_PAUSED, AcceptanceStep.CHECK_FINAL_HASH,
		AcceptanceStep.CHECK_NO_SCRIPT_ERRORS]
	if step.replay_path != REPLAY_PATH or step.checks != wanted:
		return "%s flies %s with %s" % [STEP_ID, step.replay_path, step.checks]
	var replay: Replay = Replay.load_file(REPLAY_PATH)
	var half: int = replay.frames.size() / 2
	if absi(step.pause_at_tick - half) > replay.frames.size() / 10 or step.pause_seconds != 3.0:
		return "pauses at %d for %s s; the replay flies %d ticks" % [step.pause_at_tick, step.pause_seconds,
			replay.frames.size()]
	var basic: AcceptanceStep = _find("basic_flight")
	if basic == null or step.expected_hash != basic.expected_hash or step.expected_hash != replay.expected_hash:
		return "%s expects %d, not basic_flight's" % [STEP_ID, step.expected_hash]
	for key: String in [AcceptancePauseCheck.KEY_TICK, AcceptancePauseCheck.KEY_SECONDS]:
		if not AcceptanceStepParser.STEP_KEYS.has(key):
			return "the step parser does not know %s" % key
	return ""


## Each bad pause is a suite error naming the field at fault.
func test_bad_pause_fields_are_refused_naming_the_field() -> String:
	var held: String = "[\"held_while_paused\"]"
	var cases: Array[Array] = [
		[_suite_text(held, ", \"pause_at_tick\": 10, \"pause_seconds\": 3", false), "steps[0].pause_at_tick"],
		[_suite_text(held, ", \"pause_at_tick\": 999999, \"pause_seconds\": 3"), "past the replay"],
		[_suite_text(held, ", \"pause_at_tick\": 10"), "steps[0].pause_seconds"],
		[_suite_text(held, ", \"pause_seconds\": 3"), "steps[0].pause_at_tick"],
		[_suite_text(held, ", \"pause_at_tick\": -1, \"pause_seconds\": 3"), "steps[0].pause_at_tick"],
		[_suite_text(held, ", \"pause_at_tick\": 10, \"pause_seconds\": 0"), "steps[0].pause_seconds"],
		[_suite_text(held, ""), "steps[0].pause_at_tick: needed"],
		[_suite_text("[\"final_hash\"]", ", \"expected_hash\": 1, \"pause_at_tick\": 10, \"pause_seconds\": 3"),
			"steps[0].pause_at_tick: only used by the held_while_paused check"],
	]
	for case: Array in cases:
		var suite: AcceptanceSuite = AcceptanceSuite.parse_json(case[0])
		if suite.error.find(case[1]) < 0:
			return "%s gave '%s', wanted '%s'" % [case[0], suite.error, case[1]]
	var good: AcceptanceSuite = AcceptanceSuite.parse_json(
		_suite_text(held, ", \"pause_at_tick\": 10, \"pause_seconds\": 1.5"))
	if good.error != "" or good.steps[0].pause_at_tick != 10 or good.steps[0].pause_seconds != 1.5:
		return "a good pause: %s" % good.error
	return ""


## The m1 step passes in the main scene, holding three seconds of frames.
func test_the_step_passes_headless() -> String:
	var step: AcceptanceStep = _find(STEP_ID)
	if step == null:
		return "m1 has no step %s" % STEP_ID
	var only: AcceptanceSuite = AcceptanceSuite.new()
	only.name = "m1"
	only.steps.append(step)
	var suites: Array[AcceptanceSuite] = [only]
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = func(_code: int) -> void: pass
	runner.setup((load("res://main.tscn") as PackedScene).instantiate(), suites, null)
	var frames: int = 0
	while not runner.finished and frames < FRAME_LIMIT:
		runner.process_frame()
		frames += 1
	var text: String = "\n".join(runner.messages)
	var measured: Dictionary = {}
	for report: AcceptanceReport in runner.reports:
		for entry: Dictionary in report.steps:
			measured = entry["measurements"]
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	var code: int = runner.exit_code
	runner.main.free()
	runner.free()
	if code != AcceptanceRunner.EXIT_PASS:
		return "exit %d: %s" % [code, text]
	if int(measured.get("paused_frames", 0)) != 180 or int(measured.get("pause_tick", -1)) != step.pause_at_tick \
			or int(measured.get("resume_tick", -1)) != step.pause_at_tick + 1:
		return "measured %s" % measured
	return ""


## A pause that does not hold (the session keeps flying) fails naming the tick.
func test_a_broken_pause_fails_naming_the_tick() -> String:
	var result: Array = _fly(true)
	if result[0] != AcceptanceReport.RESULT_FAIL:
		return "a broken pause passed: %s" % result[1]
	if str(result[1]).find("paused at tick 300") < 0 or str(result[1]).find("advanced to tick 301") < 0:
		return "the failure does not name the tick: %s" % result[1]
	var held: Array = _fly(false)
	if held[0] != AcceptanceReport.RESULT_PASS:
		return "the same flight held properly failed: %s" % held[1]
	return ""


## [result, message] of the pause check over the basic flight flown frame by
## frame in the main scene, pausing at tick 300 for one second; `broken`
## clears the session's pause every frame, as a pause that never took would.
func _fly(broken: bool) -> Array:
	var suite: AcceptanceSuite = AcceptanceSuite.parse_json(_suite_text("[\"held_while_paused\"]",
		", \"pause_at_tick\": 300, \"pause_seconds\": 1"))
	if suite.error != "":
		return [AcceptanceReport.RESULT_FAIL, suite.error]
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	var source: ReplayInputSource = ReplayInputSource.new(Replay.load_file(REPLAY_PATH))
	main.set("session", source.new_session())
	var pause: AcceptancePauseCheck = AcceptancePauseCheck.new(suite.steps[0])
	var frames: int = 0
	while (main.get("session") as LocalSession).sim.tick < source.tick_count() and frames < FRAME_LIMIT:
		pause.before_frame(main, (main.get("session") as LocalSession).sim.tick)
		if broken:
			(main.get("session") as LocalSession).paused = false
		main.call("advance_frame", ShipState.TICK_DT)
		pause.after_frame(main)
		frames += 1
	var result: Array = pause.judge({})
	main.free()
	return result
