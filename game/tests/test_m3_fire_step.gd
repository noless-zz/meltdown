extends RefCounted

## The m3 suite's fire step (#517, RUN-4, CMB-2, DEV-6, decision record 0005):
## the bot pilot's escape from a generated seed on which fire (#480, #497)
## burnt the ship on the way out. Like `bot_generated_door_escape` the replay
## holds only inputs and the level is built from the seed each run; the seed
## and hashes live only in `m3.json`.
##
## Re-recording uses the same one command as the other m3 steps, from the
## repository root:
##
##     MELTDOWN_RECORD_M3=1 godot --headless --path game -s res://tests/run_tests.gd
##
## It keeps the step's seed while the bot still escapes it having been burnt,
## otherwise picks the lowest seed in 1..300 that does (`m3_seed_pick.gd`).

const STEP_ID: String = "bot_generated_fire_escape"
const REPLAY_PATH: String = "res://acceptance/replays/bot_generated_fire_escape.replay"
const RECORD_SWITCH: String = "MELTDOWN_RECORD_M3"
## The escape takes a few thousand ticks; the runner flies one per frame.
const FRAME_LIMIT: int = 40000
const SeedPick := preload("res://tests/m3_seed_pick.gd")
## Written above the recording; `Replay` skips lines starting with `#`.
const REPLAY_HEADER: String = """# The bot pilot's escape from the m3 suite's fire seed (#517): the reactor
# destroyed, the ship burnt by fire at least once, out through the entrance.
# Inputs only: the m3 suite builds the level from the seed in m3.json and the
# shipped data files. Re-record from the repository root; the recorder picks the
# seed and writes the seed and hashes into m3.json itself:
#     MELTDOWN_RECORD_M3=1 godot --headless --path game -s res://tests/run_tests.gd
"""
const REACTOR_JSON: String = '{"position": [0, 0, -30], "radius": 2, "hull": 40, "meltdown_seconds": 60}'
const PULSE: String = "res://data/weapons/pulse_cannon.json"
## Fire across the tunnel the ship flies back through, as in `test_meltdown_fire.gd`.
const FIRE_ON_THE_PATH: String = '[{"position": [0, 0, -8], "size": [8, 8, 2],' \
	+ ' "after_seconds": 0.1, "kind": "fire", "damage_per_second": 40}]'
## The same fire moved beside the path: the ship's centre never enters it.
const FIRE_BESIDE_THE_PATH: String = '[{"position": [7, 0, -8], "size": [4, 4, 2],' \
	+ ' "after_seconds": 0.1, "kind": "fire", "damage_per_second": 40}]'

var _quit_codes: Array[int] = []


## Off unless RECORD_SWITCH is set; see the top of this file.
func test_record_when_asked() -> String:
	if OS.get_environment(RECORD_SWITCH) != "1":
		return ""
	return SeedPick.record(STEP_ID, REPLAY_PATH, REPLAY_HEADER, SeedPick.NEED_BURN)


func test_the_step_names_its_seed_and_checks() -> String:
	var found: AcceptanceStep = SeedPick.find_step(STEP_ID)
	if found == null:
		return "m3 has no step %s" % STEP_ID
	if found.level_seed == AcceptanceStep.NO_SEED or found.level != "" or found.replay_path != REPLAY_PATH:
		return "the step flies %s on seed %d, level '%s'" % [found.replay_path, found.level_seed, found.level]
	for check: String in [AcceptanceStep.CHECK_FINAL_HASH, AcceptanceStep.CHECK_LEVEL_HASH,
			AcceptanceStep.CHECK_OUTCOME, AcceptanceStep.CHECK_FIRE_BURNED]:
		if not found.has_check(check):
			return "%s does not check %s: %s" % [STEP_ID, check, found.checks]
	if found.expected_outcome != ExitRule.Outcome.ESCAPED:
		return "%s expects outcome %d" % [STEP_ID, found.expected_outcome]
	if found.level_seed < SeedPick.SEARCH_FIRST or found.level_seed > SeedPick.SEARCH_LAST:
		return "%s flies seed %d, outside %d..%d" % [STEP_ID, found.level_seed, SeedPick.SEARCH_FIRST,
			SeedPick.SEARCH_LAST]
	return ""


## The level must come from the seed, as for the other seed steps.
func test_the_replay_holds_only_inputs() -> String:
	var replay: Replay = Replay.load_file(REPLAY_PATH)
	if replay.error != "":
		return replay.error
	if replay.box_mins_mm.size() > 0 or replay.reactor != null or not replay.robots.is_empty() \
			or replay.debris != null or replay.tuning != null or replay.loadout != null \
			or not replay.parts.is_empty() or not replay.start_positions_mm.is_empty():
		return "%s carries more than its inputs" % REPLAY_PATH
	var found: AcceptanceStep = SeedPick.find_step(STEP_ID)
	if replay.ship_count != 1 or replay.frames.is_empty() or replay.expected_hash != found.expected_hash:
		return "%s: %d ships, %d ticks, hash %d" % [REPLAY_PATH, replay.ship_count,
			replay.frames.size(), replay.expected_hash]
	return ""


