extends RefCounted

## The m4 suite's first step, `run_advances` (#989, RUN-1, DEV-6, decision
## record 0005): the bot pilot escapes the first level of run 12345, started as
## `--run=12345` starts it, and the restart press flies the run's second level,
## checked by its seed and level hash.
##
## The replay holds only the inputs; both levels are built from the run's seeds
## and the shipped data files each time. Re-recording after an intended change,
## from the repository root:
##
##     MELTDOWN_RECORD_M4=run_advances godot --headless --path game -s res://tests/run_tests.gd
##
## It flies the bot on the run's first level, overwrites the replay and writes
## both hashes into `m4.json`. It fails, writing nothing, if the bot no longer
## escapes that level.

const SUITE_PATH: String = "res://acceptance/suites/m4.json"
const STEP_ID: String = "run_advances"
const RUN_SEED: int = 12345
const REPLAY_PATH: String = "res://acceptance/replays/bot_run_advances.replay"
const RecordSwitch := preload("res://tests/record_switch.gd")
const SeedPick := preload("res://tests/m3_seed_pick.gd")
## The escape takes about 7,100 ticks; the runner flies one per frame.
const FRAME_LIMIT: int = 20000
const REPLAY_HEADER: String = """# The bot pilot's escape from the first level of run 12345 (#989): the m4 suite
# starts the run as --run=12345 does, flies these inputs on its first level and
# checks that the restart press flies the run's second level. Inputs only.
# Re-record from the repository root:
#     MELTDOWN_RECORD_M4=run_advances godot --headless --path game -s res://tests/run_tests.gd
"""

var _quit_codes: Array[int] = []


static func step() -> AcceptanceStep:
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	for found: AcceptanceStep in suite.steps:
		if found.id == STEP_ID:
			return found
	return null


static func _plan() -> RunPlan:
	return RunPlan.build(RUN_SEED, FileAccess.get_file_as_string(RunWiring.RUN_FILE))


## The level hash of `level_seed`'s level as `LevelStart` builds it for a restart.
static func _level_hash(level_seed: int) -> int:
	var level: LevelDef = LevelSwitch.load_level(LevelSwitch.SEED_PREFIX + str(level_seed))
	var session: LocalSession = LocalSession.for_level(level, 0, null,
		LocalSession.load_tuning(LevelStart.SHIP_TUNING_PATH))
	return AcceptanceStepLevel.level_hash(session.replay)


## Off unless MELTDOWN_RECORD_M4 is `1` or lists the step; see the top of this file.
func test_record_when_asked() -> String:
	if not RecordSwitch.asks_for(AcceptanceRunStep.RECORD_SWITCH, STEP_ID):
		return ""
	var plan: RunPlan = _plan()
	var flown: SeedPick.Flown = SeedPick.fly(plan.level_seed(0))
	if not flown.escaped:
		return "the bot no longer escapes run %d's first level (%s); nothing recorded" % [RUN_SEED, flown.reason]
	var inputs: Replay = Replay.new(flown.session.replay.run_seed, 1)
	inputs.frames = flown.session.replay.frames
	inputs.expected_hash = flown.session.sim.state_hash()
	var suite: String = SeedLevel.read_text(SUITE_PATH)
	for pair: Array in [["expected_hash", inputs.expected_hash],
			["expected_next_level_hash", _level_hash(plan.level_seed(1))]]:
		var pattern: RegEx = RegEx.create_from_string("\"%s\": -?\\d+" % pair[0])
		suite = pattern.sub(suite, "\"%s\": %d" % pair, false)
	for written: Array in [[REPLAY_PATH, REPLAY_HEADER + inputs.to_text()], [SUITE_PATH, suite]]:
		var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path(written[0]), FileAccess.WRITE)
		if file == null:
			return "could not write %s" % written[0]
		file.store_string(written[1])
		file.close()
	print("Meltdown: recorded %s: %s, hash %d" % [REPLAY_PATH, flown.reason, inputs.expected_hash])
	return ""


