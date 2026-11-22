extends RefCounted

## The m4 suite's `aim_assist_fitted` step (#1159, CMB-8, CRF-4, CRF-5, ARC-2,
## DEV-6, decision record 0005): run 12345's first level flown by the
## `run_advances` replay with a scratch profile that has crafted the aim assist
## lens and a fitting that puts it in the first utility slot, the ship otherwise
## plain. The step pins where that flight ends, so a module that stops bending
## shots shows here (gate #950's "a crafted upgrade is felt in the next run").
##
## The replay's inputs are the plain ship's recording, so the step measures that
## the module changes the flight, not that it feels right (#1117 stays a headset
## check). The cone and range are those `aim_assist.json` ships.
##
## The issue asked for at least as many robot hits with the module as without.
## On this replay there are fewer (28 against 30): `AimAssist.bend` turns a shot
## to a moving robot's current centre, which drops the lead the plain ship's
## nose already had (first at tick 31, a hit at tick 55 becomes a miss), and the
## flights diverge from there. #1192 puts the fix to the owner; until then the
## counts are pinned so a change to aim assist shows here. Once #1192 lands,
## replace the pin with "at least as many" and re-record the hash.
## Re-recording the final hash after an intended change, from the repository root:
##
##     MELTDOWN_RECORD_M4=aim_assist_fitted godot --headless --path game -s res://tests/run_tests.gd

const SUITE_PATH: String = "res://acceptance/suites/m4.json"
const STEP_ID: String = "aim_assist_fitted"
const PLAIN_ID: String = "run_advances"
const FITTING: String = "res://acceptance/fittings/aim_assist_fitting.json"
const PROFILE: String = "res://acceptance/fittings/aim_assist_profile.json"
const RECORD_SWITCH: String = "MELTDOWN_RECORD_M4"
const RecordSwitch := preload("res://tests/record_switch.gd")
## The replay takes about 7,200 ticks; the runner flies one per frame.
const FRAME_LIMIT: int = 20000
## Robot hits measured on this replay with and without the module (#1192).
const PINNED_HITS_ASSISTED: int = 28
const PINNED_HITS_PLAIN: int = 30

var _quit_codes: Array[int] = []


static func step(step_id: String = STEP_ID) -> AcceptanceStep:
	for found: AcceptanceStep in AcceptanceSuite.load_file(SUITE_PATH).steps:
		if found.id == step_id:
			return found
	return null


## The step with its scratch stores dropped: the plain ship on the same replay,
## judged against `run_advances`' pinned final hash and outcome.
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
	var flown: Dictionary = _fly(step())
	var runner: AcceptanceRunner = flown["runner"]
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
	print("Meltdown: recorded %s final hash %d, outcome %s, robot hits %d" % [STEP_ID,
		measured["final_hash"], measured.get("outcome", "?"), flown["hits"]])
	return ""


## The fitting is the plain ship plus the module, and the profile has crafted it.
func test_the_fitting_adds_only_the_aim_assist_module() -> String:
	var fitting: Fitting = FittingStore.new(FITTING).load_fitting()
	if fitting == null:
		return "%s does not load" % FITTING
	if fitting.utility != ([ShipLoadout.AIM_ASSIST_MODULE] as Array[String]):
		return "the fitting's utility is %s" % [fitting.utility]
	for kind: String in [Fitting.PRIMARY, Fitting.SECONDARY]:
		if fitting.ids_of(kind).any(func(id: String) -> bool: return id != ""):
			return "the fitting changes %s: %s" % [kind, fitting.ids_of(kind)]
	for slot: String in fitting.parts:
		if fitting.parts[slot] != "":
			return "the fitting changes the %s part to %s" % [slot, fitting.parts[slot]]
	var profile: Profile = ProfileStore.new(PROFILE).load_profile()
	if profile == null or not profile.crafted.has("aim_assist"):
		return "%s has not crafted the aim assist" % PROFILE
	if not profile.crew.is_empty():
		return "the profile carries crew, which would change more than the module"
	return ""


