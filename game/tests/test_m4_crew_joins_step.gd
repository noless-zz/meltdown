extends RefCounted

## The m4 suite's `crew_joins` step (#1084, CRW-1, SLV-3, DEV-6, ARC-2,
## decision record 0005): run 12345's first level flown as `--run` flies it,
## with component drops and miner rescue on, by the bot pilot given a rescue
## goal (`BotRescue`). It holds at the level's first trapped miner, shoots the
## reactor and escapes; the escape's restart press brings the miner into the
## run's profile as crew. Re-recording the replay and its hash after an
## intended change, from the repository root:
##
##     MELTDOWN_RECORD_M4=crew_joins godot --headless --path game -s res://tests/run_tests.gd

const SUITE_PATH: String = "res://acceptance/suites/m4.json"
const STEP_ID: String = "crew_joins"
const REPLAY_PATH: String = "res://acceptance/replays/crew_joins.replay"
const RUN_ADVANCES_REPLAY: String = "res://acceptance/replays/run_advances.replay"
const RECORD_SWITCH: String = "MELTDOWN_RECORD_M4"
const RecordSwitch := preload("res://tests/record_switch.gd")
const BotSweep := preload("res://tests/bot_escape_sweep.gd")
const RUN_SEED: int = 12345
## Ten minutes of flight, as `bot_escape_sweep.gd` allows.
const TICK_LIMIT: int = 36000
## The escape takes about 10,500 ticks; the runner flies one per frame.
const FRAME_LIMIT: int = 25000
## Ticks of the goal-free bot compared with the run_advances replay: past its
## first robot fights, short enough to keep the suite quick.
const COMPARED_TICKS: int = 2400
const REPLAY_HEADER: String = """# The bot pilot's flight through level 1 of run 12345 with a rescue goal
# (#1084): it holds at the first trapped miner, then shoots the reactor and
# escapes. The m4 suite's crew_joins step; flown with drops and rescue on, as
# --run flies it. Inputs only: the level is built from the run's level 1 seed.
# Re-record from the repository root; the recorder writes the hash into m4.json:
#     MELTDOWN_RECORD_M4=crew_joins godot --headless --path game -s res://tests/run_tests.gd
"""

var _quit_codes: Array[int] = []


static func step() -> AcceptanceStep:
	for found: AcceptanceStep in AcceptanceSuite.load_file(SUITE_PATH).steps:
		if found.id == STEP_ID:
			return found
	return null


## A run with no shaft choice, kept in memory, as the suite's run steps fly it.
static func _run_wiring() -> RunWiring:
	return RunWiring.new(RUN_SEED, null, Callable(), "", false)


## The bot's flight of the run's first level, `rules` on or off, with a rescue
## goal at the first trapped miner when `rescue` is true, for at most `ticks`.
static func _bot_flight(rules: bool, rescue: bool, ticks: int) -> LocalSession:
	var run: RunWiring = _run_wiring()
	run.level_rules = rules
	var level_start: LevelStart = LevelStart.new()
	level_start.run = run
	var world: Node3D = Node3D.new()
	var source: BotSweep.BotSource = BotSweep.BotSource.new()
	var session: LocalSession = level_start.session_for(world, run.level_source(), source)
	world.free()
	source.bot = BotPilot.new(session.sim, 0, LevelSwitch.load_level(run.level_source()))
	if rescue and session.sim.rescue != null and not session.sim.rescue.trapped.is_empty():
		source.bot.set_rescue_goal(session.sim.rescue.trapped[0])
	var sim: Sim = session.sim
	while sim.outcome() == ExitRule.Outcome.RUNNING and sim.ships[0].hull > 0.0 and sim.tick < ticks:
		session.advance(ShipState.TICK_DT)
	return session


