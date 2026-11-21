extends RefCounted

## `RunWiring` flies a run without a scene (#989, RUN-1, RUN-3, RUN-7, CRF-2):
## an escape moves to the next level with the seed `RunPlan` gives and banks
## the level's components, the last escape wins the run, and a loss ends it
## keeping what earlier escapes banked. Also the `--run` switch, `LevelStart`'s
## choice and the escape screen's won line. These runs have no shaft choice, as
## a run flies when the shaft file is rejected; `test_shaft_choice_wiring.gd`
## covers the choice (#990).

## A run of exactly three levels, so the tests know where it ends.
const THREE_LEVELS: String = "{\"min_levels\": 3, \"max_levels\": 3, \"seed_salt\": 2654435769}"
const RUN_SEED: int = 12345
const NEXT_RUN_SEED: int = 77
const PROFILE_PATH: String = "user://t989_profile.json"


func _wiring(store: ProfileStore = null) -> RunWiring:
	return RunWiring.new(RUN_SEED, store, func() -> int: return NEXT_RUN_SEED, THREE_LEVELS, false)


func _plan(run_seed: int) -> RunPlan:
	return RunPlan.build(run_seed, THREE_LEVELS)


func _seed_source(run_seed: int, index: int) -> String:
	return LevelSwitch.SEED_PREFIX + str(_plan(run_seed).level_seed(index))


func test_a_run_starts_on_its_first_level() -> String:
	var run: RunWiring = _wiring()
	if not run.active() or run.error != "" or run.state.plan.level_count() != 3:
		return "run: active %s, error '%s'" % [run.active(), run.error]
	if run.level_source() != _seed_source(RUN_SEED, 0):
		return "level 1 flies %s, expected %s" % [run.level_source(), _seed_source(RUN_SEED, 0)]
	if run.on_last_level():
		return "level 1 of 3 counted as the last"
	return ""


func test_an_escape_on_level_one_flies_level_two_and_banks() -> String:
	var run: RunWiring = _wiring()
	var next: String = run.after_level(ExitRule.Outcome.ESCAPED, 50.0, {"power_cell": 2})
	if next != _seed_source(RUN_SEED, 1) or run.state.level_index != 1:
		return "after the escape: %s at index %d, expected %s" % [next, run.state.level_index,
			_seed_source(RUN_SEED, 1)]
	if run.profile.count_of("power_cell") != 2 or run.state.banked.get("power_cell", 0) != 2:
		return "banked %s, profile has %d" % [run.state.banked, run.profile.count_of("power_cell")]
	return ""


func test_the_last_escape_wins_and_starts_a_new_run() -> String:
	var run: RunWiring = _wiring()
	run.after_level(ExitRule.Outcome.ESCAPED, 50.0, {"power_cell": 1})
	run.after_level(ExitRule.Outcome.ESCAPED, 50.0, {})
	if not run.on_last_level():
		return "level 3 of 3 is not the last"
	var next: String = run.after_level(ExitRule.Outcome.ESCAPED, 50.0, {"power_cell": 3})
	if run.ended == null or not run.ended.won or run.ended.lost:
		return "the ended run is %s" % ("missing" if run.ended == null else "won %s lost %s" % [
			run.ended.won, run.ended.lost])
	if run.ended.banked.get("power_cell", 0) != 4 or run.profile.count_of("power_cell") != 4:
		return "won with %s banked, profile %d" % [run.ended.banked, run.profile.count_of("power_cell")]
	if next != _seed_source(NEXT_RUN_SEED, 0) or run.state.plan.run_seed != NEXT_RUN_SEED:
		return "after the win flies %s, expected the new run's %s" % [next, _seed_source(NEXT_RUN_SEED, 0)]
	return ""


