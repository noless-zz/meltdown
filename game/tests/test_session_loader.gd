extends RefCounted

## `SessionLoader` builds sessions from data without the local tick, so the host
## and dedicated server can use it (MP-3, ARC-4, #1156). Moving the loaders out
## of `LocalSession` must not change a session: these compare the two paths.

const RUN_SEED: int = 12345
const IDLE_TICKS: int = 60


func _level_one() -> LevelDef:
	return SeedLevel.load_level(AcceptanceRunStep.plan_for(RUN_SEED).level_seed(0))


func _idle(session: LocalSession) -> void:
	for i: int in IDLE_TICKS:
		session.advance(ShipState.TICK_DT)


func test_for_level_matches_local_session_after_idle_ticks() -> String:
	var level: LevelDef = _level_one()
	if level == null:
		return "run %d's level 1 did not load" % RUN_SEED
	var loaded: LocalSession = SessionLoader.for_level(level, RUN_SEED)
	var local: LocalSession = LocalSession.for_level(_level_one(), RUN_SEED)
	if loaded.sim.robots.is_empty():
		return "run %d's level 1 has no robots, so the check proves little" % RUN_SEED
	if loaded.sim.state_hash() != local.sim.state_hash():
		return "start hashes differ: %d against %d" % [loaded.sim.state_hash(), local.sim.state_hash()]
	_idle(loaded)
	_idle(local)
	if loaded.sim.tick != IDLE_TICKS:
		return "the loaded session ran %d ticks, wanted %d" % [loaded.sim.tick, IDLE_TICKS]
	if loaded.sim.state_hash() != local.sim.state_hash():
		return "hashes after %d idle ticks differ: %d against %d" % [IDLE_TICKS,
			loaded.sim.state_hash(), local.sim.state_hash()]
	if loaded.replay.to_text() != local.replay.to_text():
		return "the two sessions recorded different replays"
	return ""


func test_build_gives_the_session_its_replay_and_armed_sim() -> String:
	var tuning: ShipTuning = LocalSession.load_tuning("res://data/ships/default_ship.json")
	if tuning == null:
		return "the default ship file did not load"
	var session: LocalSession = LocalSession.new(RUN_SEED, null, null, tuning, [], null,
		LocalSession.load_parts())
	var rebuilt: LocalSession = LocalSession.new(0)
	SessionLoader.build(rebuilt, RUN_SEED, null, tuning, [], null, LocalSession.load_parts())
	if rebuilt.replay == null or rebuilt.sim == null:
		return "build left the session without a replay or sim"
	if rebuilt.replay.run_seed != RUN_SEED:
		return "the replay's run seed is %d" % rebuilt.replay.run_seed
	if rebuilt.replay.parts.is_empty():
		return "the part catalogue was not recorded"
	if rebuilt.sim.state_hash() != session.sim.state_hash():
		return "build gave hash %d, the constructor %d" % [rebuilt.sim.state_hash(),
			session.sim.state_hash()]
	return ""
