extends RefCounted

## Run levels drop components and let miners be rescued (#1028, CRF-1, CRF-2,
## SLV-3, ARC-2): a session for the level a run flies gets both rule sets from
## the data files, a level flown alone gets neither, a broken file leaves its
## feature off, the escape banks what the sim collected, and the replay of a
## run level flies back to the same hash.

const RUN_SEED: int = 12345
const REPLAY_PATH: String = "res://acceptance/replays/run_advances.replay"
const PROFILE_PATH: String = "user://t1028_profile.json"
const SCRATCH_DIR: String = "user://t1028_components"
const BAD_RESCUE: String = "user://t1028_rescue.json"

## The run-level flight of `REPLAY_PATH`, flown once and shared.
var _flown: LocalSession = null


## A run with no shaft choice, kept in memory unless `store` is given.
func _run(store: ProfileStore = null) -> RunWiring:
	return RunWiring.new(RUN_SEED, store, func() -> int: return 77, "", false)


## A session for `path` as `LevelStart` builds it with `run` (or none).
func _session(run: RunWiring, path: String, input: ShipInputSource = null) -> LocalSession:
	var level_start: LevelStart = LevelStart.new()
	level_start.run = run
	var world: Node3D = Node3D.new()
	var session: LocalSession = level_start.session_for(world, path, input)
	world.free()
	return session


## Level 1 of run 12345 flown as the game flies it, with the bot pilot's escape
## inputs from the m4 suite's replay.
func _flight() -> LocalSession:
	if _flown != null:
		return _flown
	var inputs: Replay = Replay.load_file(REPLAY_PATH)
	var run: RunWiring = _run()
	_flown = _session(run, run.level_source(), ReplayInputSource.new(inputs))
	while _flown.sim.tick < inputs.frames.size():
		_flown.advance(ShipState.TICK_DT)
	return _flown


func test_a_run_level_session_has_both_rule_sets() -> String:
	var run: RunWiring = _run()
	var session: LocalSession = _session(run, run.level_source())
	if session == null or session.sim.component_rules == null or session.sim.rescue == null:
		return "the run's level flies without drops or rescue"
	var level: LevelDef = LevelSwitch.load_level(run.level_source())
	if session.sim.rescue.trapped != level.miners or level.miners.is_empty():
		return "trapped %s, the level has %s" % [session.sim.rescue.trapped, level.miners]
	if session.replay.component_rules == null or session.replay.rescue_rules == null \
			or session.replay.miners != level.miners:
		return "the replay does not record the rules"
	return ""


func test_a_level_flown_alone_has_neither() -> String:
	var run: RunWiring = _run()
	var alone: LocalSession = _session(null, run.level_source())
	if alone.sim.component_rules != null or alone.sim.rescue != null:
		return "a lone --seed session has rules"
	if not alone.replay.to_text().begins_with("meltdown-replay 17\n"):
		return "a lone session's replay is not written as version 17"
	var other: LocalSession = _session(run, LevelSwitch.SEED_PREFIX + "31")
	if other.sim.component_rules != null or other.sim.rescue != null:
		return "a seed the run is not flying got rules"
	run.level_rules = false
	var off: LocalSession = _session(run, run.level_source())
	if off.sim.component_rules != null or off.sim.rescue != null:
		return "level_rules false still installs rules"
	return ""


func test_a_robot_kill_drops_a_component_the_ship_collects() -> String:
	var session: LocalSession = _flight()
	if session.sim.outcome() != ExitRule.Outcome.ESCAPED:
		return "the flight ended %d, not escaped" % session.sim.outcome()
	if session.sim.collected.get("cell_salts", 0) != 1:
		return "collected %s, expected one cell_salts" % session.sim.collected
	return ""


func test_the_escape_banks_the_collected_component() -> String:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))
	var store: ProfileStore = ProfileStore.new(PROFILE_PATH)
	var run: RunWiring = _run(store)
	var next: String = run.after_session(_flight())
	var saved: Profile = ProfileStore.new(PROFILE_PATH).load_profile()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))
	if next != LevelSwitch.SEED_PREFIX + str(run.state.plan.level_seed(1)):
		return "the run flies %s next" % next
	if run.profile.count_of("cell_salts") != 1 or saved.count_of("cell_salts") != 1:
		return "banked %s, saved %s" % [run.profile.banked, saved.banked]
	return ""


