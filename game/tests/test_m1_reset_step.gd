extends RefCounted

## The m1 suite's `reset_to_start` step and its `at_start` check (#776, FLT-1,
## CMF-8, ARC-2, DEV-6, decision record 0005, umbrella #153). In the empty test
## tunnel the ship rises off the floor, flies down the tunnel, bumps the side
## wall once, then yaws, pitches and rolls while it coasts, about four and a half
## seconds in all, then sends `reset_to_start` and idles for a second.
##
## The reset is a single tick: the view's hold (`ResetHold`, one second on the
## menu button) fades to black and then sends exactly one tick of
## `reset_to_start`, so one tick is what the hold needs in the simulation.
##
## Re-recording this step only, from the repository root (see `record_switch.gd`):
##
##     MELTDOWN_RECORD_M1=reset_to_start godot --headless --path game -s res://tests/run_tests.gd
##
## It overwrites the replay and prints the new hash; paste that hash into
## `expected_hash` of the step in `acceptance/suites/m1.json`.

const SUITE_PATH: String = "res://acceptance/suites/m1.json"
const STEP_ID: String = "reset_to_start"
const REPLAY_PATH: String = "res://acceptance/replays/m1_reset.replay"
const RECORD_SWITCH: String = "MELTDOWN_RECORD_M1"
const RecordSwitch := preload("res://tests/record_switch.gd")
const Main := preload("res://main.gd")
const RUN_SEED: int = 776
const LIFT: Vector3 = Vector3(0, 0.25, 0)
const FORWARD: Vector3 = Vector3(0, 0, -1)
const RIGHT: Vector3 = Vector3(1, 0, 0)
## [ticks, thrust, turn, reset]. Lifting off the floor as `flight_axes` does
## keeps the floor out of the flight. The tunnel's interior leaves the ship
## about a metre either side, so the turns come after the thrust, while the
## ship coasts: turning never changes where the ship is heading, only where it
## points. The short side thrust is the one bump; its bounce dies out before
## the far wall.
const PLAN: Array[Array] = [
	[10, LIFT, Vector3.ZERO, false],
	[30, Vector3.ZERO, Vector3.ZERO, false],
	[60, FORWARD * 0.5, Vector3.ZERO, false],
	[10, RIGHT, Vector3.ZERO, false],
	[40, Vector3.ZERO, Vector3.ZERO, false],
	[40, Vector3.ZERO, Vector3(0, 0.8, 0), false],
	[40, Vector3.ZERO, Vector3(0.6, 0, 0), false],
	[40, Vector3.ZERO, Vector3(0, 0, 1.0), false],
	[1, Vector3.ZERO, Vector3.ZERO, true],
	[60, Vector3.ZERO, Vector3.ZERO, false],
]


## Flies PLAN in the empty test tunnel with the main scene's walls and the ship
## file's tuning, one tick per input.
static func record(plan: Array[Array] = PLAN) -> LocalSession:
	var latest: LatestInputSource = LatestInputSource.new()
	var session: LocalSession = LocalSession.new(RUN_SEED, latest, TestTunnel.interior_box(Main.TUNNEL_OFFSET),
		LocalSession.load_tuning(Main.SHIP_TUNING_PATH))
	for entry: Array in plan:
		var input: ShipInput = ShipInput.from_floats(entry[1], entry[2], false)
		input.reset_to_start = entry[3]
		latest.set_input(input)
		for i: int in int(entry[0]):
			session.advance(ShipState.TICK_DT)
	return session


static func _step() -> AcceptanceStep:
	for step: AcceptanceStep in AcceptanceSuite.load_file(SUITE_PATH).steps:
		if step.id == STEP_ID:
			return step
	return null


## Wall contacts of ship 0 while `replay` flies.
static func _wall_contacts(replay: Replay) -> int:
	var frames: Array[Array] = replay.frames
	replay.frames = []
	var sim: Sim = replay.run()
	replay.frames = frames
	var contacts: int = 0
	for frame: Array in frames:
		var inputs: Array[ShipInput] = []
		inputs.assign(frame)
		sim.step(inputs)
		for event: SimEvent in sim.last_events:
			if event.kind == SimEvent.Kind.WALL_IMPACT and event.ship == 0:
				contacts += 1
	return contacts


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


