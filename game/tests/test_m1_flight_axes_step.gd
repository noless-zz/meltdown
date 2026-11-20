extends RefCounted

## The m1 suite's `flight_axes` step (#686, FLT-1, FLT-3, DEV-6, decision
## record 0005, umbrella #153): in the empty test tunnel the ship flies every
## axis both ways, boosts into both end walls and holds the reset
## (`m1_flight_axes_source.gd`). The step checks the final hash, that the ship
## survived, that no script error was logged, and `wall_bounced`.
##
## Re-recording this step only, from the repository root (the switch takes a
## comma-separated list of step ids, see `record_switch.gd`; `1` records every
## m1 step this switch covers):
##
##     MELTDOWN_RECORD_M1=flight_axes godot --headless --path game -s res://tests/run_tests.gd
##
## It overwrites the replay and prints the new hash; paste that hash into
## `expected_hash` of the step in `acceptance/suites/m1.json`.

const SUITE_PATH: String = "res://acceptance/suites/m1.json"
const STEP_ID: String = "flight_axes"
const REPLAY_PATH: String = "res://acceptance/replays/m1_flight_axes.replay"
const RECORD_SWITCH: String = "MELTDOWN_RECORD_M1"
const RecordSwitch := preload("res://tests/record_switch.gd")
const FlightAxesSource := preload("res://tests/m1_flight_axes_source.gd")
const Main := preload("res://main.gd")
## The issue asks for about 30 to 40 seconds of flight.
const MIN_TICKS: int = 1800
const MAX_TICKS: int = 2400
## The runner flies one tick a frame.
const FRAME_LIMIT: int = 6000

var _quit_codes: Array[int] = []


## Flies the scripted pilot in the empty test tunnel, with the main scene's
## walls and ship tuning and no robots, until its plan ends.
static func record() -> Array:
	var source: FlightAxesSource = FlightAxesSource.new()
	var session: LocalSession = LocalSession.new(686, source, TestTunnel.interior_box(Main.TUNNEL_OFFSET),
		LocalSession.load_tuning(Main.SHIP_TUNING_PATH))
	source.sim = session.sim
	while not source.done() and session.sim.tick < MAX_TICKS * 2:
		session.advance(ShipState.TICK_DT)
	return [session, source]


func _step() -> AcceptanceStep:
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	for step: AcceptanceStep in suite.steps:
		if step.id == STEP_ID:
			return step
	return null


## Off unless RECORD_SWITCH is `1` or lists STEP_ID; see the top of this file.
func test_record_when_asked() -> String:
	if not RecordSwitch.asks_for(RECORD_SWITCH, STEP_ID):
		return ""
	var session: LocalSession = record()[0]
	session.replay.expected_hash = session.sim.state_hash()
	var error: Error = session.replay.save(ProjectSettings.globalize_path(REPLAY_PATH))
	if error != OK:
		return "could not write %s: %s" % [REPLAY_PATH, error_string(error)]
	print("Meltdown: recorded %s: %d ticks, hash %d; put the hash in %s" % [
		REPLAY_PATH, session.sim.tick, session.replay.expected_hash, SUITE_PATH])
	return ""


func test_the_step_names_its_replay_and_checks() -> String:
	var step: AcceptanceStep = _step()
	if step == null:
		return "m1 has no step %s" % STEP_ID
	var wanted: Array[String] = [AcceptanceStep.CHECK_FINAL_HASH, AcceptanceStep.CHECK_SHIP_ALIVE,
		AcceptanceStep.CHECK_WALL_BOUNCED, AcceptanceStep.CHECK_NO_SCRIPT_ERRORS]
	if step.checks != wanted:
		return "%s checks %s" % [STEP_ID, step.checks]
	if step.replay_path != REPLAY_PATH or step.level != "" or step.level_seed != AcceptanceStep.NO_SEED:
		return "%s flies %s in '%s'" % [STEP_ID, step.replay_path, step.level]
	return ""


