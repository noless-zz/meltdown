extends RefCounted

## Where a run stands: advancing through its levels, winning, losing (#926, RUN-1, RUN-7).

const SHIPPED: String = "res://data/run/run.json"


func _plan(run_seed: int) -> RunPlan:
	return RunPlan.build(run_seed, FileAccess.get_file_as_string(SHIPPED))


func test_starts_on_the_first_level() -> String:
	var plan: RunPlan = _plan(1)
	var state: RunState = RunState.new(plan)
	if state.level_index != 0 or state.current_depth() != 1 or state.is_over():
		return "fresh run at index %d, depth %d, over %s" % [state.level_index,
			state.current_depth(), state.is_over()]
	if state.current_level_seed() != plan.level_seed(0):
		return "fresh run flies seed %d, plan says %d" % [state.current_level_seed(),
			plan.level_seed(0)]
	return ""


func test_advancing_past_the_last_level_wins() -> String:
	for run_seed: int in [0, 1, 12345]:
		var plan: RunPlan = _plan(run_seed)
		var state: RunState = RunState.new(plan)
		for index: int in range(1, plan.level_count()):
			if not _advanced(state) or state.level_index != index or state.won:
				return "run seed %d: advance to level %d failed" % [run_seed, index]
			if state.current_level_seed() != plan.level_seed(index):
				return "run seed %d: level %d flies the wrong seed" % [run_seed, index]
		if not _advanced(state) or not state.won or state.lost:
			return "run seed %d: escaping the last level did not win" % run_seed
		if state.level_index != plan.level_count() - 1:
			return "run seed %d: a win left the index at %d" % [run_seed, state.level_index]
		if _advanced(state) or state.lose():
			return "run seed %d: a won run still changed" % run_seed
		if state.lost:
			return "run seed %d: a won run became lost" % run_seed
	return ""


func test_a_loss_ends_the_run() -> String:
	var state: RunState = RunState.new(_plan(12345))
	_advanced(state)
	if not state.lose() or not state.lost or not state.is_over() or state.won:
		return "losing did not end the run"
	if _advanced(state) or state.level_index != 1 or state.won:
		return "a lost run still advanced"
	return ""


func test_state_hash_follows_the_index_and_outcome() -> String:
	var state: RunState = RunState.new(_plan(12345))
	var start: int = state.state_hash()
	if RunState.new(_plan(12345)).state_hash() != start:
		return "two fresh runs of one seed hash differently"
	_advanced(state)
	var second: int = state.state_hash()
	if second == start:
		return "advancing left the hash unchanged"
	state.lose()
	if state.state_hash() == second:
		return "losing left the hash unchanged"
	if RunState.new(_plan(1)).state_hash() == start:
		return "fresh runs of two seeds hash alike"
	return ""


## True when the escape was taken; `advance` now returns the counts to bank.
func _advanced(state: RunState) -> bool:
	state.advance()
	return state.error == ""
