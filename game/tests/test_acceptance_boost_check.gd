extends RefCounted

## The m1 suite's `afterburner` step and its check (#775, FLT-2, FLT-1, ARC-2,
## DEV-6, decision record 0005, umbrella #153). In the empty test tunnel the
## ship rises off the floor, thrusts forward without the afterburner, resets to
## the start, rises again, thrusts forward with the afterburner held, then lets
## go and coasts for three seconds.
##
## The tunnel is 30 m long: at boost speed the ship crosses it in about a
## second, so the timings are shorter than the issue's "about 2 s, 3 s, 3 s".
## The plain run lasts 1.5 s and the boost about 0.7 s from a standing start,
## enough to pass the threshold; the reset between them gives the boost the
## tunnel's whole length. The coast may end with a gentle touch of the far wall.
##
## Re-recording this step only, from the repository root (see `record_switch.gd`):
##
##     MELTDOWN_RECORD_M1=afterburner godot --headless --path game -s res://tests/run_tests.gd
##
## It overwrites the replay and prints the new hash; paste that hash into
## `expected_hash` of the step in `acceptance/suites/m1.json`.

const SUITE_PATH: String = "res://acceptance/suites/m1.json"
const STEP_ID: String = "afterburner"
const REPLAY_PATH: String = "res://acceptance/replays/m1_afterburner.replay"
const RECORD_SWITCH: String = "MELTDOWN_RECORD_M1"
const RecordSwitch := preload("res://tests/record_switch.gd")
const Main := preload("res://main.gd")
const RUN_SEED: int = 775
const LIFT: Vector3 = Vector3(0, 0.25, 0)
const FORWARD: Vector3 = Vector3(0, 0, -1)
## [ticks, thrust, afterburner, reset]. Lifting off the floor as `flight_axes`
## does keeps the floor out of the measured runs.
const PLAN: Array[Array] = [
	[30, Vector3.ZERO, false, false],
	[10, LIFT, false, false],
	[90, Vector3.ZERO, false, false],
	[90, FORWARD, false, false],
	[60, Vector3.ZERO, false, true],
	[10, LIFT, false, false],
	[90, Vector3.ZERO, false, false],
	[44, FORWARD, true, false],
	[180, Vector3.ZERO, false, false],
]


## Flies PLAN in the empty test tunnel with the main scene's walls and the ship
## file's tuning, one tick per input.
static func record() -> LocalSession:
	var latest: LatestInputSource = LatestInputSource.new()
	var session: LocalSession = LocalSession.new(RUN_SEED, latest, TestTunnel.interior_box(Main.TUNNEL_OFFSET),
		LocalSession.load_tuning(Main.SHIP_TUNING_PATH))
	for entry: Array in PLAN:
		var input: ShipInput = ShipInput.from_floats(entry[1], Vector3.ZERO, entry[2])
		input.reset_to_start = entry[3]
		latest.set_input(input)
		for i: int in int(entry[0]):
			session.advance(ShipState.TICK_DT)
	return session


static func _tuning() -> ShipTuning:
	return LocalSession.load_tuning(Main.SHIP_TUNING_PATH)


static func _step() -> AcceptanceStep:
	for step: AcceptanceStep in AcceptanceSuite.load_file(SUITE_PATH).steps:
		if step.id == STEP_ID:
			return step
	return null


## Off unless RECORD_SWITCH is `1` or lists STEP_ID; see the top of this file.
func test_record_when_asked() -> String:
	if not RecordSwitch.asks_for(RECORD_SWITCH, STEP_ID):
		return ""
	var session: LocalSession = record()
	session.replay.expected_hash = session.sim.state_hash()
	var error: Error = session.replay.save(ProjectSettings.globalize_path(REPLAY_PATH))
	if error != OK:
		return "could not write %s: %s" % [REPLAY_PATH, error_string(error)]
	print("Meltdown: recorded %s: %d ticks, hash %d; put the hash in %s" % [
		REPLAY_PATH, session.sim.tick, session.replay.expected_hash, SUITE_PATH])
	return ""


## The recorder still produces the stored flight, so a re-record changes
## nothing unless the data did.
func test_the_recorder_reproduces_the_replay() -> String:
	var session: LocalSession = record()
	var replay: Replay = Replay.load_file(REPLAY_PATH)
	if replay.error != "":
		return replay.error
	if session.sim.state_hash() != replay.expected_hash or session.replay.frames.size() != replay.frames.size():
		return "the recorder flies %d ticks to %d; the replay %d ticks to %d" % [session.replay.frames.size(),
			session.sim.state_hash(), replay.frames.size(), replay.expected_hash]
	return ""


