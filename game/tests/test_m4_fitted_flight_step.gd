extends RefCounted

## The m4 suite's `fitted_flight` step (#1119, CRF-4, CMB-1, CRW-1, ARC-2,
## DEV-6, decision record 0005): run 12345's first level flown by the
## `run_advances` replay with `fitted_start`'s scratch profile and fitting
## (needle gun, lattice shield, two shield technicians). `fitted_start` pins
## only the fitted level's hash; this step pins where the fitted ship's flight
## ends, so a crafted upgrade that stops changing the flight shows here (gate
## #950's "a crafted upgrade is felt in the next run", its measurable half).
##
## The replay's inputs are the plain ship's recording, so the step measures a
## difference, not whether the fitted ship flies well. On those inputs the
## fitted ship does not reach the exit before the replay ends (outcome RUNNING)
## where the plain one escapes; the issue says to pin that rather than change data.
## Re-recording the final hash after an intended change, from the repository root:
##
##     MELTDOWN_RECORD_M4=fitted_flight godot --headless --path game -s res://tests/run_tests.gd

const SUITE_PATH: String = "res://acceptance/suites/m4.json"
const STEP_ID: String = "fitted_flight"
const PLAIN_ID: String = "run_advances"
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


## The fitted step with its scratch stores dropped: the plain ship on the same
## replay, judged against `run_advances`' pinned final hash and outcome.
static func plain_step() -> AcceptanceStep:
	var plain: AcceptanceStep = step()
	plain.profile_path = ""
	plain.fitting_path = ""
	plain.expected_hash = step(PLAIN_ID).expected_hash
	plain.expected_outcome = step(PLAIN_ID).expected_outcome
	return plain


## Off unless the switch is `1` or lists the step; see the top of this file.
func test_record_when_asked() -> String:
	if not RecordSwitch.asks_for(RECORD_SWITCH, STEP_ID):
		return ""
	var runner: AcceptanceRunner = _run(step())
	var measured: Dictionary = runner.reports[0].steps[0]["measurements"] if not runner.reports.is_empty() else {}
	_done(runner)
	if not measured.has("final_hash"):
		return "the step measured no final hash: %s" % measured
	var text: String = SeedLevel.read_text(SUITE_PATH)
	var pattern: RegEx = RegEx.create_from_string("(\"id\": \"%s\"[^}]*?\"expected_hash\": )-?\\d+" % STEP_ID)
	if pattern.search(text) == null:
		return "m4.json step %s has no expected_hash; nothing recorded" % STEP_ID
	text = pattern.sub(text, "${1}" + str(measured["final_hash"]))
	var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path(SUITE_PATH), FileAccess.WRITE)
	if file == null:
		return "could not write %s" % SUITE_PATH
	file.store_string(text)
	file.close()
	print("Meltdown: recorded %s final hash %d, outcome %s" % [STEP_ID, measured["final_hash"],
		measured.get("outcome", "?")])
	return ""


func test_the_step_flies_fitted_start_s_ship_on_run_advances_inputs() -> String:
	var found: AcceptanceStep = step()
	var fitted: AcceptanceStep = step("fitted_start")
	var plain: AcceptanceStep = step(PLAIN_ID)
	if found == null or fitted == null or plain == null:
		return "m4 lacks %s, fitted_start or %s" % [STEP_ID, PLAIN_ID]
	if found.run_seed != plain.run_seed or found.replay_path != plain.replay_path:
		return "the step flies run %d by %s" % [found.run_seed, found.replay_path]
	if found.profile_path != fitted.profile_path or found.fitting_path != fitted.fitting_path:
		return "the step reads %s and %s, not fitted_start's stores" % [found.profile_path, found.fitting_path]
	for check: String in [AcceptanceStep.CHECK_FINAL_HASH, AcceptanceStep.CHECK_OUTCOME,
			AcceptanceStep.CHECK_NO_SCRIPT_ERRORS]:
		if not found.has_check(check):
			return "the step does not check %s" % check
	if found.expected_hash == plain.expected_hash:
		return "the fitted flight pins the plain flight's final hash %d" % plain.expected_hash
	return ""


## Both ships on the same replay, each as the headset flies it: each passes its
## pinned hash and outcome, the hashes differ, and the fitted ship ends with at
## least the plain ship's shield (lattice shield and two shield technicians).
func test_the_fitted_flight_differs_from_the_plain_one() -> String:
	var flown: Array[Dictionary] = []
	for flying: AcceptanceStep in [step(), plain_step()]:
		var runner: AcceptanceRunner = _run(flying)
		if runner.exit_code != AcceptanceRunner.EXIT_PASS or not runner.reports[0].passed():
			var problem: String = "%s (%s): exit %d: %s" % [flying.id,
				"fitted" if flying.profile_path != "" else "plain", runner.exit_code, "\n".join(runner.messages)]
			_done(runner)
			return problem
		var session: LocalSession = runner.main.get("session")
		flown.append({"hash": session.sim.state_hash(), "shield": session.sim.ships[0].shield,
			"outcome": session.sim.outcome()})
		_done(runner)
	var fitted: Dictionary = flown[0]
	var plain: Dictionary = flown[1]
	print("  fitted: hash %d shield %.2f outcome %d; plain: hash %d shield %.2f outcome %d" % [
		fitted["hash"], fitted["shield"], fitted["outcome"], plain["hash"], plain["shield"], plain["outcome"]])
	if fitted["hash"] == plain["hash"]:
		return "the fitted and plain flights both end on hash %d" % plain["hash"]
	if float(fitted["shield"]) < float(plain["shield"]):
		return "the fitted ship ends with shield %.2f, below the plain ship's %.2f" % [fitted["shield"],
			plain["shield"]]
	return ""


func _on_quit(code: int) -> void:
	_quit_codes.append(code)


func _run(flying: AcceptanceStep) -> AcceptanceRunner:
	_quit_codes.clear()
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	var kept: Array[AcceptanceStep] = [flying]
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
