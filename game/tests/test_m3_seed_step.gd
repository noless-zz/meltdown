extends RefCounted

## The m3 suite's generated-level step (#460, #494, GEN-1, GEN-2, RUN-4,
## RUN-5, DEV-6, decision record 0005): the bot pilot's escape from a
## generated seed, built by `SeedLevel` from the shipped data files as
## `--seed=<n>` builds it. The bot destroys the level's robots and the
## reactor, and at least one meltdown entry comes down before it is out.
##
## The replay holds only the inputs. The level is built from the seed each
## time the step runs, so changing a shipped generator, robot or debris value
## that changes this seed changes the flight and fails the step by name.
##
## The seed, the hash and the level hash live only in the step in
## `acceptance/suites/m3.json`. Re-recording after an intended change (one
## command, from the repository root; only the steps listed are re-recorded,
## see `record_switch.gd`, and `MELTDOWN_RECORD_M3=1` records every m3 step):
##
##     MELTDOWN_RECORD_M3=bot_generated_escape godot --headless --path game -s res://tests/run_tests.gd
##
## It keeps the suite's seed if the bot still escapes it with an entry down,
## otherwise picks the lowest seed that does (`m3_seed_pick.gd`), overwrites
## the replay and writes the seed and both hashes into `m3.json`.

const SUITE_PATH: String = "res://acceptance/suites/m3.json"
const STEP_ID: String = "bot_generated_escape"
## The other generated step, whose seed this one must not share (#548).
const DOOR_STEP_ID: String = "bot_generated_door_escape"
const REPLAY_PATH: String = "res://acceptance/replays/bot_generated_escape.replay"
const RECORD_SWITCH: String = "MELTDOWN_RECORD_M3"
const RecordSwitch := preload("res://tests/record_switch.gd")
const ROBOTS_FILE: String = "res://data/gen/robots.json"
const DEBRIS_FILE: String = "res://data/gen/debris.json"
## Biased placement (#438) means `generator.json` can change any seed; the
## module file is the generator data this test changes. It must be a module the
## step's seed places: seed 43 (#548) places it, as seed 26 did before (#531).
const MODULE_FILE: String = "res://data/modules/offset_shaft.json"
## The escape takes about 3,700 ticks; the runner flies one per frame.
const FRAME_LIMIT: int = 12000
const SeedPick := preload("res://tests/m3_seed_pick.gd")
## Written above the recording; `Replay` skips lines starting with `#`.
const REPLAY_HEADER: String = """# The bot pilot's escape from the m3 suite's generated seed (#460, #494): robots
# and the reactor destroyed, debris falling, out through the entrance. Inputs
# only: the m3 suite builds the level from the seed in m3.json and the shipped
# data files. Re-record from the repository root; the recorder picks the seed and
# writes the seed and hashes into m3.json itself. Records this step only:
#     MELTDOWN_RECORD_M3=bot_generated_escape godot --headless --path game -s res://tests/run_tests.gd
"""

var _quit_codes: Array[int] = []


static func step() -> AcceptanceStep:
	return SeedPick.find_step(STEP_ID)


## Off unless RECORD_SWITCH is `1` or lists STEP_ID; see the top of this file.
func test_record_when_asked() -> String:
	if not RecordSwitch.asks_for(RECORD_SWITCH, STEP_ID):
		return ""
	# Never the door step's seed (#548): two steps on one seed cover one level.
	return SeedPick.record(STEP_ID, REPLAY_PATH, REPLAY_HEADER, false,
		SeedPick.seeds_of([DOOR_STEP_ID] as Array[String]))


func test_the_step_names_its_seed_and_checks() -> String:
	var found: AcceptanceStep = step()
	if found == null:
		return "m3 has no step %s" % STEP_ID
	if found.level_seed == AcceptanceStep.NO_SEED or found.level != "" or found.replay_path != REPLAY_PATH:
		return "the step flies %s on seed %d, level '%s'" % [found.replay_path, found.level_seed, found.level]
	for check: String in [AcceptanceStep.CHECK_FINAL_HASH, AcceptanceStep.CHECK_OUTCOME,
			AcceptanceStep.CHECK_DEBRIS_FALLEN, AcceptanceStep.CHECK_LEVEL_HASH]:
		if not found.has_check(check):
			return "%s does not check %s: %s" % [STEP_ID, check, found.checks]
	if found.expected_outcome != ExitRule.Outcome.ESCAPED:
		return "%s expects outcome %d" % [STEP_ID, found.expected_outcome]
	if found.expected_level_hash == AcceptanceStep.NO_HASH:
		return "%s pins no level hash" % STEP_ID
	return ""


