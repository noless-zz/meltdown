extends RefCounted

## Components carried on a level are banked on its escape and lost with the
## ship; banking puts them into the profile (#977, CRF-2, RUN-7, ARC-2).

const RUN: String = "res://data/run/run.json"
## `RunState.new(<plan of seed 12345>).state_hash()` before components joined
## the run; a run that never carries one must keep it.
const NO_COMPONENT_HASH: int = 2172357997
## The same run after one escape that banked nothing.
const NO_COMPONENT_HASH_LEVEL_2: int = 2633840699


func _components() -> ComponentList:
	var texts: Dictionary = {}
	for file: String in DirAccess.get_files_at(ComponentList.COMPONENTS_DIR):
		if file.ends_with(".json"):
			texts[file] = FileAccess.get_file_as_string(ComponentList.COMPONENTS_DIR.path_join(file))
	return ComponentList.parse(texts)


func _state(run_seed: int = 12345) -> RunState:
	var plan: RunPlan = RunPlan.build(run_seed, FileAccess.get_file_as_string(RUN))
	return RunState.new(plan, null, _components())


func test_components_load() -> String:
	var list: ComponentList = _components()
	if list.error != "" or not list.has_kind("scrap_alloy") or not list.has_kind("core_glass"):
		return "component list did not load: %s" % list.error
	return ""


func test_escape_banks_the_carry() -> String:
	var state: RunState = _state()
	if state.carry({"scrap_alloy": 2}) != "" or state.carried != {"scrap_alloy": 2}:
		return "carry was not held: %s" % state.error
	var to_bank: Dictionary[String, int] = state.advance({"scrap_alloy": 3, "core_glass": 0})
	if state.error != "" or to_bank != {"scrap_alloy": 3}:
		return "escape handed over %s (%s)" % [to_bank, state.error]
	if not state.carried.is_empty() or state.banked != {"scrap_alloy": 3} or state.level_index != 1:
		return "after escape: carried %s, banked %s, index %d" % [state.carried, state.banked, state.level_index]
	var profile: Profile = Profile.new()
	var problem: String = RunBanking.bank_escape(profile, to_bank)
	if problem != "" or profile.count_of("scrap_alloy") != 3:
		return "profile banked %d (%s)" % [profile.count_of("scrap_alloy"), problem]
	return ""


func test_escape_without_counts_banks_what_was_carried() -> String:
	var state: RunState = _state()
	state.carry({"cell_salts": 4})
	var to_bank: Dictionary[String, int] = state.advance()
	if to_bank != {"cell_salts": 4} or not state.carried.is_empty():
		return "bare advance handed over %s, left %s" % [to_bank, state.carried]
	return ""


func test_loss_loses_only_the_current_carry() -> String:
	var state: RunState = _state()
	var profile: Profile = Profile.new()
	RunBanking.bank_escape(profile, state.advance({"circuit_shards": 2}))
	if state.carry({"circuit_shards": 5, "scrap_alloy": 1}) != "":
		return "carry refused: %s" % state.error
	if not state.lose():
		return "loss refused"
	if not state.carried.is_empty() or state.banked != {"circuit_shards": 2}:
		return "after loss: carried %s, banked %s" % [state.carried, state.banked]
	if profile.count_of("circuit_shards") != 2 or profile.count_of("scrap_alloy") != 0:
		return "the loss took back banked components: %s" % profile.to_json()
	if not state.advance({"scrap_alloy": 1}).is_empty() or state.error == "":
		return "a lost run still banked"
	if state.carry({"scrap_alloy": 1}) == "":
		return "a lost run still carried"
	return ""


func test_three_level_run_banks_the_sum() -> String:
	var state: RunState = _state()
	if state.plan.level_count() < 3:
		return "plan has %d levels" % state.plan.level_count()
	var levels: Array[Dictionary] = [
		{"scrap_alloy": 2, "cell_salts": 1},
		{"scrap_alloy": 5},
		{"core_glass": 1, "cell_salts": 3},
	]
	var profile: Profile = Profile.new()
	for counts: Dictionary in levels:
		var problem: String = RunBanking.bank_escape(profile, state.advance(counts))
		if state.error != "" or problem != "":
			return "escape refused: %s %s" % [state.error, problem]
	var expected: Dictionary[String, int] = {"scrap_alloy": 7, "cell_salts": 4, "core_glass": 1}
	if state.banked != expected:
		return "run banked %s, expected %s" % [state.banked, expected]
	for id: String in expected:
		if profile.count_of(id) != expected[id]:
			return "profile holds %d %s, expected %d" % [profile.count_of(id), id, expected[id]]
	return ""