## Off unless the switch is `1` or lists the step; see the top of this file.
func test_record_when_asked() -> String:
	if not RecordSwitch.asks_for(RECORD_SWITCH, STEP_ID):
		return ""
	var flown: LocalSession = _bot_flight(true, true, TICK_LIMIT)
	var sim: Sim = flown.sim
	if sim.outcome() != ExitRule.Outcome.ESCAPED or sim.rescue.rescued < 1:
		return "the bot ended %s at tick %d with %d rescued; nothing recorded" % [
			AcceptanceStateChecks.outcome_name(sim.outcome()), sim.tick, sim.rescue.rescued]
	var inputs: Replay = Replay.new(flown.replay.run_seed, 1)
	inputs.frames = flown.replay.frames
	inputs.expected_hash = sim.state_hash()
	var text: String = SeedLevel.read_text(SUITE_PATH)
	var pattern: RegEx = RegEx.create_from_string("(\"id\": \"%s\"[^}]*\"expected_hash\": )-?\\d+" % STEP_ID)
	text = pattern.sub(text, "${1}%d" % inputs.expected_hash)
	for written: Array in [[REPLAY_PATH, REPLAY_HEADER + inputs.to_text()], [SUITE_PATH, text]]:
		var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path(written[0]), FileAccess.WRITE)
		if file == null:
			return "could not write %s" % written[0]
		file.store_string(written[1])
		file.close()
	print("Meltdown: recorded %s: escaped at tick %d, %d rescued, hash %d" % [REPLAY_PATH, sim.tick,
		sim.rescue.rescued, inputs.expected_hash])
	return ""


func test_the_step_flies_run_12345_and_expects_one_crew() -> String:
	var found: AcceptanceStep = step()
	if found == null:
		return "m4 has no step %s" % STEP_ID
	if found.run_seed != RUN_SEED or found.replay_path != REPLAY_PATH \
			or found.checks[-1] != AcceptanceStep.CHECK_CREW_JOINS:
		return "the step flies run %d from %s and checks %s" % [found.run_seed, found.replay_path, found.checks]
	if found.expected_crew != 1 or found.expected_outcome != ExitRule.Outcome.ESCAPED:
		return "the step expects crew %d, outcome %d" % [found.expected_crew, found.expected_outcome]
	return ""


## The step alone, as the headset flies it: the miner is rescued, the level
## escaped, and the restart press adds the miner to the crew.
func test_the_runner_passes_the_step() -> String:
	var runner: AcceptanceRunner = _run([STEP_ID])
	var problem: String = ""
	if runner.exit_code != AcceptanceRunner.EXIT_PASS or not runner.reports[0].passed():
		problem = "exit %d: %s" % [runner.exit_code, "\n".join(runner.messages)]
	else:
		var measured: Dictionary = runner.reports[0].steps[0]["measurements"]
		var level_start: LevelStart = runner.main.get("level_start") as LevelStart
		if measured.get("crew") != 1 or int(measured.get("rescued", 0)) < 1:
			problem = "measured %s" % measured
		elif level_start.run.profile.crew.size() != 1:
			problem = "the run's profile holds %s" % [level_start.run.profile.crew]
	_done(runner)
	return problem


func test_a_wrong_crew_count_fails_naming_both() -> String:
	var wrong: Array = AcceptanceCrewJoinsCheck.judge(1, 1, 3)
	if wrong[0] != AcceptanceReport.RESULT_FAIL or not str(wrong[1]).contains("crew 1") \
			or not str(wrong[1]).contains("expected 3"):
		return "a wrong count gave %s" % [wrong]
	var right: Array = AcceptanceCrewJoinsCheck.judge(2, 2, 2)
	return "" if right[0] == AcceptanceReport.RESULT_PASS else "a right count gave %s" % [right]


## Without a goal the bot flies exactly as it did when the run_advances replay
## was recorded (rules off, as that step flies), so every bot replay keeps its hash.
func test_the_bot_with_no_goal_flies_as_before() -> String:
	var recorded: Replay = Replay.load_file(RUN_ADVANCES_REPLAY)
	var flown: LocalSession = _bot_flight(false, false, COMPARED_TICKS)
	if flown.sim.tick != COMPARED_TICKS or recorded.frames.size() < COMPARED_TICKS:
		return "flew %d ticks, the replay has %d" % [flown.sim.tick, recorded.frames.size()]
	for index: int in COMPARED_TICKS:
		if _frame_text(flown.replay.frames[index]) != _frame_text(recorded.frames[index]):
			return "tick %d: the bot gave %s, the replay holds %s" % [index,
				_frame_text(flown.replay.frames[index]), _frame_text(recorded.frames[index])]
	return ""


