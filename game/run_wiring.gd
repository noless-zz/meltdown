class_name RunWiring
extends RefCounted

## Flies a run in the game (#989, RUN-1, RUN-3, RUN-7, CRF-2): owns the
## `RunState` built from `data/run/run.json` for `--run=<n>` and says which
## level the main scene flies next. Each level of the run is the generated
## level `SeedLevel` builds for `RunState.current_level_seed()`, so its source
## is `seed:<level seed>`, the form `LevelStart.source` already flies.
##
## When an end screen's restart press ends a level, `after_level` reads the
## ended session's outcome, ship hull and collected components:
##
## - Escaped: `RunState.advance` hands over the level's components, which are
##   banked into the profile (`RunBanking`, #977) and saved, and the run moves
##   to its next level. After the last level the run is won and a new run
##   starts with a new seed.
## - Ship lost: `RunState.lose` drops the level's unbanked components; earlier
##   escapes stay banked. A new run starts with a new seed.
## - Neither (the dev menu's Restart while flying): the same level again.
##
## Between levels the pilot picks a shaft (#990, RUN-1, CRF-7): the run holds
## the `ShaftOffer` from `data/run/shafts.json`. When the escape screen's press
## comes after a level that is not the last, `escape_for_choice` advances and
## banks at once and hands back the offer; the shaft panel's confirm calls
## `choose`, and the restart that follows flies the chosen shaft's level
## (`after_level` sees the escape was already taken). A restart press that
## reaches `after_level` with no choice made takes the first offered shaft, so a
## level never flies while a choice is due. A rejected shaft file, or
## `with_shafts` false, runs without a choice as #989 did.
##
## It sits beside `main.gd` because it reads the `net/` session's outcome and
## the sim's `collected` counts; it only reads them and hands back a level
## source for `main.gd` to load, as `EscapeEndWiring` hands back a restart (MP-2).

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
	return true


## Whether a run is being flown.
func active() -> bool:
	return state != null and not state.is_over()


## The level source of the run's current level, `seed:<n>`, or "" without a run.
func level_source() -> String:
	return LevelSwitch.SEED_PREFIX + str(state.current_level_seed()) if active() else ""


## True when the level flown now is the run's last: escaping it wins the run.
func on_last_level() -> bool:
	return active() and state.level_index == state.plan.level_count() - 1


## True when escaping the level flown now leads to a shaft choice: the run
## has shafts and this is not its last level (#990).
func choice_due_after_escape() -> bool:
	return active() and shafts != null and not escape_taken and not on_last_level()


## The escape screen's press after a level that leads to a choice: moves the
## run on and banks `collected` now, and returns the shafts offered, in
## `RunState.offer()` order. Empty, changing nothing, when no choice is due.
func escape_for_choice(collected: Dictionary) -> Array[String]:
	if not choice_due_after_escape():
		return []
	_bank(state.advance(collected))
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


## Called on the restart press with the ended session's outcome, ship hull and
## `collected` counts. Moves the run on as the class comment says and returns
## the level source to fly next.
func after_level(outcome: int, hull: float, collected: Dictionary) -> String:
	if not active():
		return ""
	if outcome == ExitRule.Outcome.ESCAPED and escape_taken:
		escape_taken = false
		_settle_choice()
	elif outcome == ExitRule.Outcome.ESCAPED:
		_bank(state.advance(collected))
		_settle_choice()
		if state.won:
			print("%s %d won after %d levels; banked %s" % [LOG_PREFIX, state.plan.run_seed,
				state.plan.level_count(), state.banked])
			ended = state
			start(_new_seed())
		else:
			print("%s %d: level %d escaped, flying level %d (seed %d)" % [LOG_PREFIX, state.plan.run_seed,
				state.level_index, state.current_depth(), state.current_level_seed()])
	elif hull <= 0.0:
		state.lose()
		print("%s %d lost on level %d; banked %s" % [LOG_PREFIX, state.plan.run_seed, state.current_depth(),
			state.banked])
		ended = state
		start(_new_seed())
	return level_source()


## The source after a session ended with `session`: the run's next level when
## it ended its level, otherwise the current one again.
func after_session(session: LocalSession) -> String:
	return after_level(session.sim.outcome(), session.current_ship().hull, session.sim.collected.duplicate())


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


func _bank(counts: Dictionary[String, int]) -> void:
	if state.error != "":
		error = "the escape was refused: %s" % state.error
		print("%s: %s" % [LOG_PREFIX, error])
		return
	if counts.is_empty():
		return
	var problem: String = RunBanking.bank_escape(profile, counts)
	if problem == "" and store != null and not store.save(profile):
		problem = store.message
	if problem != "":
		error = problem
		print("%s: %s" % [LOG_PREFIX, problem])


func _new_seed() -> int:
	var picked: int = int(pick_seed.call()) if pick_seed.is_valid() else LevelSwitch.random_seed()
	print("%s: new run with seed %d" % [LOG_PREFIX, picked])
	return picked


static func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
