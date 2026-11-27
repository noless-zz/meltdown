extends RefCounted

## Run 12345's first level flown by the plain ship on the `run_advances`
## replay, once, and what it ended on shared by every m4 test that compares
## against it (#1483, DEV-3). `test_m4_fitted_flight_step.gd` and
## `test_m4_aim_assist_step.gd` each flew this flight for their comparison, and
## `test_m4_components_bank_step.gd` flew `run_advances`, the same flight with
## two more checks, to see the rules stay off: three flights of about ten
## seconds each on CI where one gives the same answers (ARC-2), as
## `m3_suite_run.gd` does for the m3 suite (#1139).
##
## Only tests read this. The step is flown alone in a fresh main scene, as the
## headset flies it, and judged against `run_advances`' pinned hash and outcome.

const SUITE_PATH: String = "res://acceptance/suites/m4.json"
## The step whose stores are dropped; its replay and run are `run_advances`'.
const FROM_ID: String = "fitted_flight"
const PLAIN_ID: String = "run_advances"
## The replay takes about 7,200 ticks; the runner flies one per frame.
const FRAME_LIMIT: int = 20000

static var _flown: bool = false
static var _problem: String = ""
static var _measured: Dictionary = {}


static func _step(step_id: String) -> AcceptanceStep:
	for found: AcceptanceStep in AcceptanceSuite.load_file(SUITE_PATH).steps:
		if found.id == step_id:
			return found
	return null


## `fitted_flight` with its scratch stores dropped: the plain ship on the same
## replay, judged against `run_advances`' pinned final hash and outcome.
static func step() -> AcceptanceStep:
	var plain: AcceptanceStep = _step(FROM_ID)
	var pinned: AcceptanceStep = _step(PLAIN_ID)
	plain.profile_path = ""
	plain.fitting_path = ""
	plain.expected_hash = pinned.expected_hash
	plain.expected_outcome = pinned.expected_outcome
	return plain


## "" when the flight passed every check of its step; otherwise why not.
static func problem() -> String:
	_fly()
	return _problem


## Where the flight ended: "hash", "shield", "outcome" (an `ExitRule.Outcome`),
## "hits" (ROBOT_HIT events, read once per tick), "level_rules" and "banked"
## (the run's rules switch and its profile's bank). A copy.
static func measured() -> Dictionary:
	_fly()
	return _measured.duplicate(true)


static func _fly() -> void:
	if _flown:
		return
	_flown = true
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	var kept: Array[AcceptanceStep] = [step()]
	suite.steps = kept
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = func(_code: int) -> void: pass
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	runner.setup(main, [suite] as Array[AcceptanceSuite], null)
	var hits: int = 0
	var seen_session: LocalSession = null
	var seen_tick: int = -1
	var frames: int = 0
	while not runner.finished and frames < FRAME_LIMIT:
		runner.process_frame()
		frames += 1
		# A frame without a tick leaves the last tick's events in place.
		var session: LocalSession = main.get("session")
		if session == null or (session == seen_session and session.sim.tick == seen_tick):
			continue
		seen_session = session
		seen_tick = session.sim.tick
		for event: SimEvent in session.sim.last_events:
			if event.kind == SimEvent.Kind.ROBOT_HIT:
				hits += 1
	if runner.exit_code != AcceptanceRunner.EXIT_PASS or runner.reports.is_empty() \
			or not runner.reports[0].passed():
		_problem = "plain flight: exit %d: %s" % [runner.exit_code, "\n".join(runner.messages)]
	else:
		var flown: LocalSession = main.get("session")
		var run: RunWiring = (main.get("level_start") as LevelStart).run
		_measured = {"hash": flown.sim.state_hash(), "shield": flown.sim.ships[0].shield,
				"outcome": flown.sim.outcome(), "hits": hits, "level_rules": run.level_rules,
				"banked": run.profile.banked.duplicate(true)}
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	if runner.main != null:
		runner.main.free()
	runner.free()
