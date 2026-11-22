extends RefCounted

## `RunEscapeBank` banks one escaped level (#1136, split out of `RunWiring`;
## RUN-7, CRF-2, CRW-1, CRW-2): components, rescued miners and statistics, then
## one save. The roles text and the pinned crew are the same as in
## `test_run_crew_joins.gd`, so both see the same picks for run 12345 level 1.

const THREE_LEVELS: String = "{\"min_levels\": 3, \"max_levels\": 3, \"seed_salt\": 2654435769}"
const RUN_SEED: int = 12345
const ROLES_TEXT: String = """{"roles": [
	{"id": "surveyor", "name": "Surveyor", "weight": 30, "benefit": {"stat": "map_reveal", "amount": 1}},
	{"id": "shield_tech", "name": "Shield Technician", "weight": 25, "benefit": {"stat": "shield_max", "amount": 5}},
	{"id": "cargo_rigger", "name": "Cargo Rigger", "weight": 25, "benefit": {"stat": "salvage_slots", "amount": 1}},
	{"id": "reactor_hand", "name": "Reactor Hand", "weight": 20, "benefit": {"stat": "meltdown_seconds", "amount": 5}}
], "caps": {"map_reveal": 1, "meltdown_seconds": 20, "salvage_slots": 2, "shield_max": 25}}"""
const PATH: String = "user://t1136_escape_bank.json"


## Counts saves and can refuse them, to see one save per escape and a failure.
class CountingStore extends ProfileStore:
	var saves: int = 0
	var refuse: bool = false

	func save(profile: Profile) -> bool:
		saves += 1
		if refuse:
			message = "refused by the test"
			return false
		return super.save(profile)


func _state() -> RunState:
	return RunState.new(RunPlan.build(RUN_SEED, THREE_LEVELS))


func _store() -> CountingStore:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)
	return CountingStore.new(PATH)


func _crew_ids(profile: Profile) -> Array[String]:
	var ids: Array[String] = []
	for member: Dictionary in profile.crew:
		ids.append("%s:%s" % [member[Profile.CREW_ID], member[Profile.CREW_ROLE]])
	return ids


func test_an_escape_banks_components_crew_and_statistics_with_one_save() -> String:
	var state: RunState = _state()
	var profile: Profile = Profile.new()
	var store: CountingStore = _store()
	var roles: CrewRoles = RunEscapeBank.read_roles(ROLES_TEXT)
	var result: RunEscapeBank = RunEscapeBank.bank(state, state.advance({"power_cell": 2}), 0, 2, profile,
		store, roles, RunStatsRecorder.new())
	if result.error != "" or result.crew_error != "" or result.refused:
		return "error '%s', crew '%s', refused %s" % [result.error, result.crew_error, result.refused]
	if profile.count_of("power_cell") != 2:
		return "banked %s" % profile.banked
	if _crew_ids(profile) != ["crew-1:surveyor", "crew-2:shield_tech"]:
		return "crew %s" % [_crew_ids(profile)]
	if profile.stats.levels_escaped != 1 or profile.stats.miners_rescued != 2:
		return "stats %s" % profile.stats.to_dict()
	if store.saves != 1:
		return "%d saves, expected 1" % store.saves
	return ""


func test_a_refused_escape_banks_and_saves_nothing() -> String:
	var state: RunState = _state()
	state.advance({"power_cell": 1})
	state.advance()
	state.advance()  # Won: one more advance is refused.
	var profile: Profile = Profile.new()
	var store: CountingStore = _store()
	var result: RunEscapeBank = RunEscapeBank.bank(state, state.advance({"power_cell": 1}), 2, 1, profile,
		store, RunEscapeBank.read_roles(ROLES_TEXT), RunStatsRecorder.new())
	if not result.refused or not result.error.contains("refused"):
		return "refused %s, error '%s'" % [result.refused, result.error]
	if not profile.banked.is_empty() or not profile.crew.is_empty() or store.saves != 0:
		return "banked %s, crew %d, saves %d" % [profile.banked, profile.crew.size(), store.saves]
	return ""


func test_rescued_miners_without_roles_join_nobody_and_the_bank_still_saves() -> String:
	var state: RunState = _state()
	var profile: Profile = Profile.new()
	var store: CountingStore = _store()
	var roles: CrewRoles = RunEscapeBank.read_roles("not json")
	var result: RunEscapeBank = RunEscapeBank.bank(state, state.advance({"power_cell": 1}), 0, 3, profile,
		store, roles, RunStatsRecorder.new())
	if result.crew_error != "no crew roles" or result.error != "":
		return "crew '%s', error '%s'" % [result.crew_error, result.error]
	if not profile.crew.is_empty() or profile.count_of("power_cell") != 1 or store.saves != 1:
		return "crew %d, banked %s, saves %d" % [profile.crew.size(), profile.banked, store.saves]
	return ""


func test_a_failed_save_is_the_error_and_is_noted_in_the_statistics() -> String:
	var state: RunState = _state()
	var store: CountingStore = _store()
	store.refuse = true
	var stats: RunStatsRecorder = RunStatsRecorder.new()
	var result: RunEscapeBank = RunEscapeBank.bank(state, state.advance({}), 0, 0, Profile.new(), store,
		null, stats)
	if result.error != "refused by the test" or not stats.error.contains("not saved"):
		return "error '%s', stats '%s'" % [result.error, stats.error]
	return ""