## A goal on a sim without rescue rules, or at a miner already freed, is spent
## at once: the bot goes on as if it had none.
func test_a_goal_without_a_trapped_miner_is_spent() -> String:
	var run: RunWiring = _run_wiring()
	var level: LevelDef = LevelSwitch.load_level(run.level_source())
	var plain: LocalSession = LocalSession.for_level(level)
	var without_rules: BotRescue = BotRescue.new(plain.sim, LevelRoute.new(level), level.miners[0])
	if without_rules.active() or not without_rules.done:
		return "a goal flew a sim without rescue rules"
	var ruled: LocalSession = _bot_flight(true, false, 0)
	var miner: Vector3i = ruled.sim.rescue.trapped[0]
	var goal: BotRescue = BotRescue.new(ruled.sim, LevelRoute.new(level), miner)
	if not goal.active():
		return "a goal at a trapped miner is not active"
	ruled.sim.rescue.trapped.erase(miner)
	return "" if not goal.active() else "a goal at a freed miner is still active"


## One frame's inputs as the replay file writes them.
static func _frame_text(frame: Array) -> String:
	return ReplayLines.tick_text(frame)


func test_crew_joins_fields_are_read_and_checked() -> String:
	var base: String = "\"id\": \"a\", \"replay\": \"r\", \"run\": 5"
	var cases: Dictionary[String, String] = {
		"\"checks\": [\"crew_joins\"]": "expected_crew: needed by the crew_joins check",
		"\"checks\": [\"crew_joins\"], \"expected_crew\": 0": "expected_crew: must be a whole number from 1",
		"\"checks\": [\"crew_joins\"], \"expected_crew\": 1.5": "expected_crew: must be a whole number from 1",
		"\"checks\": [\"outcome\"], \"expected_crew\": 1": "only used by the crew_joins check",
		"\"checks\": [\"crew_joins\", \"outcome\"], \"expected_crew\": 1": "must be the last check",
		"\"checks\": [\"components_bank\", \"crew_joins\"], \"expected_crew\": 1, " +
			"\"expected_banked\": {\"x\": 1}": "components_bank and crew_joins both move",
	}
	for fields: String in cases:
		var suite: AcceptanceSuite = AcceptanceSuite.parse_json(
			"{\"name\": \"t\", \"steps\": [{%s, %s}]}" % [base, fields])
		if not suite.error.contains(cases[fields]):
			return "%s gave '%s', expected it to say %s" % [fields, suite.error, cases[fields]]
	var no_run: AcceptanceSuite = AcceptanceSuite.parse_json("{\"name\": \"t\", \"steps\": [{\"id\": \"a\", " +
		"\"replay\": \"r\", \"checks\": [\"crew_joins\"], \"expected_crew\": 1}]}")
	if not no_run.error.contains("steps[0].run: needed by the crew_joins check"):
		return "no run gave '%s'" % no_run.error
	var read: AcceptanceSuite = AcceptanceSuite.parse_json("{\"name\": \"t\", \"steps\": [{%s, " % base +
		"\"checks\": [\"crew_joins\"], \"expected_crew\": 2}]}")
	if read.error != "" or read.steps[0].expected_crew != 2:
		return "read as %s" % (read.error if read.error != "" else str(read.steps[0].expected_crew))
	return ""


func _on_quit(code: int) -> void:
	_quit_codes.append(code)


func _run(ids: Array[String]) -> AcceptanceRunner:
	_quit_codes.clear()
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	var kept: Array[AcceptanceStep] = []
	for found: AcceptanceStep in suite.steps:
		if ids.has(found.id):
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
