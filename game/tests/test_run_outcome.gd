extends RefCounted

## `RunOutcome`, the end-of-level bookkeeping split out of `RunWiring` (#1284,
## RUN-1, RUN-7, CRF-2), driven directly rather than through `after_level`:
## a run banks one escape and is then lost, and the banked components and the
## rescued miners' crew stay while a new run starts with a new seed, the facts
## `test_lost_run_rewarded.gd` checks end to end. Also a won run, a settled
## choice and the injected seed.

const THREE_LEVELS: String = "{\"min_levels\": 3, \"max_levels\": 3, \"seed_salt\": 2654435769}"
const RUN_SEED: int = 12345
const NEXT_RUN_SEED: int = 77
## A fixed copy of the roles (as in `test_lost_run_rewarded.gd`), so the crew
## pinned below does not move when the shipped roles file is tuned.
const ROLES_TEXT: String = """{"roles": [
	{"id": "surveyor", "name": "Surveyor", "weight": 30, "benefit": {"stat": "map_reveal", "amount": 1}},
	{"id": "shield_tech", "name": "Shield Technician", "weight": 25, "benefit": {"stat": "shield_max", "amount": 5}},
	{"id": "cargo_rigger", "name": "Cargo Rigger", "weight": 25, "benefit": {"stat": "salvage_slots", "amount": 1}},
	{"id": "reactor_hand", "name": "Reactor Hand", "weight": 20, "benefit": {"stat": "meltdown_seconds", "amount": 5}}
], "caps": {"map_reveal": 1, "meltdown_seconds": 20, "salvage_slots": 2, "shield_max": 25}}"""
const LEVEL_1_CARRY: Dictionary = {"scrap_alloy": 2, "cell_salts": 3}
const LEVEL_1_RESCUED: int = 2


## A three-level run without shafts, its profile kept in memory.
func _wiring(with_shafts: bool = false) -> RunWiring:
	var run: RunWiring = RunWiring.new(RUN_SEED, null, func() -> int: return NEXT_RUN_SEED,
		THREE_LEVELS, with_shafts)
	run.use_roles(ROLES_TEXT)
	return run


func _member(id: String, role: String) -> Dictionary:
	return {Profile.CREW_ID: id, Profile.CREW_ROLE: role}


func test_a_loss_after_one_escape_keeps_the_bank_and_crew_and_starts_a_new_run() -> String:
	var run: RunWiring = _wiring()
	if not run.active() or run.error != "":
		return "the run did not start: '%s'" % run.error
	var lost: RunState = run.state
	RunOutcome.bank(run, LEVEL_1_CARRY.duplicate(), LEVEL_1_RESCUED)
	if run.error != "" or run.crew_error != "" or lost.level_index != 1:
		return "the escape did not bank: '%s' '%s', index %d" % [run.error, run.crew_error, lost.level_index]
	RunOutcome.lose(run, "lost")
	var problems: Array[String] = []
	if run.ended != lost or not lost.lost or lost.won:
		problems.append("the ended run is not the lost one")
	for id: String in LEVEL_1_CARRY:
		if run.profile.count_of(id) != LEVEL_1_CARRY[id]:
			problems.append("%s: %d banked, expected %d" % [id, run.profile.count_of(id), LEVEL_1_CARRY[id]])
	var joined: Array[Dictionary] = [_member("crew-1", "surveyor"), _member("crew-2", "shield_tech")]
	if run.profile.crew != joined:
		problems.append("crew %s, expected %s" % [run.profile.crew, joined])
	if not run.active() or run.state == lost or run.state.plan.run_seed != NEXT_RUN_SEED:
		problems.append("no new run with seed %d" % NEXT_RUN_SEED)
	elif run.state.level_index != 0 or run.state.banked.size() != 0:
		problems.append("the new run starts on index %d with %s banked" % [run.state.level_index,
			run.state.banked])
	return "\n".join(problems)


func test_a_win_keeps_the_ended_run_and_starts_a_new_one() -> String:
	var run: RunWiring = _wiring()
	var won: RunState = run.state
	for i: int in 3:
		RunOutcome.bank(run, {"scrap_alloy": 1}, 0)
	if not won.won:
		return "three escapes did not win the run"
	RunOutcome.win(run)
	if run.ended != won or run.state == won or run.state.plan.run_seed != NEXT_RUN_SEED:
		return "the win did not end the run and start seed %d" % NEXT_RUN_SEED
	if run.profile.count_of("scrap_alloy") != 3:
		return "banked %d scrap_alloy, expected 3" % run.profile.count_of("scrap_alloy")
	return ""


func test_settling_a_due_choice_takes_the_first_offered_shaft() -> String:
	var run: RunWiring = _wiring(true)
	if run.shafts == null:
		return "the shipped shaft file was rejected"
	RunOutcome.bank(run, {}, 0)
	if not run.state.needs_choice():
		return "no choice due after the first escape"
	var first: String = run.state.offer()[0]
	RunOutcome.settle_choice(run)
	if run.state.needs_choice() or run.state.current_shaft() != first:
		return "shaft %s taken, expected %s" % [run.state.current_shaft(), first]
	return ""


func test_the_new_seed_is_the_injected_one() -> String:
	var run: RunWiring = _wiring()
	if RunOutcome.new_seed(run) != NEXT_RUN_SEED:
		return "new seed %d, expected %d" % [RunOutcome.new_seed(run), NEXT_RUN_SEED]
	return ""