func test_a_recorded_run_level_replays_to_the_same_hash() -> String:
	var session: LocalSession = _flight()
	var text: String = session.replay.to_text()
	# Version 20 since the run level's alarm joined it (#1342).
	if not text.begins_with("meltdown-replay 20\n") or not text.contains("\ncomponents ") \
			or not text.contains("\nrescue ") or not text.contains("\"components\":[{"):
		return "the replay does not carry the rules and drop tables"
	var replay: Replay = Replay.from_text(text)
	if replay.error != "":
		return replay.error
	var sim: Sim = replay.run()
	if sim == null or sim.state_hash() != session.sim.state_hash():
		return "the replay ends on %s, the flight on %d" % [
			"nothing" if sim == null else str(sim.state_hash()), session.sim.state_hash()]
	if sim.collected != session.sim.collected:
		return "the replay collected %s" % sim.collected
	return ""


func test_a_ship_held_at_a_miner_rescues_it() -> String:
	var run: RunWiring = _run()
	var session: LocalSession = _session(run, run.level_source())
	var miner: Vector3i = session.sim.rescue.trapped[0]
	# Placed before the first tick, as a start pose would be.
	session.sim.ships[0].position = MinerRescue.position_of(miner)
	session.sim.ships[0].velocity = Vector3.ZERO
	for _tick: int in session.sim.rescue.hold_ticks() + 1:
		session.advance(ShipState.TICK_DT)
	if session.sim.rescue.rescued != 1:
		return "rescued %d after holding at the miner" % session.sim.rescue.rescued
	return ""


func test_a_replay_without_the_lines_flies_as_before() -> String:
	var inputs: Replay = Replay.load_file(REPLAY_PATH)
	var level: LevelDef = LevelSwitch.load_level(_run().level_source())
	var session: LocalSession = LocalSession.for_level(level, inputs.run_seed, null,
		LocalSession.load_tuning(LevelStart.SHIP_TUNING_PATH))
	var replay: Replay = Replay.from_text(session.replay.to_text())
	replay.frames = inputs.frames
	var sim: Sim = replay.run()
	if replay.component_rules != null or replay.rescue_rules != null or sim.component_rules != null:
		return "a replay without the lines flew with rules"
	if sim.state_hash() != inputs.expected_hash:
		return "hash %d, pinned %d" % [sim.state_hash(), inputs.expected_hash]
	return ""


func test_shipped_replays_have_no_rules_and_stay_version_17() -> String:
	var dir: String = "res://acceptance/replays"
	for file: String in DirAccess.get_files_at(dir):
		if not file.ends_with(".replay"):
			continue
		var replay: Replay = Replay.load_file(dir.path_join(file))
		if replay.error != "":
			return "%s: %s" % [file, replay.error]
		if replay.component_rules != null or replay.rescue_rules != null:
			return "%s carries rules" % file
		# An alarm line alone (#1342) needs version 20; the shipped alarm replay has one.
		if replay.alarm_rules == null and ReplayRulesLine.format_version(replay) != 17:
			return "%s would be written as version %d" % [file, ReplayRulesLine.format_version(replay)]
	return ""


func test_a_rejected_file_turns_its_feature_off() -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCRATCH_DIR))
	var pickup: FileAccess = FileAccess.open(SCRATCH_DIR.path_join("pickup.json"), FileAccess.WRITE)
	pickup.store_string("{\"pickup_reach\": 2.5, \"magnet\": 1}")
	pickup.close()
	var rescue: FileAccess = FileAccess.open(BAD_RESCUE, FileAccess.WRITE)
	rescue.store_string("{\"rescue_reach\": 4.0}")
	rescue.close()
	var rules: RunLevelRules = RunLevelRules.load_files(SCRATCH_DIR, BAD_RESCUE)
	var no_pickup: ComponentPickup = RunLevelRules.read_components("user://t1028_missing")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_DIR.path_join("pickup.json")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_DIR))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BAD_RESCUE))
	if rules.components != null or rules.rescue != null or no_pickup != null:
		return "a rejected or missing file still gave rules"
	var shipped: RunLevelRules = RunLevelRules.load_files()
	if shipped.components == null or shipped.rescue == null:
		return "the shipped files were rejected"
	var run: RunWiring = _run()
	var level: LevelDef = LevelSwitch.load_level(run.level_source())
	var session: LocalSession = LocalSession.for_level(level)
	rules.install(session, level)
	if session.sim.component_rules != null or session.sim.rescue != null or session.replay.component_rules != null:
		return "rules with both features off installed something"
	session.advance(ShipState.TICK_DT)
	return "" if session.sim.tick == 1 else "the level did not fly"