func test_a_loss_ends_the_run_keeping_earlier_banks() -> String:
	var run: RunWiring = _wiring()
	run.after_level(ExitRule.Outcome.ESCAPED, 50.0, {"power_cell": 2})
	var next: String = run.after_level(ExitRule.Outcome.RUNNING, 0.0, {"power_cell": 5})
	if run.ended == null or not run.ended.lost or run.ended.won:
		return "the loss did not end the run lost"
	if run.ended.banked.get("power_cell", 0) != 2 or run.profile.count_of("power_cell") != 2:
		return "after the loss %s banked, profile %d; expected 2" % [run.ended.banked,
			run.profile.count_of("power_cell")]
	if next != _seed_source(NEXT_RUN_SEED, 0):
		return "after the loss flies %s, expected a new run" % next
	return ""


## The dev menu's Restart while flying: neither end, so the same level again.
func test_a_restart_mid_level_flies_the_same_level() -> String:
	var run: RunWiring = _wiring()
	run.after_level(ExitRule.Outcome.ESCAPED, 50.0, {})
	var hash_before: int = run.state.state_hash()
	var next: String = run.after_level(ExitRule.Outcome.RUNNING, 40.0, {"power_cell": 1})
	if next != _seed_source(RUN_SEED, 1) or run.state.state_hash() != hash_before:
		return "a mid-level restart flew %s and moved the run" % next
	if RunWiring.ends_level(ExitRule.Outcome.RUNNING, 40.0) or not RunWiring.ends_level(ExitRule.Outcome.RUNNING, 0.0) \
			or not RunWiring.ends_level(ExitRule.Outcome.ESCAPED, 40.0):
		return "ends_level judged wrong"
	return ""


func test_same_seed_and_inputs_give_the_same_run() -> String:
	var first: RunWiring = _wiring()
	var second: RunWiring = _wiring()
	for run: RunWiring in [first, second]:
		run.after_level(ExitRule.Outcome.ESCAPED, 50.0, {"power_cell": 1})
	if first.state.state_hash() != second.state.state_hash() or first.level_source() != second.level_source():
		return "two runs of seed %d differ" % RUN_SEED
	return ""


func test_a_rejected_run_file_flies_no_run() -> String:
	var run: RunWiring = RunWiring.new(RUN_SEED, null, Callable(), "{\"min_levels\": 3}")
	if run.active() or run.level_source() != "" or not run.error.contains("max_levels"):
		return "a rejected file gave active %s, '%s', error '%s'" % [run.active(), run.level_source(), run.error]
	return ""


func test_the_shipped_run_file_builds() -> String:
	var run: RunWiring = RunWiring.new(RUN_SEED)
	if not run.active() or run.error != "":
		return "the shipped run file: %s" % run.error
	return ""


## An escape saves the profile through the store; a loss saves nothing more.
func test_banks_are_saved_through_the_store() -> String:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))
	var run: RunWiring = _wiring(ProfileStore.new(PROFILE_PATH))
	run.after_level(ExitRule.Outcome.ESCAPED, 50.0, {"power_cell": 2})
	run.after_level(ExitRule.Outcome.RUNNING, 0.0, {"power_cell": 9})
	var read: Profile = ProfileStore.new(PROFILE_PATH).load_profile()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))
	if read.count_of("power_cell") != 2:
		return "the saved profile holds %d, expected 2" % read.count_of("power_cell")
	return ""


func test_the_run_switch_is_read_and_seed_and_level_win() -> String:
	var none: PackedStringArray = PackedStringArray()
	var picks: Callable = func() -> int: return 4321
	var cases: Array[Array] = [
		[PackedStringArray(["--run=12345"]), "", "", "run:12345"],
		[none, "", " 9 ", "run:9"],
		[PackedStringArray(["--run=1", "--run=2"]), "", "3", "run:2"],
		[PackedStringArray(["--run=random"]), "", "", "run:4321"],
		[PackedStringArray(["--run=5", "--seed=7"]), "", "", "seed:7"],
		[PackedStringArray(["--run=5", "--level=g2"]), "", "", LevelSwitch.path_for("g2")],
		[PackedStringArray(["--run=-3"]), "", "", ""],
		[PackedStringArray(["--run=abc"]), "", "", ""],
		[none, "", "", ""],
	]
	for case: Array in cases:
		var got: String = LevelSwitch.requested_source(case[0], case[1], "", picks, case[2])
		if got != case[3]:
			return "%s with run intent '%s' gave '%s', expected '%s'" % [case[0], case[2], got, case[3]]
	return ""


