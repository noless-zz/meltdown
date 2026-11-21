extends RefCounted

## The m4 suite's `shaft_choice` step (#990, RUN-1, DEV-6, decision record
## 0005): run 12345's first level, flown by the `run_advances` replay, escapes;
## scripted input presses A on the escape screen, which opens the shaft panel,
## moves the stick down and presses A, and the run flies level 2 through the
## second offered shaft, with `RunPlan.level_seed_through`'s seed and the pinned
## level hash. The level is built from its seed, so only the hash is recorded.
## Re-recording after an intended change, from the repository root:
##
##     MELTDOWN_RECORD_M4=shaft_choice godot --headless --path game -s res://tests/run_tests.gd

const SUITE_PATH: String = "res://acceptance/suites/m4.json"
const STEP_ID: String = "shaft_choice"
const RECORD_SWITCH: String = "MELTDOWN_RECORD_M4"
const RecordSwitch := preload("res://tests/record_switch.gd")
## The escape takes about 7,200 ticks and the escape screen a few seconds more.
const FRAME_LIMIT: int = 20000

var _quit_codes: Array[int] = []


static func step() -> AcceptanceStep:
	for found: AcceptanceStep in AcceptanceSuite.load_file(SUITE_PATH).steps:
		if found.id == STEP_ID:
			return found
	return null


## The level hash of level 2 of `run_seed` through the second shaft offered
## after level 1, built busier by that shaft's `risk.robot_count` (#1011).
static func next_level_hash(run_seed: int) -> int:
	var run: RunWiring = RunWiring.new(run_seed)
	var kind: String = run.escape_for_choice({})[AcceptanceShaftChoiceCheck.PICK]
	run.choose(kind)
	var next: LocalSession = LocalSession.for_level(LevelSwitch.load_level(run.level_source()), 0, null,
		LocalSession.load_tuning(LevelStart.SHIP_TUNING_PATH))
	return AcceptanceStepLevel.level_hash(next.replay)


## Off unless the switch is `1` or lists the step; see the top of this file.
func test_record_when_asked() -> String:
	if not RecordSwitch.asks_for(RECORD_SWITCH, STEP_ID):
		return ""
	var found: AcceptanceStep = step()
	if found == null:
		return "m4 has no step %s" % STEP_ID
	var text: String = SeedLevel.read_text(SUITE_PATH)
	var pattern: RegEx = RegEx.create_from_string(
		"(\"id\": \"%s\"[^}]*\"expected_next_level_hash\": )-?\\d+" % STEP_ID)
	text = pattern.sub(text, "${1}%d" % next_level_hash(found.run_seed))
	var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path(SUITE_PATH), FileAccess.WRITE)
	if file == null:
		return "could not write %s" % SUITE_PATH
	file.store_string(text)
	file.close()
	return ""


func test_the_step_chooses_a_shaft_in_run_12345() -> String:
	var found: AcceptanceStep = step()
	if found == null:
		return "m4 has no step %s" % STEP_ID
	var plan: RunPlan = AcceptanceRunStep.plan_for(12345)
	if found.run_seed != 12345 or found.level_seed != plan.level_seed(0):
		return "the step flies run %d, seed %d" % [found.run_seed, found.level_seed]
	if found.checks[-1] != AcceptanceStep.CHECK_SHAFT_CHOICE or found.expected_outcome != ExitRule.Outcome.ESCAPED:
		return "the step checks %s" % [found.checks]
	var kind: String = RunWiring.new(12345).escape_for_choice({})[AcceptanceShaftChoiceCheck.PICK]
	var shafts: ShaftOffer = ShaftOffer.build(FileAccess.get_file_as_string(RunWiring.SHAFTS_FILE))
	if float(shafts.risks[kind]["robot_count"]) <= 1.0:
		return "the step picks %s, which does not scale the robots, so no busier level is pinned (#1011)" % kind
	if found.expected_next_level_hash != next_level_hash(12345):
		return "the pinned hash %d is not level 2's through the second shaft" % found.expected_next_level_hash
	return ""


## The step alone, as the headset flies it: every check passes and the chosen shaft's level flies.
func test_the_runner_passes_the_step() -> String:
	var runner: AcceptanceRunner = _run()
	var problem: String = ""
	if runner.exit_code != AcceptanceRunner.EXIT_PASS or not runner.reports[0].passed():
		problem = "exit %d: %s" % [runner.exit_code, "\n".join(runner.messages)]
	else:
		var measured: Dictionary = runner.reports[0].steps[0]["measurements"]
		var run: RunWiring = RunWiring.new(12345)
		var offered: Array[String] = run.escape_for_choice({})
		var kind: String = offered[AcceptanceShaftChoiceCheck.PICK]
		var want: String = LevelSwitch.seed_source(run.state.plan.level_seed_through(1, run.shafts, kind),
			float(run.shafts.risks[kind]["robot_count"]))
		if measured.get("chosen") != kind or measured.get("next_level_source") != want \
				or measured.get("offered") != ",".join(offered):
			problem = "measured %s" % measured
	_done(runner)
	return problem


func test_shaft_choice_fields_are_checked() -> String:
	var cases: Dictionary[String, String] = {
		"\"checks\": [\"shaft_choice\"], \"replay\": \"r\"": "steps[0].run: needed by the shaft_choice check",
		"\"checks\": [\"shaft_choice\"], \"replay\": \"r\", \"run\": 5": "expected_next_level_hash: needed by the shaft_choice",
		"\"checks\": [\"shaft_choice\", \"outcome\"], \"replay\": \"r\", \"run\": 5": "shaft_choice must be the last check",
		"\"checks\": [\"shaft_choice\"], \"run\": 5": "steps[0].replay: needed by the shaft_choice check",
		"\"checks\": [\"run_advances\", \"shaft_choice\"], \"replay\": \"r\", \"run\": 5": "a step lists one",
	}
	for fields: String in cases:
		var suite: AcceptanceSuite = AcceptanceSuite.parse_json(
			"{\"name\": \"t\", \"steps\": [{\"id\": \"a\", %s}]}" % fields)
		if not suite.error.contains(cases[fields]):
			return "%s gave '%s', expected it to say %s" % [fields, suite.error, cases[fields]]
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
	suite.steps = kept  # The step alone; each m4 step has its own test file.
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
