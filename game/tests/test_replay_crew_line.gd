extends RefCounted

## A replay's crew line and a run level with crew (#1386, CRW-1, ARC-2, MP-2):
## the line round-trips, a replay without crew is written as before, a bad
## line is refused, a replay with crew reproduces its hash, and a run whose
## roster holds a Cargo Rigger and a Reactor Hand flies its level with the
## larger hold and the longer countdown, recorded in the replay.

const PLAIN_REPLAY: String = "res://acceptance/replays/bot_g2_escape.replay"
const LINE: String = "crew {\"hold_slots\":2,\"meltdown_seconds\":20}"
const RUN_SEED: int = 12345


func _text(version: int, extra: String) -> String:
	return "meltdown-replay %d\nseed 1\nships 1\n%sinputs\n0 0 0 0 0 0 0 0 0 0\n" % [version, extra]


func _run(crew_roles: Array[String]) -> RunWiring:
	var run: RunWiring = RunWiring.new(RUN_SEED, null, func() -> int: return 77, "", false)
	for i: int in crew_roles.size():
		run.profile.crew.append({Profile.CREW_ID: "crew-%d" % (i + 1), Profile.CREW_ROLE: crew_roles[i]})
	return run


func _session(run: RunWiring) -> LocalSession:
	var level_start: LevelStart = LevelStart.new()
	level_start.run = run
	var world: Node3D = Node3D.new()
	var session: LocalSession = level_start.session_for(world, run.level_source(), null)
	world.free()
	return session


func test_the_line_round_trips() -> String:
	var replay: Replay = Replay.from_text(_text(21, LINE + "\n"))
	if replay.error != "":
		return replay.error
	if replay.crew == null or replay.crew.hold_slots != 2 or replay.crew.meltdown_seconds != 20:
		return "the line read as %s" % [replay.crew]
	var text: String = replay.to_text()
	if not text.begins_with("meltdown-replay 21\n") or not text.contains("\n" + LINE + "\n"):
		return "written back as:\n%s" % text
	var sim: Sim = replay.run()
	if sim == null or sim.crew == null or sim.ships[0].hold_capacity != 3:
		return "the run flew without the replay's crew"
	return ""


func test_a_replay_without_crew_keeps_its_version() -> String:
	var replay: Replay = Replay.load_file(PLAIN_REPLAY)
	if replay.error != "" or replay.crew != null:
		return "the plain replay: '%s'" % replay.error
	replay.crew = CrewBonus.of(0, 0)
	var text: String = replay.to_text()
	if not text.begins_with("meltdown-replay 17\n") or text.contains("\ncrew "):
		return "a zero crew was written"
	return ""


func test_bad_lines_are_refused() -> String:
	var cases: Dictionary = {
		_text(20, LINE + "\n"): "line 4: a crew line needs format version 21 or later",
		_text(21, LINE + "\n" + LINE + "\n"): "line 5: 'crew' appears twice",
		_text(21, "crew {\"hold_slots\":2}\n"): "line 4: crew: key \"meltdown_seconds\" must be a whole number",
		_text(21, "crew {\"hold_slots\":99,\"meltdown_seconds\":0}\n"): "line 4: crew: key \"hold_slots\" must be 0 to 16",
	}
	for text: String in cases:
		var replay: Replay = Replay.from_text(text)
		if replay.error != cases[text]:
			return "%s: got '%s'" % [text.c_escape(), replay.error]
	return ""


func test_the_pinned_replay_keeps_its_hash_and_crew_reproduces() -> String:
	var plain: Replay = Replay.load_file(PLAIN_REPLAY)
	if plain.run().state_hash() != plain.expected_hash:
		return "the pinned replay moved"
	var with_crew: Replay = Replay.load_file(PLAIN_REPLAY)
	with_crew.crew = CrewBonus.of(1, 5)
	var again: Replay = Replay.from_text(with_crew.to_text())
	if again.error != "":
		return again.error
	var first: Sim = with_crew.run()
	var second: Sim = again.run()
	if first.state_hash() != second.state_hash():
		return "a replay with crew did not reproduce after a save"
	if first.state_hash() == plain.expected_hash:
		return "the crew is not in the hash"
	return ""


func test_a_run_with_a_rigger_and_a_reactor_hand_flies_with_both() -> String:
	var session: LocalSession = _session(_run(["cargo_rigger", "reactor_hand"]))
	if session == null or session.sim.reactor == null:
		return "the run's level has no session or no reactor"
	if session.sim.ships[0].hold_capacity != ShipState.HOLD_CAPACITY + 1:
		return "hold %d" % session.sim.ships[0].hold_capacity
	var level_ticks: int = LevelSwitch.load_level(_run([]).level_source()).reactor.meltdown_ticks()
	if session.sim.reactor.meltdown_ticks() != level_ticks + 5 * ReactorState.TICKS_PER_SECOND:
		return "countdown %d ticks, the level's is %d" % [session.sim.reactor.meltdown_ticks(), level_ticks]
	if session.replay.crew == null or session.replay.crew.to_json() != CrewBonus.of(1, 5).to_json():
		return "the replay does not record the crew"
	return ""


func test_a_run_without_those_roles_adds_nothing() -> String:
	var session: LocalSession = _session(_run(["shield_tech"]))
	if session.sim.crew != null or session.replay.crew != null \
			or session.sim.ships[0].hold_capacity != ShipState.HOLD_CAPACITY:
		return "a crew without riggers or hands changed the sim"
	var off: RunWiring = _run(["cargo_rigger"])
	off.level_rules = false
	if _session(off).sim.crew != null:
		return "level_rules false still installs the crew"
	return ""