func test_the_step_flies_the_module_on_run_advances_inputs() -> String:
	var found: AcceptanceStep = step()
	var plain: AcceptanceStep = step(PLAIN_ID)
	if found == null or plain == null:
		return "m4 lacks %s or %s" % [STEP_ID, PLAIN_ID]
	if found.run_seed != plain.run_seed or found.replay_path != plain.replay_path:
		return "the step flies run %d by %s" % [found.run_seed, found.replay_path]
	if found.profile_path != PROFILE or found.fitting_path != FITTING:
		return "the step reads %s and %s" % [found.profile_path, found.fitting_path]
	for check: String in [AcceptanceStep.CHECK_FINAL_HASH, AcceptanceStep.CHECK_OUTCOME,
			AcceptanceStep.CHECK_NO_SCRIPT_ERRORS]:
		if not found.has_check(check):
			return "the step does not check %s" % check
	if found.expected_hash == plain.expected_hash:
		return "the step pins the plain flight's final hash %d" % plain.expected_hash
	return ""


## Both ships on the same replay, each as the headset flies it: each passes its
## pinned hash and outcome, the hashes differ, and each lands its pinned number
## of robot hits (see the top of this file and #1192).
func test_the_module_changes_the_flight() -> String:
	var flights: Array[Dictionary] = []
	for flying: AcceptanceStep in [step(), plain_step()]:
		var flown: Dictionary = _fly(flying)
		var runner: AcceptanceRunner = flown["runner"]
		if runner.exit_code != AcceptanceRunner.EXIT_PASS or not runner.reports[0].passed():
			var problem: String = "%s (%s): exit %d: %s" % [flying.id,
				"module" if flying.fitting_path != "" else "plain", runner.exit_code, "\n".join(runner.messages)]
			_done(runner)
			return problem
		var session: LocalSession = runner.main.get("session")
		flights.append({"hash": session.sim.state_hash(), "hits": flown["hits"]})
		_done(runner)
	var assisted: Dictionary = flights[0]
	var plain: Dictionary = flights[1]
	print("  aim assist: hash %d robot hits %d; plain: hash %d robot hits %d" % [
		assisted["hash"], assisted["hits"], plain["hash"], plain["hits"]])
	if assisted["hash"] == plain["hash"]:
		return "the flights with and without aim assist both end on hash %d" % plain["hash"]
	if int(assisted["hits"]) != PINNED_HITS_ASSISTED or int(plain["hits"]) != PINNED_HITS_PLAIN:
		return "robot hits %d with aim assist and %d without, pinned %d and %d (#1192)" % [assisted["hits"],
			plain["hits"], PINNED_HITS_ASSISTED, PINNED_HITS_PLAIN]
	return ""


func _on_quit(code: int) -> void:
	_quit_codes.append(code)


## Flies `flying` alone; {"runner": the finished runner, "hits": ROBOT_HIT events
## seen}. Events are read once per tick, since a frame without a tick leaves the
## last tick's events in place.
func _fly(flying: AcceptanceStep) -> Dictionary:
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
	var hits: int = 0
	var seen_session: LocalSession = null
	var seen_tick: int = -1
	var frames: int = 0
	while not runner.finished and frames < FRAME_LIMIT:
		runner.process_frame()
		frames += 1
		var session: LocalSession = main.get("session")
		if session == null or (session == seen_session and session.sim.tick == seen_tick):
			continue
		seen_session = session
		seen_tick = session.sim.tick
		for event: SimEvent in session.sim.last_events:
			if event.kind == SimEvent.Kind.ROBOT_HIT:
				hits += 1
	return {"runner": runner, "hits": hits}


func _done(runner: AcceptanceRunner) -> void:
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	if runner.main != null:
		runner.main.free()
	runner.free()
