extends RefCounted

## The m4 suite's `abandon_run` step (#1246, RUN-1, RUN-7, CRF-2, DEV-7,
## decision record 0005): run 12345's first level replayed and escaped with
## drops on, then abandoned on level 2 through the menu row's own call; the
## level-1 bank stays, the loss is counted, the hub opens on a new run, and
## no scratch save is left behind.

const SUITE_PATH: String = "res://acceptance/suites/m4.json"
const STEP_ID: String = "abandon_run"
## The replay is a short escape; the runner flies one tick per frame.
const FRAME_LIMIT: int = 8000

var _quit_codes: Array[int] = []


static func step() -> AcceptanceStep:
	for found: AcceptanceStep in AcceptanceSuite.load_file(SUITE_PATH).steps:
		if found.id == STEP_ID:
			return found
	return null


func test_the_step_flies_run_12345_and_abandons_last() -> String:
	var found: AcceptanceStep = step()
	if found == null:
		return "m4 lacks %s" % STEP_ID
	if found.run_seed != 12345 or found.checks[-1] != AcceptanceStep.CHECK_ABANDON_RUN \
			or found.expected_banked.is_empty():
		return "the step flies run %d with checks %s" % [found.run_seed, found.checks]
	return ""


func test_the_runner_passes_the_step_and_leaves_no_scratch_save() -> String:
	var runner: AcceptanceRunner = _run()
	var problem: String = ""
	if runner.exit_code != AcceptanceRunner.EXIT_PASS or not runner.reports[0].passed():
		problem = "exit %d: %s" % [runner.exit_code, "\n".join(runner.messages)]
	elif FileAccess.file_exists(AcceptanceAbandonRunCheck.SCRATCH_PATH):
		problem = "the step left its scratch save behind"
	elif (runner.main.get("hub") as HubWiring).is_open():
		problem = "the step left the hub open"
	_done(runner)
	return problem


func test_the_check_needs_a_run_and_banked_counts_and_comes_last() -> String:
	var banked: String = ", \"expected_banked\": {\"cell_salts\": 1}"
	var cases: Dictionary[String, String] = {
		"\"replay\": \"r\", \"checks\": [\"abandon_run\"]" + banked: "steps[0].run: needed by the abandon_run check",
		"\"run\": 5, \"replay\": \"r\", \"checks\": [\"abandon_run\"]":
			"steps[0].expected_banked: needed by the abandon_run check",
		"\"run\": 5, \"replay\": \"r\", \"checks\": [\"abandon_run\", \"no_script_errors\"]" + banked:
			"abandon_run must be the last check",
		"\"run\": 5, \"checks\": [\"abandon_run\"]" + banked: "steps[0].replay: needed by the abandon_run check",
		"\"run\": 5, \"replay\": \"r\", \"checks\": [\"components_bank\", \"abandon_run\"]" + banked:
			"components_bank and abandon_run both move",
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