## The step alone, as the headset flies it: every check passes, the bot
## escapes having been burnt.
func test_the_runner_passes_the_step() -> String:
	var runner: AcceptanceRunner = _run()
	var problem: String = ""
	if runner.exit_code != AcceptanceRunner.EXIT_PASS or not runner.reports[0].passed():
		problem = "exit %d: %s" % [runner.exit_code, "\n".join(runner.messages)]
	else:
		var measured: Dictionary = runner.reports[0].steps[0]["measurements"]
		if measured.get("outcome") != "ESCAPED" or int(measured.get("burnt_ticks", 0)) < 1:
			problem = "measured %s" % measured
	_done(runner)
	return problem


## A hand-built level: the ship shoots the reactor, then flies back to the
## start through fire that fell across the tunnel. It is burnt, so it passes.
func test_a_flight_through_fire_passes() -> String:
	var session: LocalSession = _flown(FIRE_ON_THE_PATH)
	var measured: Dictionary = {}
	var result: Array = AcceptanceStateChecks.run(AcceptanceStep.CHECK_FIRE_BURNED, _step(), session,
		true, measured)
	if not session.sim.reactor.destroyed or not session.sim.debris.is_burning(0):
		return "the hand-built flight never lit the fire"
	if result[0] != AcceptanceReport.RESULT_PASS or int(measured.get("burnt_ticks", 0)) < 1 \
			or measured.get("fires") != 1:
		return "a flight through fire gave %s, %s" % [result, measured]
	return ""


## The same flight with the fire beside the path: it burns, but never the
## ship, so the check fails naming the step.
func test_a_flight_beside_fire_fails_naming_the_step() -> String:
	var session: LocalSession = _flown(FIRE_BESIDE_THE_PATH)
	if not session.sim.debris.is_burning(0):
		return "the fire beside the path never lit"
	var measured: Dictionary = {}
	var result: Array = FireBurnCheck.run(STEP_ID, session, measured)
	if result[0] != AcceptanceReport.RESULT_FAIL or not str(result[1]).contains(STEP_ID) \
			or measured.get("burnt_ticks") != 0 or measured.get("fires") != 1:
		return "a flight beside fire gave %s, %s" % [result, measured]
	return ""


## The check flies the recording again; if that ends anywhere but where the
## live run did, it cannot vouch for the live flight and fails.
func test_a_live_run_that_differs_from_its_recording_fails() -> String:
	var session: LocalSession = _flown(FIRE_ON_THE_PATH)
	session.sim.ships[0].hull -= 1.0
	var result: Array = FireBurnCheck.run(STEP_ID, session, {})
	if result[0] != AcceptanceReport.RESULT_FAIL or not str(result[1]).contains("flying the recording again"):
		return "a doctored live run gave %s" % [result]
	return ""


## A step without a replay cannot name the check.
func test_the_check_is_known_and_needs_a_replay() -> String:
	var without: AcceptanceSuite = AcceptanceSuite.parse_json(
		"{\"name\": \"t\", \"steps\": [{\"id\": \"a\", \"checks\": [\"fire_burned\"]}]}")
	if not without.error.contains("replay: needed by the fire_burned check"):
		return "a step without a replay gave '%s'" % without.error
	var with: AcceptanceSuite = AcceptanceSuite.parse_json(
		"{\"name\": \"t\", \"steps\": [{\"id\": \"a\", \"replay\": \"r\", \"checks\": [\"fire_burned\"]}]}")
	if with.error != "":
		return "a step with a replay gave '%s'" % with.error
	return ""


## The live session of the hand-built flight with `debris_text`, flown tick by
## tick as the runner flies a step.
func _flown(debris_text: String) -> LocalSession:
	var replay: Replay = Replay.new(517, 1)
	replay.set_box(Vector3i(-10000, -10000, -100000), Vector3i(10000, 10000, 10000))
	replay.reactor = ReactorState.parse_json(REACTOR_JSON)
	var loadout: ShipLoadout = ShipLoadout.new()
	loadout.set_slot("primary", 0, "pulse_cannon",
		WeaponDef.parse_json(FileAccess.get_file_as_string(PULSE)))
	replay.loadout = loadout
	replay.debris = MeltdownDebris.parse_json(debris_text)
	var attack: ShipInput = ShipInput.from_floats(Vector3(0, 0, -1), Vector3.ZERO)
	attack.fire_primary = true
	for i: int in 90:
		replay.add_tick([attack])
	for i: int in 180:
		replay.add_tick([ShipInput.from_floats(Vector3(0, 0, 1), Vector3.ZERO)])
	var source: ReplayInputSource = ReplayInputSource.new(replay)
	var session: LocalSession = source.new_session()
	while session.sim.tick < source.tick_count():
		session.advance(ShipState.TICK_DT)
	return session


func _step() -> AcceptanceStep:
	var step: AcceptanceStep = AcceptanceStep.new()
	step.id = STEP_ID
	step.checks = [AcceptanceStep.CHECK_FIRE_BURNED]
	return step


func _on_quit(code: int) -> void:
	_quit_codes.append(code)


## Flies a suite holding only this step.
func _run() -> AcceptanceRunner:
	_quit_codes.clear()
	var only: AcceptanceSuite = AcceptanceSuite.new()
	only.name = "m3"
	only.steps.append(SeedPick.find_step(STEP_ID))
	var suites: Array[AcceptanceSuite] = [only]
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = _on_quit
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	runner.setup(scene.instantiate(), suites, null)
	var frames: int = 0
	while not runner.finished and frames < FRAME_LIMIT:
		runner.process_frame()
		frames += 1
	return runner


func _done(runner: AcceptanceRunner) -> void:
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	if runner.main != null:
		runner.main.free()
	runner.free()
