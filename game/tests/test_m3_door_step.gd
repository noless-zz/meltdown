extends RefCounted

## The m3 suite's blast-door step (#516, RUN-4, GEN-2, DEV-6, decision record
## 0005): the bot pilot's escape from a generated seed on which at least one
## failed blast door (#462) has come down before it gets out. Like
## `bot_generated_escape` the replay holds only inputs and the level is built
## from the seed each run; the seed and hashes live only in `m3.json`.
##
## Re-recording uses the same one command as the other m3 steps, from the
## repository root:
##
##     MELTDOWN_RECORD_M3=1 godot --headless --path game -s res://tests/run_tests.gd
##
## It keeps the step's seed while the bot still escapes it with a door down,
## otherwise picks the lowest seed in 1..300 that does (`m3_seed_pick.gd`).

const STEP_ID: String = "bot_generated_door_escape"
const REPLAY_PATH: String = "res://acceptance/replays/bot_generated_door_escape.replay"
const RECORD_SWITCH: String = "MELTDOWN_RECORD_M3"
## The escape takes a few thousand ticks; the runner flies one per frame.
const FRAME_LIMIT: int = 40000
const SeedPick := preload("res://tests/m3_seed_pick.gd")
## Written above the recording; `Replay` skips lines starting with `#`.
const REPLAY_HEADER: String = """# The bot pilot's escape from the m3 suite's blast-door seed (#516): robots and
# the reactor destroyed, at least one blast door down, out through the entrance.
# Inputs only: the m3 suite builds the level from the seed in m3.json and the
# shipped data files. Re-record from the repository root; the recorder picks the
# seed and writes the seed and hashes into m3.json itself:
#     MELTDOWN_RECORD_M3=1 godot --headless --path game -s res://tests/run_tests.gd
"""
## One sphere, one door and one fire, all due one second after the meltdown.
const DEBRIS: String = """[{"position": [0, 0, -10], "radius": 1, "after_seconds": 1},
	{"position": [0, 0, -20], "size": [6, 6, 0.5], "after_seconds": 1},
	{"position": [0, 0, -30], "radius": 2, "after_seconds": 1, "kind": "fire", "damage_per_second": 5}]"""

var _quit_codes: Array[int] = []


## Off unless RECORD_SWITCH is set; see the top of this file.
func test_record_when_asked() -> String:
	if OS.get_environment(RECORD_SWITCH) != "1":
		return ""
	return SeedPick.record(STEP_ID, REPLAY_PATH, REPLAY_HEADER, true)


func test_the_step_names_its_seed_and_checks() -> String:
	var found: AcceptanceStep = SeedPick.find_step(STEP_ID)
	if found == null:
		return "m3 has no step %s" % STEP_ID
	if found.level_seed == AcceptanceStep.NO_SEED or found.level != "" or found.replay_path != REPLAY_PATH:
		return "the step flies %s on seed %d, level '%s'" % [found.replay_path, found.level_seed, found.level]
	for check: String in [AcceptanceStep.CHECK_FINAL_HASH, AcceptanceStep.CHECK_LEVEL_HASH,
			AcceptanceStep.CHECK_ROBOTS_CLEARED, AcceptanceStep.CHECK_OUTCOME, AcceptanceStep.CHECK_DOOR_FALLEN]:
		if not found.has_check(check):
			return "%s does not check %s: %s" % [STEP_ID, check, found.checks]
	if found.expected_outcome != ExitRule.Outcome.ESCAPED:
		return "%s expects outcome %d" % [STEP_ID, found.expected_outcome]
	if found.level_seed < SeedPick.SEARCH_FIRST or found.level_seed > SeedPick.SEARCH_LAST:
		return "%s flies seed %d, outside %d..%d" % [STEP_ID, found.level_seed, SeedPick.SEARCH_FIRST,
			SeedPick.SEARCH_LAST]
	return ""


