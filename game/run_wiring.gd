class_name RunWiring
extends RefCounted

## Flies a run in the game (#989, RUN-1, RUN-3, RUN-7, CRF-2): owns the
## `RunState` built from `data/run/run.json` for `--run=<n>` and says which
## level the main scene flies next, as the source `seed:<level seed>` that
## `LevelStart.source` flies, plus `:robots=<scale>` when its shaft scales the
## robots (#1011).
##
## On an end screen's restart press `after_level` reads the ended session: an
## escape banks the level (`RunEscapeBank`, #1136) and flies the next, or wins
## the run after the last; a lost ship drops the level's unbanked components,
## earlier escapes stay banked (RUN-7); a win or loss starts a new run with a
## new seed. Neither (the dev menu's Restart) flies the same level again.
##
## Between levels the pilot picks a shaft (#990, CRF-7) from the `ShaftOffer` in
## `data/run/shafts.json`: `escape_for_choice` advances and banks at once and
## hands back the offer, the panel's confirm calls `choose`, and the restart
## after it flies the chosen level. A restart with no choice made takes the
## first offered shaft. A rejected shaft file, or `with_shafts` false, runs
## without a choice.
##
## It sits beside `main.gd` because it reads the `net/` session's outcome and
## `collected` counts; it only hands back a level source for `main.gd` (MP-2).

const RUN_FILE: String = "res://data/run/run.json"
const SHAFTS_FILE: String = "res://data/run/shafts.json"
const LOG_PREFIX: String = "Meltdown: run"

## The run being flown; null once `stop` has left the run.
var state: RunState = null
## Where escapes bank; held for the whole launch.
var profile: Profile = null
## Saves `profile` after each bank; null keeps the profile in memory only (tests).
var store: ProfileStore = null
## Picks a new run's seed (`LevelSwitch.random_seed` when not set); tests inject one.
var pick_seed: Callable = Callable()
## The run data file's text; tests may hand in their own.
var run_text: String = ""
## The run that ended last, won or lost, kept so its banked counts can be read.
var ended: RunState = null
## Why the last start, advance or bank went wrong; empty when all went well.
var error: String = ""
## The shafts offered between levels; null for a run without a choice.
var shafts: ShaftOffer = null
## True from `escape_for_choice` until the restart it leads to: the level
## flown was escaped and the run has already moved on.
var escape_taken: bool = false
## Whether the run's levels drop components and let miners be rescued
## (`RunLevelRules`, #1028). The game keeps it on; an acceptance run step
## turns it off unless it checks them, so its pinned hashes stand.
var level_rules: bool = true
## The roles rescued miners are given (#1032); one with `error` set adds no crew.
var roles: CrewRoles = null
## Why the last escape added no crew although miners were rescued; empty otherwise.
var crew_error: String = ""
## The fitted ship each of the run's levels flies, from `profile` and `roles` (#1057).
var ship: RunShip = RunShip.new()
## Records the run's events in the profile's statistics (#1092).
var stats: RunStatsRecorder = RunStatsRecorder.new()


## A run for `run_seed`. `p_store` is read for the profile and written after
## each bank; without one the profile starts empty and stays in memory.
## `with_shafts` false runs without a shaft choice; `p_shafts_text` replaces
## the shaft file's text (tests).
func _init(run_seed: int, p_store: ProfileStore = null, p_pick_seed: Callable = Callable(),
		p_run_text: String = "", with_shafts: bool = true, p_shafts_text: String = "") -> void:
	store = p_store
	pick_seed = p_pick_seed
	run_text = p_run_text if p_run_text != "" else _read(RUN_FILE)
	if with_shafts:
		shafts = ShaftOffer.build(p_shafts_text if p_shafts_text != "" else _read(SHAFTS_FILE))
		if shafts.error != "":
			print("%s: %s rejected, flying without a shaft choice: %s" % [LOG_PREFIX, SHAFTS_FILE, shafts.error])
			shafts = null
	use_roles(_read(CrewRoles.ROLES_FILE))
	profile = store.load_profile() if store != null else Profile.new()
	if store != null and store.message != "":
		print("%s: %s" % [LOG_PREFIX, store.message])
	start(run_seed)


## Starts the run with seed `run_seed` from its first level. False, with
## `error` set and no run, when the run data file is rejected.
func start(run_seed: int) -> bool:
	var plan: RunPlan = RunPlan.build(run_seed, run_text)
	if plan.error != "":
		error = "%s rejected: %s" % [RUN_FILE, plan.error]
		print("%s: %s" % [LOG_PREFIX, error])
		state = null
		return false
	state = RunState.new(plan, shafts)
	error = ""
	escape_taken = false
	print("%s %d: %d levels, flying level 1 (seed %d)" % [LOG_PREFIX, run_seed, plan.level_count(),
		state.current_level_seed()])
	stats.run_started(profile, store)
	return true


## Reads the crew roles from `text`, the roles file's text (tests hand in
## their own). A rejected file logs one line; escapes then add no crew.
func use_roles(text: String) -> void:
	roles = RunEscapeBank.read_roles(text)


## How many miners `sim` has rescued so far; 0 when it flies without rescue.
static func rescued_in(sim: Sim) -> int:
	return sim.rescue.rescued if sim.rescue != null else 0


