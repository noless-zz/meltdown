extends RefCounted

## The m4 suite's `shaft_rewards` steps (#1065, CRF-7, RUN-1, DEV-6, decision
## record 0005): run 12345's first level, flown by the `run_advances` replay,
## escapes; the step takes a shaft through the shaft panel's path and flies a
## bot pilot's replay on that shaft's level 2 with drops on. Two steps take two
## shafts, and their pinned `collected` counts differ, because the shaft's
## reward weights shape the drops (#1000). Each level-2 replay holds inputs
## only; its level is built from the run and the shaft. Re-recording after an
## intended change, from the repository root (both steps, or name one):
##
##     MELTDOWN_RECORD_M4=shaft_rewards,shaft_rewards_steady godot --headless --path game -s res://tests/run_tests.gd
##
## The recorder flies `BotPilot` on the step's level 2 until it escapes, writes
## its inputs to the step's `next_replay`, and the final hash and collected
## counts into m4.json.

const SUITE_PATH: String = "res://acceptance/suites/m4.json"
const STEP_IDS: Array[String] = ["shaft_rewards", "shaft_rewards_steady"]
const RECORD_SWITCH: String = "MELTDOWN_RECORD_M4"
const RecordSwitch := preload("res://tests/record_switch.gd")
const BotSweep := preload("res://tests/bot_escape_sweep.gd")
## Level 1 takes about 7,200 ticks and level 2 up to about 10,000.
const FRAME_LIMIT: int = 30000
## The longest the recorder lets the bot fly level 2: 10 minutes of ticks.
const RECORD_TICK_LIMIT: int = 36000

var _quit_codes: Array[int] = []


static func step(step_id: String) -> AcceptanceStep:
	for found: AcceptanceStep in AcceptanceSuite.load_file(SUITE_PATH).steps:
		if found.id == step_id:
			return found
	return null


## Level 2 of `found`'s run through its shaft as `LevelStart.session_for`
## builds it, with drops on and weighted by the shaft, flown by `input`.
static func level_two(found: AcceptanceStep, input: ShipInputSource) -> LocalSession:
	var run: RunWiring = RunWiring.new(found.run_seed)
	run.choose(run.escape_for_choice({})[found.shaft_index])
	var level: LevelDef = LevelSwitch.load_level(run.level_source())
	var session: LocalSession = LocalSession.for_level(level, 0, input,
		LocalSession.load_tuning(LevelStart.SHIP_TUNING_PATH))
	RunLevelRules.load_files(RunLevelRules.COMPONENTS_DIR, RunLevelRules.RESCUE_FILE, run.level_reward()) \
		.install(session, level)
	return session


## Off unless the switch is `1` or lists a step; see the top of this file.
func test_record_when_asked() -> String:
	for step_id: String in STEP_IDS:
		if not RecordSwitch.asks_for(RECORD_SWITCH, step_id):
			continue
		var problem: String = _record(step_id)
		if problem != "":
			return problem
	return ""


