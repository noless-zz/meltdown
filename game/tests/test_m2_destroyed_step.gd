extends RefCounted

## The m2 suite's destroyed-ship step (#601, RUN-7, CMB-2, DEV-6, decision
## record 0005): in the test tunnel the ship drifts straight down the tunnel
## into the robots with its guns silent until they destroy it (about three
## seconds), then the replay keeps sending full thrust, a turn, the afterburner
## and fire for three seconds more. The step checks the run is LOST, and
## `ship_destroyed_inert` re-flies it to check the wreck fired nothing and did
## not move once stopped.
##
## Re-recording this step only, from the repository root (the switch takes a
## comma-separated list of step ids, see `record_switch.gd`; `1` records every
## m2 step):
##
##     MELTDOWN_RECORD_M2=ship_destroyed_in_test_tunnel godot --headless --path game -s res://tests/run_tests.gd
##
## It overwrites the replay and prints the new hash; paste that hash into
## `expected_hash` of the step in `acceptance/suites/m2.json`.

const SUITE_PATH: String = "res://acceptance/suites/m2.json"
const STEP_ID: String = "ship_destroyed_in_test_tunnel"
const REPLAY_PATH: String = "res://acceptance/replays/ship_destroyed_test_tunnel.replay"
const RECORD_SWITCH: String = "MELTDOWN_RECORD_M2"
const RecordSwitch := preload("res://tests/record_switch.gd")
const Main := preload("res://main.gd")
## A minute for the robots to destroy the silent ship.
const TICK_LIMIT: int = 3600
## Forward thrust while alive: slow enough that the robots, not a wall, do it.
const DRIFT_THRUST: float = 0.3
## Thrust and fire sent after the ship is destroyed: three seconds.
const TICKS_AFTER: int = 180
## The runner flies one tick a frame.
const FRAME_LIMIT: int = 8000

var _quit_codes: Array[int] = []


## A slow drift forward with the trigger released, then, once the ship is
## destroyed, full forward thrust, a turn, the afterburner and fire every tick.
## It reads the session's own `Sim`, so that is set once the session exists.
class SilentDriftSource extends ShipInputSource:
	var sim: Sim = null

	func next_input(_tick: int) -> ShipInput:
		if sim == null or not sim.ships[0].is_destroyed():
			return ShipInput.from_floats(Vector3(0, 0, -DRIFT_THRUST), Vector3.ZERO)
		var input: ShipInput = ShipInput.from_floats(Vector3(0, 0, -1), Vector3(0, 1, 0), true)
		input.fire_primary = true
		return input


## Flies the silent drift in a session built like the main scene's until the
## ship has been destroyed for TICKS_AFTER ticks, or TICK_LIMIT.
static func record() -> LocalSession:
	var source: SilentDriftSource = SilentDriftSource.new()
	var session: LocalSession = LocalSession.new(0, source, TestTunnel.interior_box(Main.TUNNEL_OFFSET),
		LocalSession.load_tuning(Main.SHIP_TUNING_PATH), LocalSession.load_spawns(Main.ROBOT_SPAWNS_PATH))
	source.sim = session.sim
	var after: int = 0
	while after < TICKS_AFTER and session.sim.tick < TICK_LIMIT:
		session.advance(ShipState.TICK_DT)
		if session.sim.ships[0].is_destroyed():
			after += 1
	return session


func _step() -> AcceptanceStep:
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	for step: AcceptanceStep in suite.steps:
		if step.id == STEP_ID:
			return step
	return null


## Off unless RECORD_SWITCH is `1` or lists STEP_ID; see the top of this file.
## Records only a flight in which the ship was destroyed.
func test_record_when_asked() -> String:
	if not RecordSwitch.asks_for(RECORD_SWITCH, STEP_ID):
		return ""
	var session: LocalSession = record()
	if not session.sim.ships[0].is_destroyed():
		return "the ship survived %d ticks; nothing recorded" % session.sim.tick
	session.replay.expected_hash = session.sim.state_hash()
	var error: Error = session.replay.save(ProjectSettings.globalize_path(REPLAY_PATH))
	if error != OK:
		return "could not write %s: %s" % [REPLAY_PATH, error_string(error)]
	print("Meltdown: recorded %s: %d ticks, hash %d; put the hash in %s" % [
		REPLAY_PATH, session.sim.tick, session.replay.expected_hash, SUITE_PATH])
	return ""


