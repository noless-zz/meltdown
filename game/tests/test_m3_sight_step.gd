extends RefCounted

## The m3 suite's line-of-sight step (#615, CMB-2, CMB-3, GEN-2, DEV-6,
## decision record 0005): the bot pilot's flight on generated seed 31, where the
## owner was hit by robots behind corridor walls. Before #615 the same bot on
## this seed met 1,192 robot shots, 1,178 of them fired with no line to the ship,
## and was destroyed; the `no_hidden_hits` check re-flies the replay and fails
## on any robot shot fired with no clear line, or crossing a wall. The seed is
## the owner's, so it is kept, not searched for; the hashes live only in
## `m3.json`.
##
## Re-recording this step only, from the repository root (the switch takes a
## comma-separated list of step ids, see `record_switch.gd`; `1` records every
## m3 step):
##
##     MELTDOWN_RECORD_M3=bot_generated_sight godot --headless --path game -s res://tests/run_tests.gd

const STEP_ID: String = "bot_generated_sight"
const REPLAY_PATH: String = "res://acceptance/replays/bot_generated_sight.replay"
const RECORD_SWITCH: String = "MELTDOWN_RECORD_M3"
const RecordSwitch := preload("res://tests/record_switch.gd")
const SeedPick := preload("res://tests/m3_seed_pick.gd")
## The flight takes about 6,000 ticks; the runner flies one per frame.
const FRAME_LIMIT: int = 40000
const OWNER_SEED: int = 31
const DRONE: String = "res://data/robots/drone.json"
const PULSE_CANNON: String = "res://data/weapons/pulse_cannon.json"
## Written above the recording; `Replay` skips lines starting with `#`.
const REPLAY_HEADER: String = """# The bot pilot's flight on generated seed 31 (#615), where the owner was hit by
# robots behind corridor walls. Inputs only: the m3 suite builds the level from
# the seed in m3.json and the shipped data files. Re-record from the repository
# root; the recorder writes the hashes into m3.json itself. Records this step only:
#     MELTDOWN_RECORD_M3=bot_generated_sight godot --headless --path game -s res://tests/run_tests.gd
"""

var _quit_codes: Array[int] = []


## Off unless RECORD_SWITCH is `1` or lists STEP_ID; see the top of this file.
## Flies the step's seed with the current bot and records it only if the
## outcome is the one the step expects and no robot hit from behind a wall.
func test_record_when_asked() -> String:
	if not RecordSwitch.asks_for(RECORD_SWITCH, STEP_ID):
		return ""
	var found: AcceptanceStep = SeedPick.find_step(STEP_ID)
	if found == null:
		return "m3 has no step %s; nothing recorded" % STEP_ID
	var flown: SeedPick.Flown = SeedPick.fly(found.level_seed)
	var session: LocalSession = flown.session
	if session == null:
		return "seed %d: %s; nothing recorded" % [found.level_seed, flown.reason]
	if session.sim.outcome() != found.expected_outcome:
		return "seed %d: %s, expected %s; nothing recorded" % [found.level_seed, flown.reason,
			AcceptanceStateChecks.outcome_name(found.expected_outcome)]
	var measured: Dictionary = {}
	var hidden: Array = AcceptanceStateChecks.no_hidden_hits(session.replay, measured)
	if hidden[0] != AcceptanceReport.RESULT_PASS:
		return "seed %d: %s; nothing recorded" % [found.level_seed, hidden[1]]
	var inputs: Replay = Replay.new(session.replay.run_seed, 1)
	inputs.frames = session.replay.frames
	inputs.expected_hash = session.sim.state_hash()
	var level_hash: int = AcceptanceStepLevel.level_hash(session.replay)
	var rewritten: String = SeedPick.rewrite_step(SeedLevel.read_text(SeedPick.SUITE_PATH), STEP_ID,
		found.level_seed, inputs.expected_hash, level_hash)
	if rewritten == "":
		return "%s has no step %s with seed and both hashes; nothing recorded" % [SeedPick.SUITE_PATH, STEP_ID]
	for written: Array in [[REPLAY_PATH, REPLAY_HEADER + inputs.to_text()], [SeedPick.SUITE_PATH, rewritten]]:
		var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path(written[0]), FileAccess.WRITE)
		if file == null:
			return "could not write %s: %s" % [written[0], error_string(FileAccess.get_open_error())]
		file.store_string(written[1])
		file.close()
	print("Meltdown: recorded %s: seed %d, %s, %s, hash %d, level hash %d" % [REPLAY_PATH,
		found.level_seed, flown.reason, hidden[1], inputs.expected_hash, level_hash])
	return ""