## The steps that were there before keep their place and values.
func test_the_earlier_m1_steps_are_unchanged() -> String:
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	if suite.error != "":
		return suite.error
	var ids: Array[String] = []
	for step: AcceptanceStep in suite.steps:
		ids.append(step.id)
	if ids != ["basic_flight", "refresh_rate", "frame_budget", STEP_ID]:
		return "m1 steps %s" % [ids]
	if suite.steps[0].expected_hash != 861662111 or suite.steps[0].checks != [AcceptanceStep.CHECK_FINAL_HASH]:
		return "basic_flight changed"
	return ""


## The stored flight reproduces the suite's hash, lasts 30 to 40 seconds, flies
## every axis both ways, boosts, and passes `wall_bounced` with damage taken.
func test_the_replay_flies_every_axis_and_bounces() -> String:
	var step: AcceptanceStep = _step()
	if step == null:
		return "m1 has no step %s" % STEP_ID
	var replay: Replay = Replay.load_file(REPLAY_PATH)
	if replay.error != "":
		return replay.error
	if replay.frames.size() < MIN_TICKS or replay.frames.size() > MAX_TICKS:
		return "%d ticks, expected %d to %d" % [replay.frames.size(), MIN_TICKS, MAX_TICKS]
	if not replay.robots.is_empty() or replay.walls() == null:
		return "not the empty test tunnel: %d robots" % replay.robots.size()
	var sim: Sim = replay.run()
	if sim == null:
		return replay.run_error
	if sim.state_hash() != step.expected_hash or sim.state_hash() != replay.expected_hash:
		return "flew to %d; suite expects %d, replay %d (re-record: see the top of this file)" % [
			sim.state_hash(), step.expected_hash, replay.expected_hash]
	var problem: String = _covers_every_axis(replay)
	if problem != "":
		return problem
	var measured: Dictionary = {}
	var result: Array = AcceptanceWallCheck.run(replay, measured)
	if result[0] != AcceptanceReport.RESULT_PASS:
		return str(result)
	if float(measured["fastest_impact"]) <= LocalSession.load_tuning(Main.SHIP_TUNING_PATH).max_speed:
		return "no wall was hit faster than normal flight: %s" % measured
	return ""


## Every thrust and turn axis is used both ways, the afterburner for about two
## seconds, and the reset for a second.
func _covers_every_axis(replay: Replay) -> String:
	var plus: Array[bool] = [false, false, false, false, false, false]
	var minus: Array[bool] = [false, false, false, false, false, false]
	var boost: int = 0
	var reset: int = 0
	for frame: Array in replay.frames:
		var input: ShipInput = frame[0]
		for axis: int in 3:
			plus[axis] = plus[axis] or input.thrust_q[axis] > 0
			minus[axis] = minus[axis] or input.thrust_q[axis] < 0
			plus[axis + 3] = plus[axis + 3] or input.turn_q[axis] > 0
			minus[axis + 3] = minus[axis + 3] or input.turn_q[axis] < 0
		boost += 1 if input.afterburner else 0
		reset += 1 if input.reset_to_start else 0
	if plus.has(false) or minus.has(false):
		return "an axis is not flown both ways: plus %s, minus %s" % [plus, minus]
	if boost < 90 or boost > 180:
		return "boost held %d ticks, expected about two seconds" % boost
	if reset != 60:
		return "reset held %d ticks, expected 60" % reset
	return ""


## The recorder still produces the stored flight, so a re-record changes
## nothing unless the data did.
func test_the_recorder_reproduces_the_replay() -> String:
	var recorded: Array = record()
	var session: LocalSession = recorded[0]
	var replay: Replay = Replay.load_file(REPLAY_PATH)
	if replay.error != "":
		return replay.error
	if session.sim.state_hash() != replay.expected_hash or session.replay.frames.size() != replay.frames.size():
		return "the recorder flies %d ticks to %d; the replay %d ticks to %d" % [session.replay.frames.size(),
			session.sim.state_hash(), replay.frames.size(), replay.expected_hash]
	return ""


