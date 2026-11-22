extends RefCounted

## A run records the profile's statistics (#1092, CRW-2, RUN-7, CRF-2, SLV-3):
## `RunWiring` counts each run start, escape, loss and win through
## `RunStatsRecorder` and saves the profile once per event with its store; a
## single level records nothing; a failure is logged once and the run flies on.

## A run of exactly two levels, so the second escape wins it.
const TWO_LEVELS: String = "{\"min_levels\": 2, \"max_levels\": 2, \"seed_salt\": 2654435769}"
const RUN_SEED: int = 12345
const PROFILE_PATH: String = "user://t1092_profile.json"


## A scratch store that keeps the text of every profile it saves.
class CountingStore extends ProfileStore:
	var saved_texts: Array[String] = []

	func save(profile: Profile) -> bool:
		saved_texts.append(profile.to_json())
		return super(profile)

	## The statistics of save `index`, as written.
	func stats_at(index: int) -> Dictionary:
		return Profile.parse_json(saved_texts[index]).stats.to_dict()


func _scratch() -> CountingStore:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))
	return CountingStore.new(PROFILE_PATH)


func _cleanup() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))


func _wiring(store: ProfileStore) -> RunWiring:
	return RunWiring.new(RUN_SEED, store, func() -> int: return 77, TWO_LEVELS, false)


## `actual` holds every pair of `want`; "" or what differs.
static func _differs(actual: Dictionary, want: Dictionary) -> String:
	for key: String in want:
		if int(actual.get(key, -1)) != int(want[key]):
			return "%s is %s, expected %d (all: %s)" % [key, actual.get(key), int(want[key]), actual]
	return ""


func test_a_run_start_is_recorded_and_saved() -> String:
	var store: CountingStore = _scratch()
	var run: RunWiring = _wiring(store)
	var on_disk: Profile = ProfileStore.new(PROFILE_PATH).load_profile()
	_cleanup()
	if store.saved_texts.size() != 1:
		return "the start saved %d times, expected once" % store.saved_texts.size()
	if run.profile.stats.runs_started != 1 or on_disk.stats.runs_started != 1:
		return "runs started %d, on disk %d" % [run.profile.stats.runs_started, on_disk.stats.runs_started]
	return ""


func test_a_two_level_run_won_counts_one_start_two_escapes_and_a_win() -> String:
	var store: CountingStore = _scratch()
	var run: RunWiring = _wiring(store)
	run.after_level(ExitRule.Outcome.ESCAPED, 50.0, {"power_cell": 2}, 1)
	run.after_level(ExitRule.Outcome.ESCAPED, 50.0, {"power_cell": 1})
	var on_disk: Profile = ProfileStore.new(PROFILE_PATH).load_profile()
	_cleanup()
	if run.ended == null or not run.ended.won:
		return "the run was not won"
	# Saves: start, escape 1, escape 2, win, then the next run's start.
	if store.saved_texts.size() != 5:
		return "%d saves, expected 5 (one per event)" % store.saved_texts.size()
	var problem: String = _differs(store.stats_at(3), {"runs_started": 1, "levels_escaped": 2,
		"runs_won": 1, "runs_lost": 0, "deepest_level": 2, "miners_rescued": 1, "components_banked": 3})
	if problem != "":
		return "when the win was saved: " + problem
	# The game starts the next run at once; it counts its own start.
	problem = _differs(on_disk.stats.to_dict(), {"runs_started": 2, "levels_escaped": 2, "runs_won": 1})
	return "after the next run started: " + problem if problem != "" else ""