func test_the_step_flies_the_owner_seed_with_its_checks() -> String:
	var found: AcceptanceStep = SeedPick.find_step(STEP_ID)
	if found == null:
		return "m3 has no step %s" % STEP_ID
	if found.level_seed != OWNER_SEED or found.level != "" or found.replay_path != REPLAY_PATH:
		return "the step flies %s on seed %d, level '%s'" % [found.replay_path, found.level_seed, found.level]
	for check: String in [AcceptanceStep.CHECK_FINAL_HASH, AcceptanceStep.CHECK_LEVEL_HASH,
			AcceptanceStep.CHECK_OUTCOME, AcceptanceStep.CHECK_NO_HIDDEN_HITS]:
		if not found.has_check(check):
			return "%s does not check %s: %s" % [STEP_ID, check, found.checks]
	return ""


## The level must come from the seed, as for the other generated steps.
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


## The step alone, as the headset flies it: every check passes, and robots
## did fire at the ship, so the check had something to judge.
func test_the_runner_passes_the_step() -> String:
	var runner: AcceptanceRunner = _run()
	var problem: String = ""
	if runner.exit_code != AcceptanceRunner.EXIT_PASS or not runner.reports[0].passed():
		problem = "exit %d: %s" % [runner.exit_code, "\n".join(runner.messages)]
	else:
		var measured: Dictionary = runner.reports[0].steps[0]["measurements"]
		if int(measured.get("robot_shots", 0)) < 1:
			problem = "measured %s" % measured
	_done(runner)
	return problem


## On a hand-built replay through an opening the check counts the robot's
## shots and hits and passes.
func test_the_check_counts_shots_through_an_opening() -> String:
	var replay: Replay = Replay.new(615, 1)
	var mins: Array[Vector3i] = [Vector3i(0, 0, 0), Vector3i(0, 0, 8000), Vector3i(18000, 0, 4000)]
	var maxs: Array[Vector3i] = [Vector3i(40000, 6000, 6000), Vector3i(40000, 6000, 14000),
		Vector3i(22000, 6000, 10000)]
	replay.set_boxes(mins, maxs)
	replay.set_start_pose(0, Vector3(20.0, 3.0, 11.0), Vector3.FORWARD)
	var drone: RobotDef = RobotDef.parse_json(FileAccess.get_file_as_string(DRONE))
	var cannon: WeaponDef = WeaponDef.parse_json(FileAccess.get_file_as_string(PULSE_CANNON))
	# Facing +z, towards the ship across the opening.
	var spawn: RobotSpawn = RobotSpawn.new(drone, Vector3i(20000, 3000, 3000), Vector3i(0, 0, 1000), cannon)
	replay.robots.assign([spawn])
	for i: int in 300:
		replay.add_tick([ShipInput.new()] as Array[ShipInput])
	var measured: Dictionary = {}
	var result: Array = AcceptanceStateChecks.no_hidden_hits(replay, measured)
	if result[0] != AcceptanceReport.RESULT_PASS:
		return "gave %s" % [result]
	if int(measured.get("robot_shots", 0)) < 1 or int(measured.get("ship_hits", 0)) < 1:
		return "measured %s" % measured
	return ""


func test_the_check_is_known_and_needs_a_replay() -> String:
	var without: AcceptanceSuite = AcceptanceSuite.parse_json(
		"{\"name\": \"t\", \"steps\": [{\"id\": \"a\", \"checks\": [\"no_hidden_hits\"]}]}")
	if not without.error.contains("replay: needed by the no_hidden_hits check"):
		return "a step without a replay gave '%s'" % without.error
	return ""


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
	# Built and readied as on the headset, so the map in the hand that
	# `map_markers` reads is there (#912, as #884 did for `map_route`).
	var main: Node = scene.instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	runner.setup(main, suites, null)
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