## Whether a run is being flown.
func active() -> bool:
	return state != null and not state.is_over()


## The tier weights the current level's drops roll with (#1000, CRF-7): the
## chosen shaft's `reward.tier_weights`, or empty for the first level, a run
## without shafts, or no run.
func level_reward() -> Array[float]:
	return state.current_reward() if active() else ([] as Array[float])


## The robot count scale the current level is built with (#1011, RUN-1, GEN-2):
## the chosen shaft's `risk.robot_count`, or 1.0 for the first level, a run
## without shafts, or no run.
func level_robot_scale() -> float:
	return float(state.current_risk()["robot_count"]) if active() else 1.0


## The level source of the run's current level, or "" without a run:
## `seed:<n>`, with `:robots=<scale>` when its shaft scales the robots (#1011).
func level_source() -> String:
	return LevelSwitch.seed_source(state.current_level_seed(), level_robot_scale()) if active() else ""


## True when the level flown now is the run's last: escaping it wins the run.
func on_last_level() -> bool:
	return active() and state.level_index == state.plan.level_count() - 1


## True when escaping the level flown now leads to a shaft choice: the run
## has shafts and this is not its last level (#990).
func choice_due_after_escape() -> bool:
	return active() and shafts != null and not escape_taken and not on_last_level()


## The escape screen's press after a level that leads to a choice: moves the
## run on, banks `collected` and adds the `rescued` miners to the crew now, and
## returns the shafts offered, in `RunState.offer()` order. Empty, changing
## nothing, when no choice is due.
func escape_for_choice(collected: Dictionary, rescued: int = 0) -> Array[String]:
	if not choice_due_after_escape():
		return []
	_bank(collected, rescued)
	escape_taken = true
	return state.offer()


## Takes shaft `kind` into the next level; false when it is not on offer.
func choose(kind: String) -> bool:
	if not active() or not state.choose(kind):
		return false
	print("%s %d: shaft %s chosen into level %d (seed %d)" % [LOG_PREFIX, state.plan.run_seed, kind,
		state.current_depth(), state.current_level_seed()])
	return true


## True when a session with `outcome` and ship `hull` has ended its level:
## escaped, or the ship is lost.
static func ends_level(outcome: int, hull: float) -> bool:
	return outcome == ExitRule.Outcome.ESCAPED or hull <= 0.0


## Called on the restart press with the ended session's outcome, ship hull,
## `collected` counts and `rescued` miners. Moves the run on as the class
## comment says and returns the level source to fly next.
func after_level(outcome: int, hull: float, collected: Dictionary, rescued: int = 0) -> String:
	if not active():
		return ""
	if outcome == ExitRule.Outcome.ESCAPED and escape_taken:
		escape_taken = false
		_settle_choice()
	elif outcome == ExitRule.Outcome.ESCAPED:
		_bank(collected, rescued)
		_settle_choice()
		if state.won:
			print("%s %d won after %d levels; banked %s" % [LOG_PREFIX, state.plan.run_seed,
				state.plan.level_count(), state.banked])
			ended = state
			stats.run_won(profile, store)
			start(_new_seed())
		else:
			print("%s %d: level %d escaped, flying level %d (seed %d)" % [LOG_PREFIX, state.plan.run_seed,
				state.level_index, state.current_depth(), state.current_level_seed()])
	elif hull <= 0.0:
		state.lose()
		stats.run_lost(profile, store)
		print("%s %d lost on level %d; banked %s" % [LOG_PREFIX, state.plan.run_seed, state.current_depth(),
			state.banked])
		ended = state
		start(_new_seed())
	return level_source()


## The source after a session ended with `session`: the run's next level when
## it ended its level, otherwise the current one again.
func after_session(session: LocalSession) -> String:
	return after_level(session.sim.outcome(), session.current_ship().hull, session.sim.collected.duplicate(),
		rescued_in(session.sim))


## Leaves the run: the dev menu chose another level.
func stop() -> void:
	if state != null:
		print("%s %d left on level %d" % [LOG_PREFIX, state.plan.run_seed, state.current_depth()])
	state = null


## A level is never flown while a choice is due: with none made, the first
## offered shaft is taken.
func _settle_choice() -> void:
	if state.needs_choice():
		var offered: Array[String] = state.offer()
		print("%s %d: no shaft chosen, taking %s" % [LOG_PREFIX, state.plan.run_seed, offered[0]])
		choose(offered[0])


## Advances past the escaped level and banks its `collected` components and
## `rescued` miners through `RunEscapeBank` (#1136).
func _bank(collected: Dictionary, rescued: int) -> void:
	var escaped_index: int = state.level_index
	var banked: RunEscapeBank = RunEscapeBank.bank(state, state.advance(collected), escaped_index, rescued,
		profile, store, roles, stats)
	if banked.error != "":
		error = banked.error
	if not banked.refused:
		crew_error = banked.crew_error


func _new_seed() -> int:
	var picked: int = int(pick_seed.call()) if pick_seed.is_valid() else LevelSwitch.random_seed()
	print("%s: new run with seed %d" % [LOG_PREFIX, picked])
	return picked


static func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