func test_unknown_component_is_an_error_naming_it() -> String:
	var state: RunState = _state()
	var refused: String = state.carry({"scrap_alloy": 1, "unobtainium": 2})
	if not refused.contains("unobtainium") or not state.carried.is_empty():
		return "carry of an unknown kind gave \"%s\", carried %s" % [refused, state.carried]
	var hash_before: int = state.state_hash()
	var to_bank: Dictionary[String, int] = state.advance({"unobtainium": 2})
	if not to_bank.is_empty() or not state.error.contains("unobtainium"):
		return "escape with an unknown kind gave %s, error \"%s\"" % [to_bank, state.error]
	if state.level_index != 0 or state.state_hash() != hash_before:
		return "a refused escape changed the run"
	if not state.carry({"scrap_alloy": -1}).contains("scrap_alloy"):
		return "a negative count was not refused by name"
	return ""


func test_bank_escape_refusal_leaves_the_profile_unchanged() -> String:
	var profile: Profile = Profile.new()
	RunBanking.bank_escape(profile, {"scrap_alloy": 3})
	var before: String = profile.to_json()
	for bad: Dictionary in [{"core_glass": 1, "scrap_alloy": -1}, {"": 1}, {"core_glass": 1.5}]:
		if RunBanking.bank_escape(profile, bad) == "":
			return "bad counts %s were banked" % [bad]
		if profile.to_json() != before:
			return "a refused bank changed the profile: %s" % profile.to_json()
	if RunBanking.bank_escape(null, {"scrap_alloy": 1}) == "":
		return "banking into no profile did not refuse"
	return ""


func test_hash_without_components_is_unchanged() -> String:
	var state: RunState = _state()
	if state.state_hash() != NO_COMPONENT_HASH:
		return "a run with no components hashes %d, expected %d" % [state.state_hash(), NO_COMPONENT_HASH]
	state.carry({})
	state.advance({})
	if state.state_hash() != NO_COMPONENT_HASH_LEVEL_2:
		return "an escape with nothing hashes %d, expected %d" % [state.state_hash(), NO_COMPONENT_HASH_LEVEL_2]
	return ""


func test_components_join_the_hash() -> String:
	var plain: RunState = _state()
	var carrying: RunState = _state()
	carrying.carry({"scrap_alloy": 1})
	if carrying.state_hash() == plain.state_hash():
		return "the carry is not in the hash"
	var a: RunState = _state()
	var b: RunState = _state()
	a.advance({"scrap_alloy": 2, "core_glass": 1})
	b.advance({"core_glass": 1, "scrap_alloy": 2})
	if a.state_hash() != b.state_hash():
		return "key order changed the hash"
	plain.advance({"scrap_alloy": 2})
	if plain.state_hash() == a.state_hash():
		return "banked counts are not in the hash"
	return ""


func test_same_inputs_same_hash() -> String:
	var hashes: Array[int] = []
	for attempt: int in 2:
		var state: RunState = _state(777)
		state.carry({"cell_salts": 1})
		state.advance({"cell_salts": 2, "scrap_alloy": 1})
		state.carry({"core_glass": 1})
		state.lose()
		hashes.append(state.state_hash())
	if hashes[0] != hashes[1]:
		return "same inputs hashed %d and %d" % [hashes[0], hashes[1]]
	return ""


func test_a_suspend_save_after_escape_carries_nothing() -> String:
	var state: RunState = _state()
	if state.can_suspend():
		return "a run may be suspended before its first escape"
	state.carry({"scrap_alloy": 2})
	var to_bank: Dictionary[String, int] = state.advance()
	if not state.can_suspend() or not state.carried.is_empty() or to_bank != {"scrap_alloy": 2}:
		return "after escape: suspend %s, carried %s" % [state.can_suspend(), state.carried]
	var save: RunSave = RunSave.new()
	save.run_seed = state.plan.run_seed
	save.next_level = state.current_depth()
	save.ship = "default_ship"
	save.loadout = {"primary": ["pulse_cannon", ""], "secondary": ["", ""]}
	if save.check() != "" or save.next_level != 2:
		return "save after escape: %s, next level %d" % [save.check(), save.next_level]
	var read: RunSave = RunSave.parse_json(save.to_json())
	var resumed: RunState = _state()
	for level: int in range(1, read.next_level):
		resumed.advance()
	if not resumed.carried.is_empty() or not resumed.banked.is_empty():
		return "a resumed run carries %s" % resumed.carried
	state.carry({"core_glass": 1})
	if state.can_suspend():
		return "a run may be suspended while it carries components"
	state.lose()
	if state.can_suspend():
		return "a lost run may be suspended"
	return ""