func test_the_step_flies_a_run_and_checks_its_next_level() -> String:
	var found: AcceptanceStep = step()
	if found == null:
		return "m4 has no step %s" % STEP_ID
	if found.run_seed != RUN_SEED or found.level_seed != AcceptanceStep.NO_SEED or found.level != "" \
			or found.replay_path != REPLAY_PATH:
		return "the step flies %s on run %d, seed %d, level '%s'" % [found.replay_path, found.run_seed,
			found.level_seed, found.level]
	for check: String in [AcceptanceStep.CHECK_FINAL_HASH, AcceptanceStep.CHECK_OUTCOME,
			AcceptanceStep.CHECK_RUN_ADVANCES]:
		if not found.has_check(check):
			return "%s does not check %s: %s" % [STEP_ID, check, found.checks]
	if found.checks.back() != AcceptanceStep.CHECK_RUN_ADVANCES:
		return "run_advances must be the last check: it replaces the session the others read"
	if found.expected_outcome != ExitRule.Outcome.ESCAPED:
		return "%s expects outcome %d" % [STEP_ID, found.expected_outcome]
	if found.expected_next_level_hash != _level_hash(_plan().level_seed(1)):
		return "the pinned level 2 hash %d is not run %d's level 2 (%d)" % [found.expected_next_level_hash,
			RUN_SEED, _level_hash(_plan().level_seed(1))]
	return ""


func test_the_replay_holds_only_inputs() -> String:
	var replay: Replay = Replay.load_file(REPLAY_PATH)
	if replay.error != "":
		return replay.error
	if replay.box_mins_mm.size() > 0 or replay.reactor != null or not replay.robots.is_empty() \
			or replay.debris != null or replay.tuning != null or not replay.start_positions_mm.is_empty():
		return "%s carries more than its inputs" % REPLAY_PATH
	if replay.ship_count != 1 or replay.expected_hash != step().expected_hash:
		return "%s: %d ships, hash %d" % [REPLAY_PATH, replay.ship_count, replay.expected_hash]
	return ""


## The step as the headset flies it: every check passes, and the scene is left
## flying no run.
func test_the_runner_passes_the_step() -> String:
	var runner: AcceptanceRunner = _run()
	var problem: String = ""
	if runner.exit_code != AcceptanceRunner.EXIT_PASS or not runner.reports[0].passed():
		problem = "exit %d: %s" % [runner.exit_code, "\n".join(runner.messages)]
	else:
		var measured: Dictionary = runner.reports[0].steps[0]["measurements"]
		var wanted: String = LevelSwitch.SEED_PREFIX + str(_plan().level_seed(1))
		if measured.get("outcome") != "ESCAPED" or measured.get("run_next_source") != wanted:
			problem = "measured %s" % measured
		elif (runner.main.get("run") as RunWiring).is_active():
			problem = "the step left the scene flying a run"
	_done(runner)
	return problem


func test_run_fields_are_read_and_checked() -> String:
	var cases: Dictionary[String, String] = {
		"\"run\": -1, \"replay\": \"r\"": "steps[0].run: must be a whole number",
		"\"run\": 5": "steps[0].run: only used with a replay",
		"\"run\": 5, \"replay\": \"r\", \"seed\": 3": "steps[0].run: a step flies a level file, a seed or a run",
		"\"replay\": \"r\", \"checks\": [\"run_advances\"], \"expected_next_level_hash\": 4":
			"steps[0].run: needed by the run_advances check",
		"\"run\": 5, \"replay\": \"r\", \"checks\": [\"run_advances\"]":
			"steps[0].expected_next_level_hash: needed",
		"\"run\": 5, \"replay\": \"r\", \"expected_next_level_hash\": 4": "only used by the run_advances check",
		"\"checks\": [\"run_advances\"], \"run\": 5": "steps[0].replay: needed by the run_advances check",
	}
	for fields: String in cases:
		var text: String = fields if fields.contains("checks") else fields + ", \"checks\": [\"no_script_errors\"]"
		var suite: AcceptanceSuite = AcceptanceSuite.parse_json(
			"{\"name\": \"t\", \"steps\": [{\"id\": \"a\", %s}]}" % text)
		if not suite.error.contains(cases[fields]):
			return "%s gave '%s', expected it to say %s" % [fields, suite.error, cases[fields]]
	return ""


func _run() -> AcceptanceRunner:
	_quit_codes.clear()
	var only: AcceptanceSuite = AcceptanceSuite.new()
	only.name = "m4"
	only.steps.append(step())
	var suites: Array[AcceptanceSuite] = [only]
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = _on_quit
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	runner.setup(main, suites, null)
	var frames: int = 0
	while not runner.finished and frames < FRAME_LIMIT:
		runner.process_frame()
		frames += 1
	return runner


func _on_quit(code: int) -> void:
	_quit_codes.append(code)


func _done(runner: AcceptanceRunner) -> void:
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	if runner.main != null:
		runner.main.free()
	runner.free()
