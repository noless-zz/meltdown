extends RefCounted

## A run's level flies with the alarm on, rising by the chosen shaft's
## `risk.alarm` (#1342, RUN-6, RUN-1); a level flown alone has none, and the
## music reads the session's copy of the level (AUD-3).

const RUN_SEED: int = 12345
## Two shafts, both always offered: steady at alarm 1.0, loud at 1.5.
const SHAFTS: String = "{\"offer_min\": 2, \"offer_max\": 2, \"seed_salt\": 2246822519, \"shafts\": [" \
	+ "{\"kind\": \"steady\", \"label\": \"Steady\", \"risk\": {\"robot_count\": 1.0, \"alarm\": 1.0}, " \
	+ "\"reward\": {\"tier_weights\": [6, 3, 1]}}, " \
	+ "{\"kind\": \"loud\", \"label\": \"Loud\", \"risk\": {\"robot_count\": 1.0, \"alarm\": 1.5}, " \
	+ "\"reward\": {\"tier_weights\": [3, 4, 3]}}]}"


func _wiring(with_shafts: bool = false) -> RunWiring:
	return RunWiring.new(RUN_SEED, null, func() -> int: return 77, "", with_shafts, SHAFTS if with_shafts else "")


## A session for `path` as `LevelStart` builds it with `run` (or none).
func _session(run: RunWiring, path: String) -> LocalSession:
	var level_start: LevelStart = LevelStart.new()
	level_start.run = run
	var world: Node3D = Node3D.new()
	var session: LocalSession = level_start.session_for(world, path, null)
	world.free()
	return session


func test_a_run_level_has_the_alarm_and_its_replay_records_it() -> String:
	var run: RunWiring = _wiring()
	var session: LocalSession = _session(run, run.level_source())
	if session == null or session.sim.alarm == null:
		return "the run's level flies without an alarm"
	if session.sim.alarm.risk != 1.0 or run.level_alarm_scale() != 1.0:
		return "level 1 rises by %s" % session.sim.alarm.risk
	if session.replay.alarm_rules == null or not session.replay.to_text().contains("\nalarm {"):
		return "the replay does not record the alarm"
	return ""


func test_a_level_flown_alone_has_no_alarm_and_calm_music() -> String:
	var alone: LocalSession = _session(null, _wiring().level_source())
	if alone.sim.alarm != null or alone.replay.alarm_rules != null:
		return "a lone --seed session has an alarm"
	for tick: int in 60:
		alone.advance(ShipState.TICK_DT)
	return "" if MusicWiring.alarm_level(alone) == 0.0 else "a lone level's music heard an alarm"


func test_the_music_reads_the_rising_level() -> String:
	var run: RunWiring = _wiring()
	var session: LocalSession = _session(run, run.level_source())
	for tick: int in 120:
		session.advance(ShipState.TICK_DT)
	var heard: float = MusicWiring.alarm_level(session)
	if heard <= 0.0 or heard != session.sim.alarm.level:
		return "the music heard %f, the core holds %f" % [heard, session.sim.alarm.level]
	return ""


func test_the_chosen_shaft_scales_the_alarm() -> String:
	var run: RunWiring = _wiring(true)
	if run.shafts == null or run.escape_for_choice({}).is_empty() or not run.choose("loud"):
		return "the run did not take the loud shaft"
	if run.level_alarm_scale() != 1.5:
		return "after loud the alarm scale is %s" % run.level_alarm_scale()
	var session: LocalSession = _session(run, run.level_source())
	if session == null or session.sim.alarm == null or session.sim.alarm.risk != 1.5:
		return "the loud shaft's level does not rise by 1.5"
	var risk: float = session.replay.alarm_rules.risk
	return "" if risk == 1.5 else "the replay records risk %s" % risk


func test_a_rejected_alarm_file_turns_it_off() -> String:
	var path: String = "user://t1342_alarm.json"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{\"rise_per_second\": 0.01}")
	file.close()
	var rules: RunLevelRules = RunLevelRules.load_files(RunLevelRules.COMPONENTS_DIR,
		RunLevelRules.RESCUE_FILE, [], path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if rules.alarm != null:
		return "a rejected alarm file still gave rules"
	return "" if RunLevelRules.load_files().alarm != null else "the shipped alarm file was rejected"
