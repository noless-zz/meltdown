extends RefCounted

## An escape brings the level's rescued miners into the profile's crew; a lost
## ship adds nobody (#1032, CRW-1, SLV-3, RUN-7, CRF-2, ARC-2, MP-2). The run
## has exactly three levels and no shaft choice, as in `test_run_wiring.gd`;
## `escape_for_choice` is covered with the shipped shafts.

const THREE_LEVELS: String = "{\"min_levels\": 3, \"max_levels\": 3, \"seed_salt\": 2654435769}"
const RUN_SEED: int = 12345
const NEXT_RUN_SEED: int = 77
const DIR: String = "user://t1032_crew_joins"
## A fixed copy of the roles, so the pinned picks below do not move when the
## shipped roles file is tuned (the same copy as `test_crew_roster.gd`).
const ROLES_TEXT: String = """{"roles": [
	{"id": "surveyor", "name": "Surveyor", "weight": 30, "benefit": {"stat": "map_reveal", "amount": 1}},
	{"id": "shield_tech", "name": "Shield Technician", "weight": 25, "benefit": {"stat": "shield_max", "amount": 5}},
	{"id": "cargo_rigger", "name": "Cargo Rigger", "weight": 25, "benefit": {"stat": "salvage_slots", "amount": 1}},
	{"id": "reactor_hand", "name": "Reactor Hand", "weight": 20, "benefit": {"stat": "meltdown_seconds", "amount": 5}}
], "caps": {"map_reveal": 1, "meltdown_seconds": 20, "salvage_slots": 2, "shield_max": 25}}"""


## Counts saves, so a test can see the escape saved the profile once.
class CountingStore extends ProfileStore:
	var saves: int = 0

	func save(profile: Profile) -> bool:
		saves += 1
		return super.save(profile)


func _path(name: String) -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var path: String = "%s/%s.json" % [DIR, name]
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return path


func _wiring(store: ProfileStore = null, with_shafts: bool = false) -> RunWiring:
	var run: RunWiring = RunWiring.new(RUN_SEED, store, func() -> int: return NEXT_RUN_SEED, THREE_LEVELS,
		with_shafts)
	run.use_roles(ROLES_TEXT)
	return run


func _member(id: String, role: String) -> Dictionary:
	return {Profile.CREW_ID: id, Profile.CREW_ROLE: role}


func _pinned() -> Array[Dictionary]:
	return [_member("crew-1", "surveyor"), _member("crew-2", "shield_tech")]


func test_escaping_with_two_rescued_gives_two_pinned_crew_saved_once() -> String:
	var store: CountingStore = CountingStore.new(_path("escape"))
	var run: RunWiring = _wiring(store)
	run.after_level(ExitRule.Outcome.ESCAPED, 50.0, {"power_cell": 1}, 2)
	if run.profile.crew != _pinned():
		return "crew %s, expected %s" % [run.profile.crew, _pinned()]
	if store.saves != 1:
		return "the escape saved %d times, expected once with the components" % store.saves
	var read: Profile = ProfileStore.new(store.path).load_profile()
	if read.crew != _pinned() or read.count_of("power_cell") != 1:
		return "the saved profile has crew %s and %d power cells" % [read.crew, read.count_of("power_cell")]
	return ""


func test_losing_the_next_level_keeps_the_crew() -> String:
	var store: ProfileStore = ProfileStore.new(_path("loss_keeps"))
	var run: RunWiring = _wiring(store)
	run.after_level(ExitRule.Outcome.ESCAPED, 50.0, {}, 2)
	run.after_level(ExitRule.Outcome.RUNNING, 0.0, {}, 3)
	if run.ended == null or not run.ended.lost:
		return "the loss did not end the run"
	if run.profile.crew != _pinned():
		return "after the loss the crew is %s" % [run.profile.crew]
	if ProfileStore.new(store.path).load_profile().crew != _pinned():
		return "the saved crew changed on the loss"
	return ""


