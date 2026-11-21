extends RefCounted

## Flying a run (#989, RUN-1, RUN-3, RUN-7, CRF-2): `--run=<n>` starts run `n`,
## each escape flies the run's next level and banks its components, the last
## escape wins and a loss loses, and either starts a new run. Driven without a
## scene: the wiring is handed outcomes and collected counts.

const RUN: String = "res://data/run/run.json"
const THREE_LEVELS: String = "user://t989_three_level_run.json"
const RUN_SEED: int = 12345
const NEXT_RUN_SEED: int = 777


func _three_level_wiring() -> RunWiring:
	var file: FileAccess = FileAccess.open(THREE_LEVELS, FileAccess.WRITE)
	file.store_string('{"min_levels": 3, "max_levels": 3, "seed_salt": 2654435769}')
	file.close()
	var wiring: RunWiring = RunWiring.new()
	wiring.run_file = THREE_LEVELS
	wiring.pick_seed = func() -> int: return NEXT_RUN_SEED
	return wiring


func _plan(run_seed: int, path: String = THREE_LEVELS) -> RunPlan:
	return RunPlan.build(run_seed, FileAccess.get_file_as_string(path))


func _seed_source(level_seed: int) -> String:
	return LevelSwitch.SEED_PREFIX + str(level_seed)


func test_other_sources_fly_as_before() -> String:
	var wiring: RunWiring = RunWiring.new()
	for source: String in ["", "seed:31", "res://data/levels/g2_level.json"]:
		if wiring.begin(source) != source or wiring.is_active():
			return "source '%s' was changed or started a run" % source
		if wiring.on_end(ExitRule.Outcome.ESCAPED, {}, source) != source:
			return "an escape from '%s' flew something else" % source
		if wiring.on_end(ExitRule.Outcome.LOST, {}, source) != source:
			return "a loss on '%s' flew something else" % source
	return ""


func test_a_run_starts_on_its_first_level() -> String:
	var wiring: RunWiring = RunWiring.new()
	var source: String = wiring.begin("run:%d" % RUN_SEED)
	var plan: RunPlan = _plan(RUN_SEED, RUN)
	if not wiring.is_active() or source != _seed_source(plan.level_seed(0)):
		return "run %d flies '%s', expected %s" % [RUN_SEED, source, _seed_source(plan.level_seed(0))]
	if wiring.state.shafts != null:
		return "the run was built with a shaft offer"
	if LevelSwitch.load_level(source) == null:
		return "the run's first level did not load"
	return ""


func test_escape_on_level_one_flies_level_two() -> String:
	var wiring: RunWiring = _three_level_wiring()
	var escape_end: EscapeEndWiring = EscapeEndWiring.new()
	var first: String = wiring.begin("run:%d" % RUN_SEED, escape_end)
	var plan: RunPlan = _plan(RUN_SEED)
	if plan.level_count() != 3 or first != _seed_source(plan.level_seed(0)):
		return "three-level run flies '%s' of %d levels" % [first, plan.level_count()]
	if escape_end.run_won:
		return "level 1 of 3 is shown as the run's last"
	var second: String = wiring.on_end(ExitRule.Outcome.ESCAPED, {"scrap_alloy": 2}, first)
	if second != _seed_source(plan.level_seed(1)) or wiring.state.current_depth() != 2:
		return "escape flew '%s' at depth %d, expected %s" % [second, wiring.state.current_depth(),
			_seed_source(plan.level_seed(1))]
	if wiring.profile.count_of("scrap_alloy") != 2:
		return "the escape banked %d scrap" % wiring.profile.count_of("scrap_alloy")
	return ""


func test_restart_while_running_flies_the_same_level() -> String:
	var wiring: RunWiring = _three_level_wiring()
	var first: String = wiring.begin("run:%d" % RUN_SEED)
	if wiring.on_end(ExitRule.Outcome.RUNNING, {"scrap_alloy": 2}, first) != first:
		return "a restart while flying left the level"
	if wiring.state.level_index != 0 or wiring.profile.count_of("scrap_alloy") != 0:
		return "a restart while flying advanced or banked"
	return ""


func test_the_last_escape_wins_and_starts_a_new_run() -> String:
	var wiring: RunWiring = _three_level_wiring()
	var escape_end: EscapeEndWiring = EscapeEndWiring.new()
	var source: String = wiring.begin("run:%d" % RUN_SEED, escape_end)
	source = wiring.on_end(ExitRule.Outcome.ESCAPED, {"cell_salts": 1}, source)
	source = wiring.on_end(ExitRule.Outcome.ESCAPED, {}, source)
	if not escape_end.run_won:
		return "level 3 of 3 is not shown as the run's last"
	var last_state: RunState = wiring.state
	source = wiring.on_end(ExitRule.Outcome.ESCAPED, {"cell_salts": 2}, source)
	if not last_state.won or wiring.ended != last_state:
		return "the last escape did not win the run"
	if wiring.state == last_state or wiring.state.plan.run_seed != NEXT_RUN_SEED:
		return "no new run started after the win"
	if source != _seed_source(_plan(NEXT_RUN_SEED).level_seed(0)) or escape_end.run_won:
		return "the new run flies '%s', run won still %s" % [source, escape_end.run_won]
	if wiring.profile.count_of("cell_salts") != 3:
		return "the run banked %d cell salts, expected 3" % wiring.profile.count_of("cell_salts")
	return ""


