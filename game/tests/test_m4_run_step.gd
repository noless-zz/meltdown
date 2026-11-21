extends RefCounted

## The m4 suite's first step, `run_advances` (#989, RUN-1, DEV-6, decision
## record 0005): run seed 12345's first level, flown by the bot pilot's replay
## as m3's `bot_generated_escape` is, escapes; then the escape's restart press
## flies the run's second level, with `RunPlan`'s level 2 seed and the pinned
## level hash.
##
## The replay holds only the inputs; the level is built from the run's level 1
## seed each time. The hashes live only in `acceptance/suites/m4.json`.
## Re-recording after an intended change, from the repository root:
##
##     MELTDOWN_RECORD_M4=run_advances godot --headless --path game -s res://tests/run_tests.gd

const SUITE_PATH: String = "res://acceptance/suites/m4.json"
const STEP_ID: String = "run_advances"
const REPLAY_PATH: String = "res://acceptance/replays/run_advances.replay"
const RECORD_SWITCH: String = "MELTDOWN_RECORD_M4"
const RecordSwitch := preload("res://tests/record_switch.gd")
const SeedPick := preload("res://tests/m3_seed_pick.gd")
## The escape takes about 7,200 ticks; the runner flies one per frame.
const FRAME_LIMIT: int = 20000
const REPLAY_HEADER: String = """# The bot pilot's escape from level 1 of run 12345 (#989): the m4 suite's
# run_advances step. Inputs only: the level is built from the run's level 1 seed.
# Re-record from the repository root; the recorder writes the hashes into m4.json:
#     MELTDOWN_RECORD_M4=run_advances godot --headless --path game -s res://tests/run_tests.gd
"""

var _quit_codes: Array[int] = []


static func step() -> AcceptanceStep:
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	for found: AcceptanceStep in suite.steps:
		if found.id == STEP_ID:
			return found
	return null


## Off unless the switch is `1` or lists the step; see the top of this file.
func test_record_when_asked() -> String:
	if not RecordSwitch.asks_for(RECORD_SWITCH, STEP_ID):
		return ""
	var found: AcceptanceStep = step()
	if found == null:
		return "m4 has no step %s" % STEP_ID
	var plan: RunPlan = AcceptanceRunStep.plan_for(found.run_seed)
	var flown: SeedPick.Flown = SeedPick.fly(plan.level_seed(0))
	if not flown.escaped:
		return "the bot does not escape level 1 of run %d: %s; nothing recorded" % [found.run_seed, flown.reason]
	var inputs: Replay = Replay.new(flown.session.replay.run_seed, 1)
	inputs.frames = flown.session.replay.frames
	inputs.expected_hash = flown.session.sim.state_hash()
	var level_hash: int = AcceptanceStepLevel.level_hash(flown.session.replay)
	var next: LocalSession = LocalSession.for_level(SeedLevel.load_level(plan.level_seed(1)), 0, null,
		LocalSession.load_tuning(LevelStart.SHIP_TUNING_PATH))
	var text: String = SeedLevel.read_text(SUITE_PATH)
	for pair: Array in [["expected_hash", inputs.expected_hash], ["expected_level_hash", level_hash],
			["expected_next_level_hash", AcceptanceStepLevel.level_hash(next.replay)]]:
		text = RegEx.create_from_string("\"%s\": -?\\d+" % pair[0]).sub(text, "\"%s\": %d" % pair, false)
	for written: Array in [[REPLAY_PATH, REPLAY_HEADER + inputs.to_text()], [SUITE_PATH, text]]:
		var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path(written[0]), FileAccess.WRITE)
		if file == null:
			return "could not write %s" % written[0]
		file.store_string(written[1])
		file.close()
	print("Meltdown: recorded %s: %s, hash %d" % [REPLAY_PATH, flown.reason, inputs.expected_hash])
	return ""


func test_the_step_flies_run_12345_and_checks_the_next_level() -> String:
	var found: AcceptanceStep = step()
	if found == null:
		return "m4 has no step %s" % STEP_ID
	var plan: RunPlan = AcceptanceRunStep.plan_for(12345)
	if found.run_seed != 12345 or found.level_seed != plan.level_seed(0) or found.replay_path != REPLAY_PATH:
		return "the step flies run %d, seed %d, %s" % [found.run_seed, found.level_seed, found.replay_path]
	if found.checks[-1] != AcceptanceStep.CHECK_RUN_ADVANCES or found.expected_outcome != ExitRule.Outcome.ESCAPED:
		return "the step checks %s" % [found.checks]
	return ""


