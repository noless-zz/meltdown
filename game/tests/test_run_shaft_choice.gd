extends RefCounted

## Choosing a shaft between levels: the run waits for a choice after each
## escape but the last, and the choice sets the next level's seed and modifiers
## (#927, RUN-1, CRF-7).

const RUN: String = "res://data/run/run.json"
const SHAFTS: String = "res://data/run/shafts.json"


func _state(run_seed: int) -> RunState:
	var plan: RunPlan = RunPlan.build(run_seed, FileAccess.get_file_as_string(RUN))
	return RunState.new(plan, ShaftOffer.build(FileAccess.get_file_as_string(SHAFTS)))


func test_first_level_needs_no_choice() -> String:
	var state: RunState = _state(12345)
	if state.needs_choice() or not state.offer().is_empty() or state.choose("steady"):
		return "a choice was due before the first escape"
	if state.current_level_seed() != state.plan.level_seed(0):
		return "first level flies seed %d" % state.current_level_seed()
	if state.current_risk() != {"robot_count": 1.0, "alarm": 1.0} or not state.current_reward().is_empty():
		return "first level has shaft modifiers"
	return ""


func test_choice_sets_seed_and_modifiers() -> String:
	var state: RunState = _state(12345)
	state.advance()
	if not state.needs_choice() or state.advance():
		return "escaping did not wait for a shaft choice"
	var offered: Array[String] = state.offer()
	if offered != state.plan.offer_after(0, state.shafts):
		return "run offers %s, plan says %s" % [offered, state.plan.offer_after(0, state.shafts)]
	var missing: String = ""
	for kind: String in state.shafts.kinds:
		if not offered.has(kind):
			missing = kind
	if missing != "" and state.choose(missing):
		return "chose %s, which was not offered" % missing
	var kind: String = offered[0]
	if not state.choose(kind) or state.needs_choice() or state.current_shaft() != kind:
		return "choosing %s did not take" % kind
	if state.current_level_seed() != state.plan.level_seed_through(1, state.shafts, kind):
		return "level 1 does not fly the %s shaft's seed" % kind
	if state.current_risk() != state.shafts.risks[kind] or state.current_reward() != state.shafts.rewards[kind]:
		return "level 1 does not carry the %s shaft's modifiers" % kind
	if state.choose(offered[1]):
		return "a second choice into the same level took"
	return ""


func test_different_choices_give_different_next_levels() -> String:
	for run_seed: int in [0, 1, 12345]:
		var seeds: Dictionary = {}
		var offered: Array[String] = _state(run_seed).plan.offer_after(0, _state(run_seed).shafts)
		for kind: String in offered:
			var state: RunState = _state(run_seed)
			state.advance()
			state.choose(kind)
			if seeds.has(state.current_level_seed()):
				return "run seed %d: two shafts lead to seed %d" % [run_seed, state.current_level_seed()]
			seeds[state.current_level_seed()] = true
	return ""


func test_a_run_with_choices_still_wins() -> String:
	var state: RunState = _state(12345)
	var hashes: Dictionary = {state.state_hash(): true}
	for index: int in range(1, state.plan.level_count()):
		if not state.advance() or not state.choose(state.offer()[0]):
			return "could not reach level %d" % index
		if hashes.has(state.state_hash()):
			return "level %d repeats a state hash" % index
		hashes[state.state_hash()] = true
	if not state.advance() or not state.won or state.needs_choice():
		return "escaping the last level did not win"
	return ""


func test_a_run_without_shafts_needs_no_choice() -> String:
	var state: RunState = RunState.new(RunPlan.build(12345, FileAccess.get_file_as_string(RUN)))
	if not state.advance() or state.needs_choice() or not state.advance():
		return "a run without shafts waited for a choice"
	if state.current_level_seed() != state.plan.level_seed(2):
		return "a run without shafts changed the level seed"
	return ""