func test_level_start_chooses_a_run_or_a_single_level() -> String:
	var start: LevelStart = LevelStart.new()
	var store: ProfileStore = ProfileStore.new(PROFILE_PATH)
	var run: RunWiring = start.choose("run:%d" % RUN_SEED, store)
	var plan: RunPlan = RunPlan.build(RUN_SEED, FileAccess.get_file_as_string(RunWiring.RUN_FILE))
	if run == null or start.run != run or start.source != LevelSwitch.SEED_PREFIX + str(plan.level_seed(0)):
		return "run:%d chose %s" % [RUN_SEED, start.source]
	if start.choose("seed:5", store) != null or start.run != null or start.source != "seed:5":
		return "seed:5 chose %s with a run" % start.source
	if start.choose("", store) != null or start.source != "":
		return "the tunnel chose %s" % start.source
	return ""


## The dev menu choosing another level leaves the run: the next fresh session
## flies what the menu chose.
func test_a_dev_menu_level_leaves_the_run() -> String:
	var start: LevelStart = LevelStart.new()
	start.run = _wiring()
	start.source = ""  # The dev menu chose the test tunnel.
	var world: Node3D = Node3D.new()
	var input: LatestInputSource = LatestInputSource.new()
	var ended: LocalSession = LevelStart.tunnel_session(input)
	var fresh: LocalSession = start.fresh_session(world, input, ended)
	var problem: String = ""
	if fresh == null or start.source != "" or start.run.active():
		problem = "after the menu's choice: source '%s', run active %s" % [start.source, start.run.active()]
	world.free()
	return problem


func test_the_escape_screen_says_the_run_is_won_on_the_last_level() -> String:
	var escape: EscapeEndWiring = EscapeEndWiring.new()
	if escape.run_won():
		return "a single level counted as a won run"
	escape.run = _wiring()
	if escape.run_won():
		return "level 1 of 3 counted as won"
	escape.run.after_level(ExitRule.Outcome.ESCAPED, 50.0, {})
	escape.run.after_level(ExitRule.Outcome.ESCAPED, 50.0, {})
	if not escape.run_won():
		return "the last level's escape does not say the run is won"
	var screen: EscapeScreen = EscapeScreen.new(EscapeScreenLook.load_file())
	screen.show_state(true, true, 30.0, false, true)
	var won_text: String = screen.line_text()
	screen.show_state(true, true, 30.0, false, false)
	var escaped_text: String = screen.line_text()
	screen.free()
	if won_text != "RUN WON" or escaped_text != "ESCAPED":
		return "the screen read '%s' and '%s'" % [won_text, escaped_text]
	return ""


func test_won_text_may_be_left_out_of_the_look() -> String:
	var shipped: Dictionary = EscapeScreenLook.load_file()
	if shipped.get("won_text") != "RUN WON":
		return "the shipped look has won_text %s" % shipped.get("won_text")
	var text: String = FileAccess.get_file_as_string(EscapeScreenLook.DEFAULT_FILE)
	var without: String = text.replace(",\n\t\"won_text\": \"RUN WON\"", "")
	if without == text:
		return "could not take won_text out of the shipped file"
	var look: Dictionary = EscapeScreenLook.parse(without)
	if look.has("error") or look.get("won_text") != EscapeScreenLook.FALLBACK["won_text"]:
		return "without won_text the look is %s" % look.get("error", look.get("won_text"))
	if not EscapeScreenLook.parse(text.replace("\"RUN WON\"", "\"  \"")).get("error", "").contains("won_text"):
		return "an empty won_text was accepted"
	return ""