## Headless, the stored replay passes and reports both top speeds, the energy
## left and the seconds to settle.
func test_the_replay_passes_headless() -> String:
	var replay: Replay = Replay.load_file(REPLAY_PATH)
	if replay.error != "":
		return replay.error
	var measured: Dictionary = {}
	var result: Array = AcceptanceBoostCheck.run(replay, _tuning(), measured)
	if result[0] != AcceptanceReport.RESULT_PASS:
		return str(result)
	for key: String in ["plain_top_speed", "boosted_top_speed", "boost_threshold", "energy_end", "settle_seconds"]:
		if not measured.has(key):
			return "no %s in %s" % [key, measured]
	var tuning: ShipTuning = _tuning()
	if float(measured["boosted_top_speed"]) <= float(measured["plain_top_speed"]) \
			or float(measured["plain_top_speed"]) > tuning.max_speed * AcceptanceBoostCheck.SPEED_TOLERANCE \
			or float(measured["settle_seconds"]) <= 0.0:
		return "measured %s" % measured
	return ""


## The same flight with the afterburner never held fails on the boosted top speed.
func test_without_the_afterburner_it_fails() -> String:
	var replay: Replay = Replay.load_file(REPLAY_PATH)
	if replay.error != "":
		return replay.error
	for frame: Array in replay.frames:
		(frame[0] as ShipInput).afterburner = false
	var result: Array = AcceptanceBoostCheck.run(replay, _tuning(), {})
	if result[0] != AcceptanceReport.RESULT_FAIL or not str(result[1]).contains("boosted top speed"):
		return "no afterburner gave %s" % [result]
	return ""


## The limits follow the ship file: a lower `afterburner_max_speed` lowers the
## threshold, and the stored flight then runs past the new ceiling; a higher
## one raises the threshold past what the flight reached.
func test_the_ship_file_moves_the_threshold() -> String:
	var replay: Replay = Replay.load_file(REPLAY_PATH)
	if replay.error != "":
		return replay.error
	var tuning: ShipTuning = _tuning()
	var stock: float = AcceptanceBoostCheck.threshold(tuning)
	tuning.afterburner_max_speed = 25.0
	var lower: float = AcceptanceBoostCheck.threshold(tuning)
	if not is_equal_approx(lower, tuning.max_speed + 2.5) or lower >= stock:
		return "thresholds %.2f then %.2f" % [stock, lower]
	var result: Array = AcceptanceBoostCheck.run(replay, tuning, {})
	if result[0] != AcceptanceReport.RESULT_FAIL or not str(result[1]).contains("over the afterburner's 25.00"):
		return "a 25 m/s afterburner gave %s" % [result]
	tuning.afterburner_max_speed = 45.0
	var measured: Dictionary = {}
	result = AcceptanceBoostCheck.run(replay, tuning, measured)
	if result[0] != AcceptanceReport.RESULT_FAIL or not str(result[1]).contains("needs at least %.2f" % (tuning.max_speed + 12.5)):
		return "a 45 m/s afterburner gave %s" % [result]
	return ""


## A flight that ends while still boosting, or before the speed settles, fails.
func test_a_flight_that_never_settles_fails() -> String:
	var replay: Replay = Replay.new(RUN_SEED, 1)
	replay.set_box(Vector3i(-20000, -20000, -200000), Vector3i(20000, 20000, 20000))
	var boost: ShipInput = ShipInput.from_floats(FORWARD, Vector3.ZERO, true)
	for i: int in 60:
		replay.add_tick([boost] as Array[ShipInput])
	var result: Array = AcceptanceBoostCheck.run(replay, _tuning(), {})
	if result[0] != AcceptanceReport.RESULT_FAIL or not str(result[1]).contains("ends before"):
		return "a flight ending in the boost gave %s" % [result]
	return ""


## The suite still parses, lists the step with its checks and its replay's
## hash, and the check is refused on a step with no replay.
func test_the_step_is_listed() -> String:
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	if suite.error != "":
		return suite.error
	var step: AcceptanceStep = _step()
	if step == null:
		return "m1 has no step %s" % STEP_ID
	if step.checks != [AcceptanceStep.CHECK_AFTERBURNER, AcceptanceStep.CHECK_FINAL_HASH, AcceptanceStep.CHECK_SHIP_ALIVE]:
		return "%s checks %s" % [STEP_ID, step.checks]
	var replay: Replay = Replay.load_file(REPLAY_PATH)
	if step.replay_path != REPLAY_PATH or replay.error != "" or step.expected_hash != replay.expected_hash:
		return "%s flies %s expecting %d; replay %d %s" % [STEP_ID, step.replay_path, step.expected_hash,
			replay.expected_hash, replay.error]
	var sim: Sim = replay.run()
	if sim == null or sim.state_hash() != step.expected_hash:
		return "the replay flies to %s, the step expects %d" % [sim.state_hash() if sim != null else "nothing",
			step.expected_hash]
	var without: AcceptanceSuite = AcceptanceSuite.parse_json(
		"{\"name\": \"t\", \"steps\": [{\"id\": \"a\", \"checks\": [\"afterburner\"]}]}")
	if without.error == "":
		return "a step with the afterburner check and no replay was accepted"
	return ""
