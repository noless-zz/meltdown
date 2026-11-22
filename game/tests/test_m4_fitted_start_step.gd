extends RefCounted

## The m4 suite's `fitted_start` step (#1057, CRF-4, CRW-1, DEV-6, decision
## record 0005): run 12345's first level flown as `--run` flies it, from a
## scratch profile (needle gun and lattice shield crafted, two shield
## technicians) and fitting (needle gun in primary slot 1, lattice shield) under
## `acceptance/fittings/`. The pinned level hash covers the ship's tuning and
## weapon lines, so it pins the fitted ship. Re-recording it after an intended
## change, from the repository root:
##
##     MELTDOWN_RECORD_M4=fitted_start godot --headless --path game -s res://tests/run_tests.gd

const SUITE_PATH: String = "res://acceptance/suites/m4.json"
const STEP_ID: String = "fitted_start"
const RECORD_SWITCH: String = "MELTDOWN_RECORD_M4"
const RecordSwitch := preload("res://tests/record_switch.gd")
## The replay takes about 7,200 ticks; the runner flies one per frame.
const FRAME_LIMIT: int = 20000

var _quit_codes: Array[int] = []


static func step(step_id: String = STEP_ID) -> AcceptanceStep:
	for found: AcceptanceStep in AcceptanceSuite.load_file(SUITE_PATH).steps:
		if found.id == step_id:
			return found
	return null


## Off unless the switch is `1` or lists the step; see the top of this file.
func test_record_when_asked() -> String:
	if not RecordSwitch.asks_for(RECORD_SWITCH, STEP_ID):
		return ""
	var runner: AcceptanceRunner = _run()
	var measured: Dictionary = runner.reports[0].steps[0]["measurements"] if not runner.reports.is_empty() else {}
	_done(runner)
	if not measured.has("level_hash"):
		return "the step measured no level hash: %s" % measured
	var text: String = SeedLevel.read_text(SUITE_PATH)
	var pattern: RegEx = RegEx.create_from_string("(\"id\": \"%s\"[^}]*?\"expected_level_hash\": )-?\\d+" % STEP_ID)
	if pattern.search(text) == null:
		return "m4.json step %s has no expected_level_hash; nothing recorded" % STEP_ID
	text = pattern.sub(text, "${1}" + str(measured["level_hash"]))
	var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path(SUITE_PATH), FileAccess.WRITE)
	if file == null:
		return "could not write %s" % SUITE_PATH
	file.store_string(text)
	file.close()
	print("Meltdown: recorded %s level hash %d" % [STEP_ID, measured["level_hash"]])
	return ""


func test_the_step_names_scratch_stores_and_pins_another_ship() -> String:
	var found: AcceptanceStep = step()
	var plain: AcceptanceStep = step("run_advances")
	if found == null or plain == null:
		return "m4 lacks %s or run_advances" % STEP_ID
	if found.run_seed != plain.run_seed or found.profile_path == "" or found.fitting_path == "":
		return "the step flies run %d from %s and %s" % [found.run_seed, found.profile_path, found.fitting_path]
	if found.expected_level_hash == plain.expected_level_hash:
		return "the fitted ship pins the plain ship's level hash %d" % found.expected_level_hash
	return ""


## The step alone, as the headset flies it: the level hash passes and the
## session flew the fitted needle gun with the two technicians' shield.
func test_the_runner_passes_the_step() -> String:
	var runner: AcceptanceRunner = _run()
	var problem: String = ""
	if runner.exit_code != AcceptanceRunner.EXIT_PASS or not runner.reports[0].passed():
		problem = "exit %d: %s" % [runner.exit_code, "\n".join(runner.messages)]
	else:
		var session: LocalSession = runner.main.get("session")
		var plain: ShipTuning = LocalSession.load_tuning(LevelStart.SHIP_TUNING_PATH)
		if LevelStart.local_loadout(session).ids_of("primary")[0] != "needle_gun" \
				or session.replay.tuning.max_shield <= plain.max_shield:
			problem = "the step flew %s with max_shield %s" % [LevelStart.local_loadout(session).ids_of("primary"),
				session.replay.tuning.max_shield]
	_done(runner)
	return problem


func test_a_run_step_without_stores_flies_the_plain_ship() -> String:
	var run: RunWiring = RunWiring.new(12345, null, Callable(), "", false)
	AcceptanceFittedStart.begin(run, step("run_advances"))
	if run.ship.enabled or run.ship.fittings != null:
		return "a run step without stores flies the fitted ship"
	AcceptanceFittedStart.begin(run, step())
	if not run.ship.enabled or run.ship.fittings == null or run.profile.crew.size() != 2:
		return "the fitted step's stores were not read"
	return ""


func test_store_fields_are_checked() -> String:
	var cases: Dictionary[String, String] = {
		"\"run\": 5, \"replay\": \"r\", \"profile\": \"\"": "steps[0].profile: must be a non-empty path",
		"\"run\": 5, \"replay\": \"r\", \"fitting\": 3": "steps[0].fitting: must be a non-empty path",
		"\"replay\": \"r\", \"profile\": \"p\"": "steps[0].profile: only used by a run step",
		"\"replay\": \"r\", \"seed\": 3, \"fitting\": \"f\"": "steps[0].fitting: only used by a run step",
	}
	for fields: String in cases:
		var suite: AcceptanceSuite = AcceptanceSuite.parse_json(
			"{\"name\": \"t\", \"steps\": [{\"id\": \"a\", \"checks\": [\"no_script_errors\"], %s}]}" % fields)
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