func test_a_lost_level_with_one_rescued_adds_nobody() -> String:
	var store: CountingStore = CountingStore.new(_path("loss"))
	var run: RunWiring = _wiring(store)
	run.after_level(ExitRule.Outcome.RUNNING, 0.0, {}, 1)
	if not run.profile.crew.is_empty() or store.saves != 0:
		return "the loss gave crew %s and %d saves" % [run.profile.crew, store.saves]
	return ""


## ARC-2: the same run seed, level and count give the same roles; another
## level gives its own.
func test_the_same_run_level_and_count_give_the_same_roles() -> String:
	var first: RunWiring = _wiring()
	var second: RunWiring = _wiring()
	first.after_level(ExitRule.Outcome.ESCAPED, 50.0, {}, 2)
	second.after_level(ExitRule.Outcome.ESCAPED, 50.0, {}, 2)
	if first.profile.crew != second.profile.crew:
		return "two runs gave %s and %s" % [first.profile.crew, second.profile.crew]
	first.after_level(ExitRule.Outcome.ESCAPED, 50.0, {}, 1)
	var expected: Profile = Profile.new()
	expected.crew = _pinned()
	CrewRoster.add_rescued(expected, CrewRoles.parse_json(ROLES_TEXT), RUN_SEED, 1, 1)
	if first.profile.crew != expected.crew:
		return "level 2's miner joined as %s, expected %s" % [first.profile.crew, expected.crew]
	return ""


func test_a_rejected_roles_file_adds_no_crew_and_leaves_the_file_unchanged() -> String:
	var store: ProfileStore = ProfileStore.new(_path("rejected"))
	var run: RunWiring = _wiring(store)
	run.after_level(ExitRule.Outcome.ESCAPED, 50.0, {}, 2)
	var before: String = FileAccess.get_file_as_string(store.path)
	run.use_roles("{\"roles\": []}")
	var next: String = run.after_level(ExitRule.Outcome.ESCAPED, 50.0, {}, 1)
	if FileAccess.get_file_as_string(store.path) != before:
		return "the refused add changed the profile file"
	if run.profile.crew != _pinned() or run.crew_error == "":
		return "crew %s, crew error '%s'" % [run.profile.crew, run.crew_error]
	if run.error != "" or next == "" or run.state.level_index != 2:
		return "the run stopped: error '%s', next '%s'" % [run.error, next]
	return ""


func test_an_escape_with_no_rescued_adds_nobody() -> String:
	var run: RunWiring = _wiring()
	run.after_level(ExitRule.Outcome.ESCAPED, 50.0, {"power_cell": 1})
	if not run.profile.crew.is_empty() or run.crew_error != "":
		return "crew %s, error '%s'" % [run.profile.crew, run.crew_error]
	return ""


## The escape screen's press before a shaft choice adds the crew there, once:
## the restart that follows does not add it again.
func test_escape_for_choice_adds_the_crew_once() -> String:
	var store: CountingStore = CountingStore.new(_path("choice"))
	var run: RunWiring = _wiring(store, true)
	if run.shafts == null:
		return "the shipped shafts were rejected"
	if run.escape_for_choice({"power_cell": 1}, 2).is_empty():
		return "no shaft choice after level 1"
	if run.profile.crew != _pinned() or store.saves != 1:
		return "crew %s after %d saves" % [run.profile.crew, store.saves]
	run.after_level(ExitRule.Outcome.ESCAPED, 50.0, {"power_cell": 1}, 2)
	if run.profile.crew != _pinned() or store.saves != 1:
		return "the restart added crew again: %s, %d saves" % [run.profile.crew, store.saves]
	return ""


func test_rescued_in_reads_the_sims_count() -> String:
	var sim: Sim = Sim.new()
	if RunWiring.rescued_in(sim) != 0:
		return "a sim without rescue counted %d" % RunWiring.rescued_in(sim)
	var rules: MinerRescue = MinerRescue.parse_json("{\"rescue_reach\": 4.0, \"hold_seconds\": 2.0}")
	if sim.set_rescue_rules(rules, [Vector3i(0, 0, 0)]) != "":
		return "the rescue rules were refused"
	sim.rescue.rescued = 3
	if RunWiring.rescued_in(sim) != 3:
		return "counted %d, expected 3" % RunWiring.rescued_in(sim)
	return ""
