extends RefCounted

## The `crew_bonus` check (#1386, CRW-1, CRW-3, SLV-3, ARC-2, MP-2, DEV-6),
## lane-b's file under `acceptance/checks/`. On a run step whose replay
## destroys the reactor:
##
##     {"id": "crew_bonus", "run": 12345, "replay": "res://...",
##      "checks": ["outcome", "no_script_errors", "crew_bonus"]}
##
## The scene's own run has no crew, so its session must fly without a bonus
## and its replay must carry no crew line: every pinned hash stands. The check
## then puts a Cargo Rigger and a Reactor Hand in the run's roster for a
## moment and asks the scene's `LevelStart` for the run level's rules, the
## path the game takes, and flies the step's replay on two sessions of its
## own, one with that roster and one with none. With the roster the hold must
## take one more part and the countdown must start five seconds longer, from
## the shipped roles file; the replay of the crewed flight must fly back to
## its hash. The scene's run, profile and session are left as they were.

const CHECK: String = "crew_bonus"
const ROSTER: Array[String] = ["cargo_rigger", "reactor_hand"]


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	var main: Node = runner.main if runner != null else null
	if main == null:
		return [AcceptanceReport.RESULT_FAIL, "no main scene"]
	var level_start: LevelStart = main.get("level_start") as LevelStart
	var session: LocalSession = main.get("session") as LocalSession
	if level_start == null or session == null:
		return [AcceptanceReport.RESULT_FAIL, "the scene has no level start or session"]
	return judge(level_start, session, Replay.load_file(step.replay_path), measurements)


## The verdict for the scene's `level_start` and session, flying `inputs` again.
static func judge(level_start: LevelStart, session: LocalSession, inputs: Replay,
		measurements: Dictionary) -> Array:
	var run: RunWiring = level_start.run
	if run == null or not run.active():
		return [AcceptanceReport.RESULT_FAIL, "the step flies no run; crew_bonus needs a run step"]
	if inputs.error != "":
		return [AcceptanceReport.RESULT_FAIL, "the step's replay: %s" % inputs.error]
	if not run.profile.crew.is_empty() or session.sim.crew != null or session.replay.crew != null:
		return [AcceptanceReport.RESULT_FAIL, "the scene's run has crew %s; the check needs none" % [run.profile.crew]]
	var plain: LocalSession = _fly(level_start, [], inputs)
	var crewed: LocalSession = _fly(level_start, ROSTER, inputs)
	if plain == null or crewed == null:
		return [AcceptanceReport.RESULT_FAIL, "no session for the run's level"]
	var expected: CrewBonus = CrewBenefits.bonus(_totals(run.roles, ROSTER))
	var hold: int = crewed.sim.ships[0].hold_capacity
	var countdown: Array[int] = [plain.get_meta(CHECK, -1), crewed.get_meta(CHECK, -1)]
	measurements["hold_plain"] = plain.sim.ships[0].hold_capacity
	measurements["hold_crewed"] = hold
	measurements["countdown_plain_ticks"] = countdown[0]
	measurements["countdown_crewed_ticks"] = countdown[1]
	if expected.hold_slots < 1 or expected.meltdown_seconds < 1:
		return [AcceptanceReport.RESULT_FAIL, "the shipped roles give %s for %s" % [expected.to_json(), ROSTER]]
	if plain.sim.crew != null or plain.sim.ships[0].hold_capacity != ShipState.HOLD_CAPACITY:
		return [AcceptanceReport.RESULT_FAIL, "a run without crew flew with a bonus"]
	if hold != ShipState.HOLD_CAPACITY + expected.hold_slots:
		return [AcceptanceReport.RESULT_FAIL, "with %s the hold takes %d parts, expected %d" % [
			ROSTER, hold, ShipState.HOLD_CAPACITY + expected.hold_slots]]
	if countdown[0] < 1 or countdown[1] != countdown[0] + expected.meltdown_seconds * ReactorState.TICKS_PER_SECOND:
		return [AcceptanceReport.RESULT_FAIL, "the countdown started at %d ticks with %s and %d without" % [
			countdown[1], ROSTER, countdown[0]]]
	var again: Replay = Replay.from_text(crewed.replay.to_text())
	var replayed: Sim = again.run() if again.error == "" else null
	if replayed == null or again.crew == null or replayed.state_hash() != crewed.sim.state_hash():
		return [AcceptanceReport.RESULT_FAIL, "the crewed flight's replay does not fly back to its hash"]
	return [AcceptanceReport.RESULT_PASS, "with %s: hold %d parts (1 without), countdown %d ticks (%d without); replay reproduces" % [
		ROSTER, hold, countdown[1], countdown[0]]]


## The run level flown with `inputs` and `roster` in the run's profile while
## `LevelStart` reads its rules and ship, with drops, rescue and the alarm on
## as in the game. The countdown at the reactor's death is kept as metadata.
static func _fly(level_start: LevelStart, roster: Array[String], inputs: Replay) -> LocalSession:
	var run: RunWiring = level_start.run
	var kept_profile: Profile = run.profile
	var kept_rules: bool = run.level_rules
	run.profile = _profile(roster)
	run.level_rules = true
	var path: String = run.level_source()
	var world: Node3D = Node3D.new()
	var session: LocalSession = LevelStart.level_session(world, path, ReplayInputSource.new(inputs),
		level_start.run_rules(path), level_start.run_tuning(path))
	world.free()
	run.profile = kept_profile
	run.level_rules = kept_rules
	if session == null or session.sim.reactor == null:
		return null
	while session.sim.tick < inputs.frames.size():
		var was_destroyed: bool = session.sim.reactor.destroyed
		session.advance(ShipState.TICK_DT)
		if not was_destroyed and session.sim.reactor.destroyed:
			session.set_meta(CHECK, session.sim.reactor.meltdown_ticks_left)
	return session


static func _profile(roster: Array[String]) -> Profile:
	var profile: Profile = Profile.new()
	for i: int in roster.size():
		profile.crew.append({Profile.CREW_ID: "check_%d" % i, Profile.CREW_ROLE: roster[i]})
	return profile


static func _totals(roles: CrewRoles, roster: Array[String]) -> Dictionary:
	return CrewBenefits.totals(_profile(roster), roles)
