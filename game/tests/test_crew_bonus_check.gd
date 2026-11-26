extends RefCounted

## The m6 `crew_bonus` acceptance check (#1386, DEV-6) refuses a step that
## flies no run and a run that already has crew, and leaves the scene's run
## as it found it. The passing flight is the m6 suite's `crew_bonus` step.

const CHECK_FILE: String = "res://acceptance/checks/crew_bonus_check.gd"
const REPLAY: String = "res://acceptance/replays/run_advances.replay"


func _check() -> GDScript:
	return load(CHECK_FILE) as GDScript


func _level_start(run: RunWiring) -> LevelStart:
	var level_start: LevelStart = LevelStart.new()
	level_start.run = run
	return level_start


func _run() -> RunWiring:
	return RunWiring.new(12345, null, func() -> int: return 77, "", false)


func test_a_step_without_a_run_fails() -> String:
	var verdict: Array = _check().judge(_level_start(null), LocalSession.new(), Replay.load_file(REPLAY), {})
	if verdict[0] != AcceptanceReport.RESULT_FAIL or not str(verdict[1]).contains("needs a run step"):
		return "verdict %s" % [verdict]
	return ""


func test_a_run_with_crew_fails_and_is_left_as_it_was() -> String:
	var run: RunWiring = _run()
	run.profile.crew.append({Profile.CREW_ID: "c1", Profile.CREW_ROLE: "cargo_rigger"})
	var verdict: Array = _check().judge(_level_start(run), LocalSession.new(), Replay.load_file(REPLAY), {})
	if verdict[0] != AcceptanceReport.RESULT_FAIL or not str(verdict[1]).contains("the check needs none"):
		return "verdict %s" % [verdict]
	if run.profile.crew.size() != 1 or not run.level_rules:
		return "the check changed the scene's run"
	return ""


func test_a_flight_leaves_the_runs_profile_and_rules() -> String:
	var run: RunWiring = _run()
	run.level_rules = false
	var kept: Profile = run.profile
	var roster: Array[String] = ["cargo_rigger"]
	var session: LocalSession = _check()._fly(_level_start(run), roster, Replay.new())
	if run.profile != kept or run.level_rules or not kept.crew.is_empty():
		return "the flight changed the scene's run"
	if session == null or session.sim.ships[0].hold_capacity != ShipState.HOLD_CAPACITY + 1:
		return "the probe flew without the roster's hold"
	return ""
