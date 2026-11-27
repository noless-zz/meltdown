extends RefCounted

## The m4 suite's `components_bank` step (#1028, CRF-1, CRF-2, DEV-6, decision
## record 0005): run 12345's first level flown as `--run` flies it, with
## component drops and miner rescue on, by the `run_advances` replay. A robot
## the bot pilot kills drops a cell salt the ship flies through, the level is
## escaped, and the escape's restart press banks it into the run's profile.
## The other run steps keep the rules off, so their pinned hashes stand.
## Re-recording the final hash after an intended change, from the repository root:
##
##     MELTDOWN_RECORD_M4=components_bank godot --headless --path game -s res://tests/run_tests.gd

const SUITE_PATH: String = "res://acceptance/suites/m4.json"
const STEP_ID: String = "components_bank"
const RECORD_SWITCH: String = "MELTDOWN_RECORD_M4"
const RecordSwitch := preload("res://tests/record_switch.gd")
const RulesTest := preload("res://tests/test_run_level_rules.gd")
const M4Plain := preload("res://tests/m4_plain_flight.gd")
## The escape takes about 7,200 ticks; the runner flies one per frame.
const FRAME_LIMIT: int = 20000

var _quit_codes: Array[int] = []


static func step() -> AcceptanceStep:
	for found: AcceptanceStep in AcceptanceSuite.load_file(SUITE_PATH).steps:
		if found.id == STEP_ID:
			return found
	return null


## Off unless the switch is `1` or lists the step; see the top of this file.
func test_record_when_asked() -> String:
	if not RecordSwitch.asks_for(RECORD_SWITCH, STEP_ID):
		return ""
	var flown: LocalSession = RulesTest.new()._flight()
	var text: String = SeedLevel.read_text(SUITE_PATH)
	var pattern: RegEx = RegEx.create_from_string("(\"id\": \"%s\"[^}]*\"expected_hash\": )-?\\d+" % STEP_ID)
	text = pattern.sub(text, "${1}%d" % flown.sim.state_hash())
	var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path(SUITE_PATH), FileAccess.WRITE)
	if file == null:
		return "could not write %s" % SUITE_PATH
	file.store_string(text)
	file.close()
	print("Meltdown: recorded %s: hash %d, collected %s" % [STEP_ID, flown.sim.state_hash(), flown.sim.collected])
	return ""


func test_the_step_banks_run_12345s_component() -> String:
	var found: AcceptanceStep = step()
	if found == null:
		return "m4 has no step %s" % STEP_ID
	if found.run_seed != 12345 or found.checks[-1] != AcceptanceStep.CHECK_COMPONENTS_BANK:
		return "the step flies run %d and checks %s" % [found.run_seed, found.checks]
	if found.expected_banked != {"cell_salts": 1}:
		return "the step expects %s banked" % found.expected_banked
	return ""


## The step alone, as the headset flies it: the escape banks the cell salt.
func test_the_runner_passes_the_step() -> String:
	var runner: AcceptanceRunner = _run([STEP_ID])
	var problem: String = ""
	if runner.exit_code != AcceptanceRunner.EXIT_PASS or not runner.reports[0].passed():
		problem = "exit %d: %s" % [runner.exit_code, "\n".join(runner.messages)]
	else:
		var measured: Dictionary = runner.reports[0].steps[0]["measurements"]
		if measured.get("banked") != "{\"cell_salts\":1}" or measured.get("collected") != "{\"cell_salts\":1}":
			problem = "measured %s" % measured
	_done(runner)
	return problem


## The other run steps fly the same replay with the rules off: `run_advances`'
## pinned hash stands, and the run's profile banks nothing. The flight is the
## plain ship's on that replay, judged against that hash, and shared with the
## other m4 tests (`m4_plain_flight.gd`, #1483); `test_m4_run_step.gd` flies
## `run_advances` itself.
func test_other_run_steps_keep_the_rules_off() -> String:
	if M4Plain.problem() != "":
		return M4Plain.problem()
	var measured: Dictionary = M4Plain.measured()
	if measured["level_rules"] or not (measured["banked"] as Dictionary).is_empty():
		return "run_advances' replay flew with rules: banked %s" % measured["banked"]
	return ""


func test_components_bank_fields_are_read_and_checked() -> String:
	var base: String = "\"id\": \"a\", \"replay\": \"r\", \"run\": 5"
	var cases: Dictionary[String, String] = {
		"\"checks\": [\"components_bank\"]": "expected_banked: needed by the components_bank check",
		"\"checks\": [\"components_bank\"], \"expected_banked\": {}": "must be an object of component id",
		"\"checks\": [\"components_bank\"], \"expected_banked\": {\"x\": 0}": "expected_banked.x: must be a whole",
		"\"checks\": [\"outcome\"], \"expected_banked\": {\"x\": 1}": "only used by the components_bank check",
		"\"checks\": [\"components_bank\", \"outcome\"], \"expected_banked\": {\"x\": 1}": "must be the last check",
		"\"checks\": [\"run_advances\", \"components_bank\"], \"expected_banked\": {\"x\": 1}, " +
			"\"expected_next_level_hash\": 3": "run_advances and components_bank both move",
	}
	for fields: String in cases:
		var suite: AcceptanceSuite = AcceptanceSuite.parse_json(
			"{\"name\": \"t\", \"steps\": [{%s, %s}]}" % [base, fields])
		if not suite.error.contains(cases[fields]):
			return "%s gave '%s', expected it to say %s" % [fields, suite.error, cases[fields]]
	var no_run: AcceptanceSuite = AcceptanceSuite.parse_json("{\"name\": \"t\", \"steps\": [{\"id\": \"a\", " +
		"\"replay\": \"r\", \"checks\": [\"components_bank\"], \"expected_banked\": {\"x\": 1}}]}")
	if not no_run.error.contains("steps[0].run: needed by the components_bank check"):
		return "no run gave '%s'" % no_run.error
	var read: AcceptanceSuite = AcceptanceSuite.parse_json("{\"name\": \"t\", \"steps\": [{%s, " % base +
		"\"checks\": [\"components_bank\"], \"expected_banked\": {\"scrap_alloy\": 2}}]}")
	if read.error != "" or read.steps[0].expected_banked != {"scrap_alloy": 2}:
		return "read as %s" % (read.error if read.error != "" else str(read.steps[0].expected_banked))
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
