class_name RunWiring
extends RefCounted

## Flies a run (#989, RUN-1, RUN-3, RUN-7, CRF-2): `--run=<n>` starts the run
## with seed `n`, each of its levels is the generated level for
## `RunState.current_level_seed()`, an escape goes on to the next level and banks
## the level's components into the profile, and a loss ends the run. After the
## last level, or a loss, the restart press starts a new run with a new seed.
##
## It sits beside `main.gd`, like `LevelStart`, because it reads the `net/`
## session's outcome and joins it to `meta/` banking. It never writes simulation
## state (MP-2): `main.gd` asks it which source to fly next and loads that level
## through `LevelStart`, as a restart always has. The run is built without a
## `ShaftOffer` for now, so `advance` never waits for a choice (the shaft choice
## screen is #990).

const RUN_FILE: String = "res://data/run/run.json"

## The run being flown; null when the launch flies a single level or the tunnel.
var state: RunState = null
## The last run that ended, won or lost, kept for its totals; null before one ends.
var ended: RunState = null
## Where banked components go; null until a run starts.
var profile: Profile = null
## Saves the profile after each escape; null saves nothing (tests).
var store: ProfileStore = null
## Picks the seed of each new run after the first; `LevelSwitch.random_seed`
## when not valid. Tests inject one.
var pick_seed: Callable = Callable()
## Told when the level flown is the run's last, so the escape screen says the
## run is won; null without a scene.
var escape_end: EscapeEndWiring = null
## The plan's data file; tests may point it elsewhere.
var run_file: String = RUN_FILE


func _init(p_store: ProfileStore = null) -> void:
	store = p_store


## What the launch flies: `source` unchanged unless it is `run:<n>`, which starts
## run `n` and gives its first level's source (`seed:<level seed>`). A run whose
## plan is rejected gives "", and the tunnel flies.
func begin(source: String, p_escape_end: EscapeEndWiring = null) -> String:
	escape_end = p_escape_end
	if not source.begins_with(LevelSwitch.RUN_PREFIX):
		return source
	return start_run(LevelSwitch.seed_from(source.substr(LevelSwitch.RUN_PREFIX.length())))


## Starts the run with `run_seed` from its first level and gives that level's
## source, or "" after printing why when the plan is rejected.
func start_run(run_seed: int) -> String:
	var plan: RunPlan = RunPlan.build(run_seed, FileAccess.get_file_as_string(run_file)) if run_seed >= 0 else null
	if plan == null or plan.error != "":
		print("Meltdown: run %d not started (%s); flying the test tunnel" % [
			run_seed, plan.error if plan != null else "not a seed"])
		state = null
		if escape_end != null:
			escape_end.run_won = false
		return ""
	state = RunState.new(plan)
	if profile == null:
		profile = store.load_profile() if store != null else Profile.new()
	return _level_source()


## True while a run is flown.
func is_active() -> bool:
	return state != null


## Called on the restart press with the outcome of the level that ended and the
## components its ship collected (a copy of the sim's `collected`); gives the
## source to fly next. An escape moves to the next level and banks; the last
## escape, or a loss, starts a new run. While the level still runs (a restart
## from the developer menu) it flies the same level again, as without a run.
func on_end(outcome: ExitRule.Outcome, collected: Dictionary, current_source: String) -> String:
	if state == null or outcome == ExitRule.Outcome.RUNNING:
		return current_source
	if outcome == ExitRule.Outcome.ESCAPED:
		_bank(state.advance(collected))
		if not state.won:
			return _level_source()
		print("Meltdown: run %d won; banked this run %s" % [state.plan.run_seed, state.banked])
	else:
		state.carry(collected)
		state.lose()
		print("Meltdown: run %d lost on level %d; banked this run %s" % [
			state.plan.run_seed, state.current_depth(), state.banked])
	ended = state
	var next_seed: int = pick_seed.call() if pick_seed.is_valid() else LevelSwitch.random_seed()
	print("Meltdown: flying random run %d" % next_seed)
	return start_run(next_seed)


func _bank(counts: Dictionary[String, int]) -> void:
	if state.error != "":
		print("Meltdown: escape not counted (%s)" % state.error)
		return
	var problem: String = RunBanking.bank_escape(profile, counts)
	if problem == "" and store != null and not counts.is_empty() and not store.save(profile):
		problem = store.message
	if problem != "":
		print("Meltdown: components not banked (%s)" % problem)


## The current level's source, printed, with the escape screen told whether it
## is the run's last.
func _level_source() -> String:
	var last: bool = state.level_index + 1 >= state.plan.level_count()
	if escape_end != null:
		escape_end.run_won = last
	print("Meltdown: run %d, level %d of %d, seed %d" % [state.plan.run_seed, state.current_depth(),
		state.plan.level_count(), state.current_level_seed()])
	return LevelSwitch.SEED_PREFIX + str(state.current_level_seed())