## The check refuses a flight that never touches a wall, one whose only hit is
## too gentle to cost anything, and one that comes to rest against a wall.
func test_the_check_fails_without_a_wall_or_without_damage() -> String:
	var replay: Replay = Replay.new(686, 1)
	replay.set_box(Vector3i(-20000, -20000, -100000), Vector3i(20000, 20000, 20000))
	var slow: ShipInput = ShipInput.from_floats(Vector3(0, 0, -0.2), Vector3.ZERO)
	for i: int in 60:
		replay.add_tick([slow] as Array[ShipInput])
	var result: Array = AcceptanceWallCheck.run(replay, {})
	if result[0] != AcceptanceReport.RESULT_FAIL or not str(result[1]).contains("never touched a wall"):
		return "no wall gave %s" % [result]
	# A short push, then a coast into a near wall, below the speed at which a hit hurts.
	var near: Replay = Replay.new(686, 1)
	near.set_box(Vector3i(-2000, -2000, -2000), Vector3i(2000, 2000, 2000))
	var coast: ShipInput = ShipInput.new()
	for i: int in 120:
		near.add_tick([slow if i < 30 else coast] as Array[ShipInput])
	result = AcceptanceWallCheck.run(near, {})
	if result[0] != AcceptanceReport.RESULT_FAIL or not str(result[1]).contains("cost neither hull nor shield"):
		return "a harmless bump gave %s" % [result]
	# Creeping thrust held into the wall: the ship comes to rest against it.
	var pressed: Replay = Replay.new(686, 1)
	pressed.set_box(Vector3i(-2000, -2000, -3000), Vector3i(2000, 2000, 2000))
	for i: int in 120:
		pressed.add_tick([slow] as Array[ShipInput])
	result = AcceptanceWallCheck.run(pressed, {})
	if result[0] != AcceptanceReport.RESULT_FAIL or not str(result[1]).contains("the ship stopped"):
		return "a ship at rest against a wall gave %s" % [result]
	return ""


func test_the_check_is_known_and_needs_a_replay() -> String:
	var without: AcceptanceSuite = AcceptanceSuite.parse_json(
		"{\"name\": \"t\", \"steps\": [{\"id\": \"a\", \"checks\": [\"wall_bounced\"]}]}")
	if not without.error.contains("replay: needed by the wall_bounced check"):
		return "a step without a replay gave '%s'" % without.error
	var typo: AcceptanceSuite = AcceptanceSuite.parse_json(
		"{\"name\": \"t\", \"steps\": [{\"id\": \"a\", \"replay\": \"x\", \"checks\": [\"wall_bounce\"]}]}")
	return "" if typo.error != "" else "a misspelt check was accepted"


## The step alone, in the real main scene as the headset flies it: every
## check passes; with its expected hash changed, the step fails.
func test_the_runner_passes_the_step_and_fails_a_wrong_hash() -> String:
	var step: AcceptanceStep = _step()
	if step == null:
		return "m1 has no step %s" % STEP_ID
	var passed: Array = _run_step(step)
	if passed[0] != AcceptanceRunner.EXIT_PASS:
		return "exit %d: %s" % passed
	var wrong: AcceptanceStep = _step()
	wrong.expected_hash += 1
	var failed: Array = _run_step(wrong)
	if failed[0] == AcceptanceRunner.EXIT_PASS or not str(failed[1]).contains("final hash"):
		return "a wrong hash gave exit %d: %s" % failed
	return ""


## [exit code, messages] of the runner flying `step` alone in the main scene.
func _run_step(step: AcceptanceStep) -> Array:
	_quit_codes.clear()
	var only: AcceptanceSuite = AcceptanceSuite.new()
	only.name = "m1"
	only.steps.append(step)
	var suites: Array[AcceptanceSuite] = [only]
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = _on_quit
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	runner.setup(scene.instantiate(), suites, null)
	var frames: int = 0
	while not runner.finished and frames < FRAME_LIMIT:
		runner.process_frame()
		frames += 1
	var code: int = runner.exit_code if runner.finished else -1
	if code == AcceptanceRunner.EXIT_PASS and not runner.reports[0].passed():
		code = -2
	var text: String = "\n".join(runner.messages)
	for report: AcceptanceReport in runner.reports:
		for entry: Dictionary in report.steps:
			text += "\n%s: %s" % [entry["result"], entry["message"]]
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	if runner.main != null:
		runner.main.free()
	runner.free()
	return [code, text]


func _on_quit(code: int) -> void:
	_quit_codes.append(code)