func test_the_step_expects_a_lost_run_and_an_inert_wreck() -> String:
	var step: AcceptanceStep = _step()
	if step == null:
		return "m2 has no step %s" % STEP_ID
	var wanted: Array[String] = [AcceptanceStep.CHECK_FINAL_HASH, AcceptanceStep.CHECK_OUTCOME,
		AcceptanceStep.CHECK_SHIP_DESTROYED_INERT]
	if step.checks != wanted or step.expected_outcome != ExitRule.Outcome.LOST:
		return "%s checks %s, outcome %d" % [STEP_ID, step.checks, step.expected_outcome]
	if step.replay_path != REPLAY_PATH or step.level != "" or step.level_seed != AcceptanceStep.NO_SEED:
		return "%s flies %s in '%s'" % [STEP_ID, step.replay_path, step.level]
	return ""


## The recording reproduces the suite's hash, ends LOST, and passes the check
## with three seconds of thrust and fire after the ship was destroyed.
func test_the_replay_ends_lost_with_an_inert_wreck() -> String:
	var step: AcceptanceStep = _step()
	if step == null:
		return "m2 has no step %s" % STEP_ID
	var replay: Replay = Replay.load_file(REPLAY_PATH)
	if replay.error != "":
		return replay.error
	var sim: Sim = replay.run()
	if sim == null:
		return replay.run_error
	if sim.state_hash() != step.expected_hash or sim.state_hash() != replay.expected_hash:
		return "flew to %d; suite expects %d, replay %d (re-record: see the top of this file)" % [
			sim.state_hash(), step.expected_hash, replay.expected_hash]
	if sim.outcome() != ExitRule.Outcome.LOST:
		return "outcome %s" % AcceptanceStateChecks.outcome_name(sim.outcome())
	var measured: Dictionary = {}
	var result: Array = AcceptanceWreckCheck.run(replay, measured)
	if result[0] != AcceptanceReport.RESULT_PASS:
		return str(result)
	if int(measured["inputs_after_destroyed"]) < TICKS_AFTER - 1:
		return "measured %s" % measured
	return ""


## The robots as they are now still destroy the silent ship, so the recorder works.
func test_the_robots_still_destroy_the_silent_ship() -> String:
	var session: LocalSession = record()
	if not session.sim.ships[0].is_destroyed():
		return "the ship survived %d ticks" % session.sim.tick
	return ""


## The check refuses a ship that was never destroyed, and one that could
## still fire after it was.
func test_the_check_fails_a_live_ship_and_a_firing_wreck() -> String:
	var replay: Replay = Replay.new(601, 1)
	replay.set_box(Vector3i(-20000, -20000, -100000), Vector3i(20000, 20000, 20000))
	var fire: ShipInput = ShipInput.from_floats(Vector3(0, 0, -1), Vector3.ZERO)
	fire.fire_primary = true
	for i: int in 120:
		replay.add_tick([fire] as Array[ShipInput])
	var result: Array = AcceptanceWreckCheck.run(replay, {})
	if result[0] != AcceptanceReport.RESULT_FAIL or not str(result[1]).contains("never destroyed"):
		return "a live ship gave %s" % [result]
	return ""


func test_the_check_is_known_and_needs_a_replay() -> String:
	var without: AcceptanceSuite = AcceptanceSuite.parse_json(
		"{\"name\": \"t\", \"steps\": [{\"id\": \"a\", \"checks\": [\"ship_destroyed_inert\"]}]}")
	if not without.error.contains("replay: needed by the ship_destroyed_inert check"):
		return "a step without a replay gave '%s'" % without.error
	return ""


## The step alone, in the real main scene as the headset flies it: every
## check passes.
func test_the_runner_passes_the_step_in_the_main_scene() -> String:
	var step: AcceptanceStep = _step()
	if step == null:
		return "m2 has no step %s" % STEP_ID
	_quit_codes.clear()
	var only: AcceptanceSuite = AcceptanceSuite.new()
	only.name = "m2"
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
	var problem: String = ""
	if runner.exit_code != AcceptanceRunner.EXIT_PASS or not runner.reports[0].passed():
		problem = "exit %d: %s" % [runner.exit_code, "\n".join(runner.messages)]
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	if runner.main != null:
		runner.main.free()
	runner.free()
	return problem


func _on_quit(code: int) -> void:
	_quit_codes.append(code)