## The flight is what the issue asks: about five seconds of flying, one wall
## bump, then the reset.
func test_the_flight_bumps_a_wall_once() -> String:
	var replay: Replay = Replay.load_file(REPLAY_PATH)
	if replay.error != "":
		return replay.error
	var contacts: int = _wall_contacts(replay)
	if contacts != 1:
		return "%d wall contacts, expected one" % contacts
	return ""


## Headless, the stored replay passes and reports the pose before and after.
func test_the_replay_passes_headless() -> String:
	var replay: Replay = Replay.load_file(REPLAY_PATH)
	if replay.error != "":
		return replay.error
	var measured: Dictionary = {}
	var result: Array = AcceptanceResetCheck.run(replay, measured)
	if result[0] != AcceptanceReport.RESULT_PASS:
		return str(result)
	for key: String in ["distance_before_reset", "angle_before_reset", "distance_after", "angle_after",
			"speed_after", "spin_after", "reset_ticks"]:
		if not measured.has(key):
			return "no %s in %s" % [key, measured]
	if float(measured["distance_before_reset"]) < 5.0 or float(measured["angle_before_reset"]) < 10.0:
		return "the ship was not far from the start before the reset: %s" % measured
	return ""


## The same flight with the reset ticks removed fails, naming the distance.
func test_without_the_reset_it_fails() -> String:
	var replay: Replay = Replay.load_file(REPLAY_PATH)
	if replay.error != "":
		return replay.error
	for frame: Array in replay.frames:
		(frame[0] as ShipInput).reset_to_start = false
	var result: Array = AcceptanceResetCheck.run(replay, {})
	if result[0] != AcceptanceReport.RESULT_FAIL or not str(result[1]).contains("m from the start"):
		return "no reset gave %s" % [result]
	return ""


## A ship reset and then still turning, or reset and moved off again, fails.
func test_turning_or_drifting_after_the_reset_fails() -> String:
	var turning: Array[Array] = [[30, FORWARD, Vector3.ZERO, false], [1, Vector3.ZERO, Vector3.ZERO, true],
		[1, Vector3.ZERO, Vector3(0, 0.05, 0), false]]
	var result: Array = AcceptanceResetCheck.run(record(turning).replay, {})
	if result[0] != AcceptanceReport.RESULT_FAIL or not str(result[1]).contains("turning"):
		return "turning after the reset gave %s" % [result]
	var drifting: Array[Array] = [[30, FORWARD, Vector3.ZERO, false], [1, Vector3.ZERO, Vector3.ZERO, true],
		[2, FORWARD, Vector3.ZERO, false]]
	result = AcceptanceResetCheck.run(record(drifting).replay, {})
	if result[0] != AcceptanceReport.RESULT_FAIL or not str(result[1]).contains("from the start"):
		return "moving off after the reset gave %s" % [result]
	return ""


## The suite still parses, lists the step with its checks, its replay's hash
## and a screenshot at the end, and the check is refused with no replay.
func test_the_step_is_listed() -> String:
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	if suite.error != "":
		return suite.error
	var step: AcceptanceStep = _step()
	if step == null:
		return "m1 has no step %s" % STEP_ID
	if step.checks != [AcceptanceStep.CHECK_AT_START, AcceptanceStep.CHECK_FINAL_HASH,
			AcceptanceStep.CHECK_NO_SCRIPT_ERRORS]:
		return "%s checks %s" % [STEP_ID, step.checks]
	if not step.screenshot_at_end:
		return "%s takes no screenshot at its end" % STEP_ID
	var replay: Replay = Replay.load_file(REPLAY_PATH)
	if step.replay_path != REPLAY_PATH or replay.error != "" or step.expected_hash != replay.expected_hash:
		return "%s flies %s expecting %d; replay %d %s" % [STEP_ID, step.replay_path, step.expected_hash,
			replay.expected_hash, replay.error]
	var sim: Sim = replay.run()
	if sim == null or sim.state_hash() != step.expected_hash:
		return "the replay flies to %s, the step expects %d" % [sim.state_hash() if sim != null else "nothing",
			step.expected_hash]
	var without: AcceptanceSuite = AcceptanceSuite.parse_json(
		"{\"name\": \"t\", \"steps\": [{\"id\": \"a\", \"checks\": [\"at_start\"]}]}")
	if without.error == "":
		return "a step with the at_start check and no replay was accepted"
	return ""
