class_name RunResume
extends RefCounted

## Turns a run into a `RunSave` and back (#1029, RUN-8), so the game side only
## stores and takes the save. It lives in `meta/` because `core/` may not know
## the save, and apart from `RunSave` because that class holds plain values only
## and does not depend on the run's state class.


## A save of `state`, which must `can_suspend()`, flying `ship` with `loadout`
## (ship data id and weapon slots as in `RunSave`). Refused, as an empty save
## with `error` set, when the run cannot be suspended now or a field would not
## read back.
static func to_save(state: RunState, ship: String, loadout: Dictionary) -> RunSave:
	var run: RunSave = RunSave.new()
	if not state.can_suspend():
		run.error = "the run cannot be suspended now: only between levels, with nothing carried"
		return run
	run.run_seed = state.plan.run_seed
	run.next_level = state.current_depth()
	run.ship = ship
	run.loadout = loadout.duplicate(true)
	run.chosen = state.chosen_so_far()
	var problem: String = run.check()
	if problem != "":
		var rejected: RunSave = RunSave.new()
		rejected.error = problem
		return rejected
	return run


## The run `run` suspended, rebuilt on `plan` (which the caller builds from the
## save's `run_seed`) with the shaft offer and component list it was flown
## with. On a refusal the state's `error` names the reason.
static func resume(run: RunSave, plan: RunPlan, shafts: ShaftOffer = null,
		components: ComponentList = null) -> RunState:
	if plan.run_seed != run.run_seed:
		var wrong: RunState = RunState.new(plan, shafts, components)
		wrong.error = "the plan is for run seed %d, the save for %d" % [plan.run_seed, run.run_seed]
		return wrong
	return RunState.resumed(plan, shafts, components, run.next_level, run.chosen)