func test_a_loss_ends_the_run_and_keeps_earlier_banking() -> String:
	var wiring: RunWiring = _three_level_wiring()
	var source: String = wiring.begin("run:%d" % RUN_SEED)
	source = wiring.on_end(ExitRule.Outcome.ESCAPED, {"circuit_shards": 2}, source)
	var lost_state: RunState = wiring.state
	source = wiring.on_end(ExitRule.Outcome.LOST, {"core_glass": 1, "circuit_shards": 4}, source)
	if not lost_state.lost or wiring.ended != lost_state:
		return "the loss did not end the run as lost"
	if lost_state.banked != {"circuit_shards": 2} or not lost_state.carried.is_empty():
		return "the lost run banked %s, carried %s" % [lost_state.banked, lost_state.carried]
	if wiring.profile.count_of("circuit_shards") != 2 or wiring.profile.count_of("core_glass") != 0:
		return "the profile holds %s after the loss" % wiring.profile.to_json()
	if wiring.state.plan.run_seed != NEXT_RUN_SEED or wiring.state.level_index != 0:
		return "the loss did not start a new run"
	if source != _seed_source(_plan(NEXT_RUN_SEED).level_seed(0)):
		return "after the loss the run flies '%s'" % source
	return ""


func test_a_rejected_plan_flies_the_tunnel() -> String:
	var wiring: RunWiring = RunWiring.new()
	wiring.run_file = "res://no_such_run.json"
	if wiring.begin("run:5") != "" or wiring.is_active():
		return "a run with no plan file started"
	if wiring.begin("run:x") != "" or wiring.is_active():
		return "a run with no seed started"
	return ""


func test_the_profile_is_saved_after_a_banking_escape() -> String:
	var path: String = "user://t989_profile.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var wiring: RunWiring = _three_level_wiring()
	wiring.store = ProfileStore.new(path)
	var source: String = wiring.begin("run:%d" % RUN_SEED)
	wiring.on_end(ExitRule.Outcome.ESCAPED, {"scrap_alloy": 3}, source)
	var read: Profile = ProfileStore.new(path).load_profile()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if read.count_of("scrap_alloy") != 3:
		return "the saved profile holds %d scrap" % read.count_of("scrap_alloy")
	return ""


func test_run_switch_is_read_after_level_and_seed() -> String:
	var pick: Callable = func() -> int: return 42
	var cases: Array = [
		[["--run=12345"], "", "", "", "run:12345"],
		[[], "", "", "9", "run:9"],
		[["--run=random"], "", "", "", "run:42"],
		[["--run=5", "--seed=7"], "", "", "", "seed:7"],
		[["--run=5"], "g2", "", "", LevelSwitch.path_for("g2")],
		[[], "", "8", "9", "seed:8"],
		[["--run=-3"], "", "", "", ""],
		[["--run=abc"], "", "", "", ""],
		[[], "", "", "", ""],
	]
	for case: Array in cases:
		var got: String = LevelSwitch.requested_source(PackedStringArray(case[0]), case[1], case[2], pick, case[3])
		if got != case[4]:
			return "%s, intents %s/%s/%s gave '%s', expected '%s'" % [case[0], case[1], case[2], case[3],
				got, case[4]]
	return ""


func test_escape_screen_says_run_won_on_the_last_level() -> String:
	var look: Dictionary = EscapeScreenLook.load_file()
	if look.has("error") or look["run_won_text"] != "RUN WON" or look != EscapeScreenLook.parse(
			FileAccess.get_file_as_string(EscapeScreenLook.DEFAULT_FILE)):
		return "the shipped escape screen has no run won line"
	var rig: Node3D = Node3D.new()
	var wiring: EscapeEndWiring = EscapeEndWiring.new()
	wiring.attach(rig)
	var level: LevelDef = LevelSwitch.load_level("res://data/levels/g2_level.json")
	var session: LocalSession = LocalSession.for_level(level, 0, null, LocalSession.load_tuning(LevelStart.SHIP_TUNING_PATH))
	session.sim.reactor.destroyed = true
	session.sim.ships[0].escaped = true
	wiring.update(session, 0.5, false, Transform3D.IDENTITY, false)
	var plain: String = wiring.screen.line_text()
	wiring.run_won = true
	wiring.update(session, 0.5, false, Transform3D.IDENTITY, false)
	var won: String = wiring.screen.line_text()
	rig.free()
	if plain != "ESCAPED" or won != "RUN WON":
		return "the line read '%s' then '%s'" % [plain, won]
	return ""