func _record(step_id: String) -> String:
	var found: AcceptanceStep = step(step_id)
	if found == null or found.next_replay_path == "":
		return "m4 has no step %s with a next_replay" % step_id
	var source: BotSweep.BotSource = BotSweep.BotSource.new()
	var session: LocalSession = level_two(found, source)
	source.bot = BotPilot.new(session.sim, 0, LevelSwitch.load_level(_level_source(found)))
	var sim: Sim = session.sim
	while sim.outcome() == ExitRule.Outcome.RUNNING and sim.ships[0].hull > 0.0 and sim.tick < RECORD_TICK_LIMIT:
		session.advance(ShipState.TICK_DT)
	if sim.outcome() != ExitRule.Outcome.ESCAPED:
		return "%s: the bot did not escape level 2 (%s at tick %d); nothing recorded" % [step_id,
			AcceptanceStateChecks.outcome_name(sim.outcome()), sim.tick]
	var inputs: Replay = Replay.new(session.replay.run_seed, 1)
	inputs.frames = session.replay.frames
	inputs.expected_hash = sim.state_hash()
	var counts: Dictionary[String, int] = AcceptanceCollectedCheck.counts_of(sim.collected)
	var kinds: Array[String] = []
	kinds.assign(counts.keys())
	kinds.sort()
	var pairs: PackedStringArray = PackedStringArray()
	for kind: String in kinds:
		pairs.append("\"%s\": %d" % [kind, counts[kind]])
	var collected: String = "{%s}" % ", ".join(pairs)  # As the suite writes an object.
	var text: String = SeedLevel.read_text(SUITE_PATH)
	for pair: Array in [["expected_hash", "-?\\d+", str(inputs.expected_hash)],
			["expected_collected", "\\{[^}]*\\}", collected]]:
		var pattern: RegEx = RegEx.create_from_string(
			"(\"id\": \"%s\"[^}]*?\"%s\": )%s" % [step_id, pair[0], pair[1]])
		if pattern.search(text) == null:
			return "m4.json step %s has no %s; nothing recorded" % [step_id, pair[0]]
		text = pattern.sub(text, "${1}" + pair[2])
	var header: String = ("# The bot pilot on level 2 of run 12345 after shaft %d (%s) (#1065): the m4\n"
		+ "# suite's %s step. Inputs only: the level is built from the run and the shaft.\n"
		+ "# Re-record from the repository root; the recorder writes the hash and counts into m4.json:\n"
		+ "#     %s=%s godot --headless --path game -s res://tests/run_tests.gd\n") % [found.shaft_index,
		_level_source(found), step_id, RECORD_SWITCH, step_id]
	for written: Array in [[found.next_replay_path, header + inputs.to_text()], [SUITE_PATH, text]]:
		var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path(written[0]), FileAccess.WRITE)
		if file == null:
			return "could not write %s" % written[0]
		file.store_string(written[1])
		file.close()
	print("Meltdown: recorded %s: %d ticks, hash %d, collected %s" % [found.next_replay_path, sim.tick,
		inputs.expected_hash, collected])
	return ""


static func _level_source(found: AcceptanceStep) -> String:
	var run: RunWiring = RunWiring.new(found.run_seed)
	run.choose(run.escape_for_choice({})[found.shaft_index])
	return run.level_source()


func test_two_steps_take_different_shafts_and_pin_different_counts() -> String:
	var first: AcceptanceStep = step(STEP_IDS[0])
	var second: AcceptanceStep = step(STEP_IDS[1])
	if first == null or second == null:
		return "m4 lacks %s" % [STEP_IDS]
	for found: AcceptanceStep in [first, second]:
		if found.run_seed != 12345 or found.replay_path != "res://acceptance/replays/run_advances.replay" \
				or found.checks[-1] != AcceptanceStep.CHECK_COLLECTED or found.expected_collected.is_empty():
			return "%s flies run %d with %s, checks %s, pins %s" % [found.id, found.run_seed, found.replay_path,
				found.checks, found.expected_collected]
	if first.shaft_index == second.shaft_index or first.next_replay_path == second.next_replay_path:
		return "both steps take shaft %d" % first.shaft_index
	if first.expected_collected == second.expected_collected:
		return "both steps pin %s; the shafts' rewards are not told apart" % first.expected_collected
	return ""


## Each step alone, as the headset flies it: every check passes on the chosen shaft's level.
func test_the_runner_passes_each_step() -> String:
	for step_id: String in STEP_IDS:
		var runner: AcceptanceRunner = _run(step_id)
		var problem: String = ""
		if runner.exit_code != AcceptanceRunner.EXIT_PASS or not runner.reports[0].passed():
			problem = "%s: exit %d: %s" % [step_id, runner.exit_code, "\n".join(runner.messages)]
		else:
			var measured: Dictionary = runner.reports[0].steps[0]["measurements"]
			var found: AcceptanceStep = step(step_id)
			var want: String = AcceptanceShaftStep.offer_for(12345)[found.shaft_index]
			if measured.get("shaft") != want or measured.get("level_source") != _level_source(found):
				problem = "%s measured %s, expected shaft %s" % [step_id, measured, want]
		_done(runner)
		if problem != "":
			return problem
	return ""