func test_a_loss_on_level_two_counts_one_escape_and_one_loss_keeping_the_bank() -> String:
	var store: CountingStore = _scratch()
	var run: RunWiring = _wiring(store)
	run.after_level(ExitRule.Outcome.ESCAPED, 50.0, {"power_cell": 2})
	run.after_level(ExitRule.Outcome.RUNNING, 0.0, {"power_cell": 5})
	var on_disk: Profile = ProfileStore.new(PROFILE_PATH).load_profile()
	_cleanup()
	if run.ended == null or not run.ended.lost:
		return "the run was not lost"
	if store.saved_texts.size() != 4:
		return "%d saves, expected 4 (start, escape, loss, next start)" % store.saved_texts.size()
	var problem: String = _differs(store.stats_at(2), {"runs_started": 1, "levels_escaped": 1,
		"runs_lost": 1, "runs_won": 0, "deepest_level": 1, "components_banked": 2})
	if problem != "":
		return "when the loss was saved: " + problem
	if on_disk.count_of("power_cell") != 2:
		return "the level-1 bank was not kept: %s" % on_disk.banked
	return ""


func test_an_escape_into_a_shaft_choice_is_recorded_once() -> String:
	var store: CountingStore = _scratch()
	var run: RunWiring = RunWiring.new(RUN_SEED, store, func() -> int: return 77)
	var offered: Array[String] = run.escape_for_choice({"power_cell": 1})
	run.choose(offered[0])
	run.after_level(ExitRule.Outcome.ESCAPED, 50.0, {"power_cell": 1})
	_cleanup()
	var problem: String = _differs(run.profile.stats.to_dict(), {"runs_started": 1, "levels_escaped": 1,
		"deepest_level": 1, "components_banked": 1})
	if problem != "":
		return problem
	return "" if store.saved_texts.size() == 2 else "%d saves, expected 2" % store.saved_texts.size()


func test_a_single_level_records_nothing() -> String:
	var store: CountingStore = _scratch()
	var level_start: LevelStart = LevelStart.new()
	var picked: RunWiring = level_start.choose("res://data/levels/test_level.json", store)
	var seeded: RunWiring = level_start.choose(LevelSwitch.SEED_PREFIX + "42", store)
	var exists: bool = FileAccess.file_exists(PROFILE_PATH)
	_cleanup()
	if picked != null or seeded != null:
		return "a single level started a run"
	if not store.saved_texts.is_empty() or exists:
		return "a single level saved the profile"
	return ""


func test_leaving_the_run_records_nothing_more() -> String:
	var store: CountingStore = _scratch()
	var run: RunWiring = _wiring(store)
	run.stop()
	_cleanup()
	if store.saved_texts.size() != 1 or run.profile.stats.runs_lost != 0:
		return "leaving the run saved %d times" % store.saved_texts.size()
	return ""


func test_a_failed_save_is_noted_and_the_run_flies_on() -> String:
	var store: CountingStore = _scratch()
	var run: RunWiring = _wiring(store)
	store.locked = true  # As a profile from a newer build leaves it.
	var next: String = run.after_level(ExitRule.Outcome.ESCAPED, 50.0, {})
	_cleanup()
	if not run.stats.logged or not run.stats.error.contains("not saved"):
		return "the failure was not noted: '%s'" % run.stats.error
	if not run.active() or next != LevelSwitch.SEED_PREFIX + str(run.state.plan.level_seed(1)):
		return "the run stopped: flies '%s'" % next
	run.after_level(ExitRule.Outcome.RUNNING, 0.0, {})
	if run.ended == null or not run.ended.lost or not run.active() or not run.stats.error.contains("not saved"):
		return "after a second failure: '%s', active %s" % [run.stats.error, run.active()]
	return ""


func test_a_refused_escape_is_noted_and_changes_nothing() -> String:
	var recorder: RunStatsRecorder = RunStatsRecorder.new()
	var profile: Profile = Profile.new()
	if recorder.escaped(profile, 0, -1, {}):
		return "negative miners were recorded"
	if profile.stats.levels_escaped != 0 or not recorder.logged or recorder.error == "":
		return "escapes %d, logged %s" % [profile.stats.levels_escaped, recorder.logged]
	return ""