## The level must come from the seed, as for `bot_generated_escape`.
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
## escapes with every robot gone and a door down.
func test_the_runner_passes_the_step() -> String:
	var runner: AcceptanceRunner = _run()
	var problem: String = ""
	if runner.exit_code != AcceptanceRunner.EXIT_PASS or not runner.reports[0].passed():
		problem = "exit %d: %s" % [runner.exit_code, "\n".join(runner.messages)]
	else:
		var measured: Dictionary = runner.reports[0].steps[0]["measurements"]
		if measured.get("outcome") != "ESCAPED" or int(measured.get("doors_fallen", 0)) < 1 \
				or int(measured.get("robots_alive", -1)) != 0:
			problem = "measured %s" % measured
	_done(runner)
	return problem


## Before the meltdown nothing is down and the check fails naming the step;
## once the door's time has come it passes. The sphere and the fire never
## count as doors.
func test_door_fallen_check_on_hand_made_states() -> String:
	var sim: Sim = Sim.new(0, 1)
	var measured: Dictionary = {}
	var none: Array = AcceptanceStateChecks.door_fallen(STEP_ID, sim, measured)
	if none[0] != AcceptanceReport.RESULT_FAIL or not str(none[1]).contains(STEP_ID) \
			or measured.get("doors") != 0:
		return "no debris gave %s, %s" % [none, measured]
	var debris: MeltdownDebris = MeltdownDebris.parse_json(DEBRIS)
	if debris.error != "":
		return debris.error
	sim.set_debris(debris)
	var before: Array = AcceptanceStateChecks.door_fallen(STEP_ID, sim, measured)
	if before[0] != AcceptanceReport.RESULT_FAIL or not str(before[1]).contains(STEP_ID) \
			or measured.get("doors") != 1 or measured.get("doors_fallen") != 0:
		return "debris before the meltdown gave %s, %s" % [before, measured]
	debris.elapsed_ticks = debris.after_ticks[1]
	var fell: Array = AcceptanceStateChecks.door_fallen(STEP_ID, sim, measured)
	if fell[0] != AcceptanceReport.RESULT_PASS or measured.get("doors_fallen") != 1:
		return "a fallen door gave %s, %s" % [fell, measured]
	return ""


## A door the route guard held back did not come down, so it does not count,
## even though `debris_fallen` counts it; the fallen sphere and burning fire
## do not count either.
func test_a_held_back_door_does_not_pass() -> String:
	var sim: Sim = Sim.new(0, 1)
	var debris: MeltdownDebris = MeltdownDebris.parse_json(DEBRIS)
	sim.set_debris(debris)
	debris.elapsed_ticks = debris.after_ticks[1]
	debris.skipped = [false, true, false]
	var measured: Dictionary = {}
	var result: Array = AcceptanceStateChecks.door_fallen(STEP_ID, sim, measured)
	if result[0] != AcceptanceReport.RESULT_FAIL or measured.get("doors_fallen") != 0:
		return "a held-back door gave %s, %s" % [result, measured]
	if AcceptanceStateChecks.debris_fallen(sim, measured)[0] != AcceptanceReport.RESULT_PASS:
		return "debris_fallen no longer counts the held-back door and the sphere"
	return ""


func test_the_check_is_known_and_needs_a_replay() -> String:
	var without: AcceptanceSuite = AcceptanceSuite.parse_json(
		"{\"name\": \"t\", \"steps\": [{\"id\": \"a\", \"checks\": [\"door_fallen\"]}]}")
	if not without.error.contains("replay: needed by the door_fallen check"):
		return "a step without a replay gave '%s'" % without.error
	var with: AcceptanceSuite = AcceptanceSuite.parse_json(
		"{\"name\": \"t\", \"steps\": [{\"id\": \"a\", \"replay\": \"r\", \"checks\": [\"door_fallen\"]}]}")
	if with.error != "":
		return "a step with a replay gave '%s'" % with.error
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