## The level must come from the seed: a replay carrying walls, a reactor,
## robots, debris or tuning would hide a data change.
func test_the_replay_holds_only_inputs() -> String:
	var replay: Replay = Replay.load_file(REPLAY_PATH)
	if replay.error != "":
		return replay.error
	if replay.box_mins_mm.size() > 0 or replay.reactor != null or not replay.robots.is_empty() \
			or replay.debris != null or replay.tuning != null or replay.loadout != null \
			or not replay.parts.is_empty() or not replay.start_positions_mm.is_empty():
		return "%s carries more than its inputs" % REPLAY_PATH
	if replay.ship_count != 1 or replay.frames.is_empty() or replay.expected_hash != step().expected_hash:
		return "%s: %d ships, %d ticks, hash %d" % [REPLAY_PATH, replay.ship_count,
			replay.frames.size(), replay.expected_hash]
	return ""


## The step alone, as the headset flies it: every check passes, the bot
## escapes with all four robots gone and at least one rock down.
func test_the_runner_passes_the_step() -> String:
	var runner: AcceptanceRunner = _run({})
	var problem: String = ""
	if runner.exit_code != AcceptanceRunner.EXIT_PASS or not runner.reports[0].passed():
		problem = "exit %d: %s" % [runner.exit_code, "\n".join(runner.messages)]
	else:
		var measured: Dictionary = runner.reports[0].steps[0]["measurements"]
		if measured.get("outcome") != "ESCAPED" or int(measured.get("debris_fallen", 0)) < 1 \
				or int(measured.get("robots_alive", -1)) != 0:
			problem = "measured %s" % measured
	_done(runner)
	return problem


## A changed shipped value that changes the seed's level fails the step, and
## the report and the log name it, and the level hash says the level changed
## even where the flight might not show it (a rock's radius). One change each
## to robot, debris and generator data.
func test_a_changed_data_value_fails_the_step_naming_it() -> String:
	var changes: Dictionary = {
		ROBOTS_FILE: ["\"min_per_level\": 4", "\"min_per_level\": 5"],
		DEBRIS_FILE: ["\"radius\": [1.5, 3]", "\"radius\": [1.5, 2.5]"],
		MODULE_FILE: ["\"min\": [2.0, -22.0, -5.0]", "\"min\": [1.0, -22.0, -5.0]"],
	}
	for path: String in changes:
		var text: String = SeedLevel.read_text(path)
		var pair: Array = changes[path]
		if not text.contains(pair[0]):
			return "%s no longer has %s; pick another change" % [path, pair[0]]
		var runner: AcceptanceRunner = _run({path: text.replace(pair[0], pair[1])})
		var report: Dictionary = runner.reports[0].steps[0] if not runner.reports.is_empty() else {}
		var said: String = "\n".join(runner.messages)
		var problem: String = ""
		if runner.exit_code != AcceptanceRunner.EXIT_FAIL:
			problem = "with %s changed the step still passed" % path.get_file()
		elif report.get("id") != STEP_ID or report.get("result") != AcceptanceReport.RESULT_FAIL:
			problem = "with %s changed the report says %s" % [path.get_file(), report]
		elif not str(report.get("message")).contains("level_hash: level hash"):
			problem = "with %s changed the level hash was not failed: %s" % [path.get_file(), report.get("message")]
		elif not str(report.get("message")).contains(SeedPick.record_command(STEP_ID)):
			problem = "with %s changed the report does not name the record command: %s" % [
				path.get_file(), report.get("message")]
		elif not said.contains("step %s %s" % [STEP_ID, AcceptanceReport.RESULT_FAIL]):
			problem = "with %s changed the log does not name the step: %s" % [path.get_file(), said]
		_done(runner)
		if problem != "":
			return problem
	return ""