func test_shaft_fields_are_checked() -> String:
	var run: String = "\"run\": 12345, \"replay\": \"r\""
	var cases: Dictionary[String, String] = {
		"%s, \"shaft\": 0, \"checks\": [\"outcome\"]" % run: "steps[0].next_replay: needed with shaft",
		"%s, \"next_replay\": \"n\", \"checks\": [\"outcome\"]" % run: "steps[0].shaft: needed with next_replay",
		"%s, \"shaft\": 0, \"next_replay\": \"\", \"checks\": [\"outcome\"]" % run: "next_replay: must be a non-empty path",
		"\"replay\": \"r\", \"shaft\": 0, \"next_replay\": \"n\", \"checks\": [\"outcome\"]": "shaft: only used by a run step",
		"%s, \"shaft\": -1, \"next_replay\": \"n\", \"checks\": [\"outcome\"]" % run: "shaft: must be a whole number from 0",
		"%s, \"shaft\": 1.5, \"next_replay\": \"n\", \"checks\": [\"outcome\"]" % run: "shaft: must be a whole number from 0",
		"%s, \"shaft\": 9, \"next_replay\": \"n\", \"checks\": [\"outcome\"]" % run: "steps[0].shaft: step a picks shaft 9, but run 12345 offers",
		"%s, \"shaft\": 0, \"next_replay\": \"n\", \"checks\": [\"run_advances\"], \"expected_next_level_hash\": 1" % run:
			"run_advances presses on to the next level",
		"%s, \"checks\": [\"collected\"]" % run: "expected_collected: needed by the collected check",
		"%s, \"checks\": [\"outcome\"], \"expected_collected\": {}" % run: "expected_collected: only used by the collected check",
		"%s, \"checks\": [\"collected\"], \"expected_collected\": {\"scrap_alloy\": 0}" % run: "expected_collected.scrap_alloy: must be a whole number from 1",
		"%s, \"checks\": [\"collected\"], \"expected_collected\": [1]" % run: "expected_collected: must be an object",
		"\"checks\": [\"collected\"], \"expected_collected\": {}": "steps[0].replay: needed by the collected check",
	}
	for fields: String in cases:
		var suite: AcceptanceSuite = AcceptanceSuite.parse_json(
			"{\"name\": \"t\", \"steps\": [{\"id\": \"a\", %s}]}" % fields)
		if not suite.error.contains(cases[fields]):
			return "%s gave '%s', expected it to say %s" % [fields, suite.error, cases[fields]]
	return ""


func test_shaft_fields_are_read() -> String:
	var suite: AcceptanceSuite = AcceptanceSuite.parse_json("{\"name\": \"t\", \"steps\": [{\"id\": \"a\", "
		+ "\"run\": 12345, \"replay\": \"r\", \"shaft\": 1, \"next_replay\": \"n\", \"checks\": [\"collected\"], "
		+ "\"expected_collected\": {\"scrap_alloy\": 2}}, {\"id\": \"b\", \"run\": 12345, \"replay\": \"r\", "
		+ "\"checks\": [\"outcome\"], \"expected_outcome\": \"ESCAPED\"}]}")
	if suite.error != "":
		return suite.error
	var read: AcceptanceStep = suite.steps[0]
	if read.shaft_index != 1 or read.next_replay_path != "n" or read.expected_collected != {"scrap_alloy": 2}:
		return "read shaft %d, %s, %s" % [read.shaft_index, read.next_replay_path, read.expected_collected]
	var plain: AcceptanceStep = suite.steps[1]
	if plain.shaft_index != AcceptanceStep.NO_SHAFT or plain.next_replay_path != "":
		return "a step without the fields reads shaft %d, %s" % [plain.shaft_index, plain.next_replay_path]
	return ""


func test_the_offer_is_the_panels() -> String:
	var offered: Array[String] = AcceptanceShaftStep.offer_for(12345)
	var panel: Array[String] = RunWiring.new(12345).escape_for_choice({})
	if offered.is_empty() or offered != panel:
		return "offer_for gives %s, the run offers %s" % [offered, panel]
	return ""


func _on_quit(code: int) -> void:
	_quit_codes.append(code)


func _run(step_id: String) -> AcceptanceRunner:
	_quit_codes.clear()
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	var kept: Array[AcceptanceStep] = []
	for found: AcceptanceStep in suite.steps:
		if found.id == step_id:
			kept.append(found)
	suite.steps = kept
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