## The step alone, as the headset flies it: every check passes and level 2 flies.
func test_the_runner_passes_the_step() -> String:
	var runner: AcceptanceRunner = _run()
	var problem: String = ""
	if runner.exit_code != AcceptanceRunner.EXIT_PASS or not runner.reports[0].passed():
		problem = "exit %d: %s" % [runner.exit_code, "\n".join(runner.messages)]
	else:
		var measured: Dictionary = runner.reports[0].steps[0]["measurements"]
		var want: String = LevelSwitch.SEED_PREFIX + str(AcceptanceRunStep.plan_for(12345).level_seed(1))
		if measured.get("outcome") != "ESCAPED" or measured.get("next_level_source") != want:
			problem = "measured %s" % measured
	_done(runner)
	return problem


func test_run_fields_are_read_and_checked() -> String:
	var cases: Dictionary[String, String] = {
		"\"run\": -1, \"replay\": \"r\"": "steps[0].run: must be a whole number",
		"\"run\": \"5\", \"replay\": \"r\"": "steps[0].run: must be a whole number",
		"\"run\": 5": "steps[0].run: only used with a replay",
		"\"run\": 5, \"replay\": \"r\", \"seed\": 3": "steps[0].run: a step flies a run, a seed or a level file",
		"\"run\": 5, \"replay\": \"r\", \"level\": \"g2\"": "steps[0].run: a step flies a run",
		"\"replay\": \"r\", \"expected_next_level_hash\": 3": "expected_next_level_hash: only used by a run step",
		"\"run\": 5, \"replay\": \"r\", \"expected_next_level_hash\": 3": "only used by the run_advances check",
	}
	for fields: String in cases:
		var suite: AcceptanceSuite = AcceptanceSuite.parse_json(
			"{\"name\": \"t\", \"steps\": [{\"id\": \"a\", \"checks\": [\"no_script_errors\"], %s}]}" % fields)
		if not suite.error.contains(cases[fields]):
			return "%s gave '%s', expected it to say %s" % [fields, suite.error, cases[fields]]
	var check_cases: Dictionary[String, String] = {
		"\"checks\": [\"run_advances\"], \"replay\": \"r\"": "steps[0].run: needed by the run_advances check",
		"\"checks\": [\"run_advances\"], \"replay\": \"r\", \"run\": 5": "expected_next_level_hash: needed",
		"\"checks\": [\"run_advances\", \"no_script_errors\"], \"replay\": \"r\", \"run\": 5": "must be the last check",
		"\"checks\": [\"run_advances\"], \"run\": 5": "steps[0].replay: needed by the run_advances check",
	}
	for fields: String in check_cases:
		var suite: AcceptanceSuite = AcceptanceSuite.parse_json(
			"{\"name\": \"t\", \"steps\": [{\"id\": \"a\", %s}]}" % fields)
		if not suite.error.contains(check_cases[fields]):
			return "%s gave '%s', expected it to say %s" % [fields, suite.error, check_cases[fields]]
	var read: AcceptanceSuite = AcceptanceSuite.parse_json("{\"name\": \"t\", \"steps\": [{\"id\": \"a\", " +
		"\"replay\": \"r\", \"run\": 7, \"checks\": [\"run_advances\"], \"expected_next_level_hash\": 9}]}")
	if read.error != "" or read.steps[0].run_seed != 7 or read.steps[0].expected_next_level_hash != 9 \
			or read.steps[0].level_seed != AcceptanceRunStep.plan_for(7).level_seed(0):
		return "run 7 read as %s" % (read.error if read.error != "" else str(read.steps[0].level_seed))
	return ""


func _on_quit(code: int) -> void:
	_quit_codes.append(code)


func _run() -> AcceptanceRunner:
	_quit_codes.clear()
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	var kept: Array[AcceptanceStep] = []
	for found: AcceptanceStep in suite.steps:
		if found.id == STEP_ID:
			kept.append(found)
	suite.steps = kept  # The step alone; `test_m4_shaft_step.gd` flies shaft_choice (#990).
	var suites: Array[AcceptanceSuite] = [suite]
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


func _done(runner: AcceptanceRunner) -> void:
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	if runner.main != null:
		runner.main.free()
	runner.free()