func test_seed_is_read_and_checked() -> String:
	var cases: Dictionary[String, String] = {
		"\"seed\": -1, \"replay\": \"r\"": "steps[0].seed: must be a whole number",
		"\"seed\": 1.5, \"replay\": \"r\"": "steps[0].seed: must be a whole number",
		"\"seed\": \"205\", \"replay\": \"r\"": "steps[0].seed: must be a whole number",
		"\"seed\": 5": "steps[0].seed: only used with a replay",
		"\"seed\": 5, \"replay\": \"r\", \"level\": \"g2\"": "steps[0].seed: a step flies a level file or a seed",
	}
	for fields: String in cases:
		var suite: AcceptanceSuite = AcceptanceSuite.parse_json(
			"{\"name\": \"t\", \"steps\": [{\"id\": \"a\", \"checks\": [\"no_script_errors\"], %s}]}" % fields)
		if not suite.error.contains(cases[fields]):
			return "%s gave '%s', expected it to say %s" % [fields, suite.error, cases[fields]]
	var read: AcceptanceSuite = AcceptanceSuite.parse_json(
		"{\"name\": \"t\", \"steps\": [{\"id\": \"a\", \"replay\": \"r\", \"seed\": 0, \"checks\": [\"debris_fallen\"]}]}")
	if read.error != "" or read.steps[0].level_seed != 0:
		return "seed 0 read as %s" % (read.error if read.error != "" else str(read.steps[0].level_seed))
	return ""


func test_expected_level_hash_is_read_and_checked() -> String:
	var cases: Dictionary[String, String] = {
		"\"checks\": [\"level_hash\"]": "steps[0].expected_level_hash: needed",
		"\"checks\": [\"outcome\"], \"expected_outcome\": \"LOST\", \"expected_level_hash\": 1":
			"steps[0].expected_level_hash: only used",
		"\"checks\": [\"level_hash\"], \"expected_level_hash\": -3": "must be a whole number",
	}
	for fields: String in cases:
		var suite: AcceptanceSuite = AcceptanceSuite.parse_json(
			"{\"name\": \"t\", \"steps\": [{\"id\": \"a\", \"replay\": \"r\", %s}]}" % fields)
		if not suite.error.contains(cases[fields]):
			return "%s gave '%s', expected it to say %s" % [fields, suite.error, cases[fields]]
	return ""


## A seed step whose replay brings its own level is refused, not flown.
func test_a_replay_with_a_level_is_refused_for_a_seed_step() -> String:
	var replay: Replay = Replay.new(0, 1)
	replay.add_box(Vector3i(-1000, -1000, -1000), Vector3i(1000, 1000, 1000))
	var problem: String = AcceptanceStepLevel.fly_seed(null, step().level_seed, replay, ReplayInputSource.new(replay))
	if not problem.contains("carries a level of its own"):
		return "gave '%s'" % problem
	return ""


## The debris check fails a run where nothing fell and passes one where a rock did.
func test_debris_fallen_check() -> String:
	var sim: Sim = Sim.new(0, 1)
	var measured: Dictionary = {}
	var none: Array = AcceptanceStateChecks.debris_fallen(sim, measured)
	if none[0] != AcceptanceReport.RESULT_FAIL or measured.get("debris") != 0:
		return "no debris gave %s, %s" % [none, measured]
	var debris: MeltdownDebris = MeltdownDebris.parse_json(
		"[{\"position\": [0, 0, -10], \"radius\": 1, \"after_seconds\": 1}]")
	sim.set_debris(debris)
	if AcceptanceStateChecks.debris_fallen(sim, measured)[0] != AcceptanceReport.RESULT_FAIL:
		return "debris before the meltdown counted as fallen"
	debris.elapsed_ticks = debris.after_ticks[0]
	var fell: Array = AcceptanceStateChecks.debris_fallen(sim, measured)
	if fell[0] != AcceptanceReport.RESULT_PASS or measured.get("debris_fallen") != 1:
		return "a solid entry gave %s, %s" % [fell, measured]
	return ""


func _on_quit(code: int) -> void:
	_quit_codes.append(code)


## Flies a suite holding only this step, with `overrides` in place of data files.
func _run(overrides: Dictionary) -> AcceptanceRunner:
	_quit_codes.clear()
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	var only: AcceptanceSuite = AcceptanceSuite.new()
	only.name = suite.name
	only.error = suite.error
	only.steps.append(step())
	var suites: Array[AcceptanceSuite] = [only]
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = _on_quit
	runner.seed_overrides = overrides
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
