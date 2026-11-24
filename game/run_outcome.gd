class_name RunOutcome
extends RefCounted

## End-of-level bookkeeping for `RunWiring` (#1284, RUN-1, RUN-7, CRF-2): an
## escape banks through `RunEscapeBank`, a pending shaft choice is settled
## before a level is flown, a won or lost run is kept in `ended` and the next
## run starts with a new seed. Split out of `run_wiring.gd` to keep it under
## 300 lines (ARC-5); every function works on the `RunWiring` it is handed, so
## the run's state stays in one place and its log lines are unchanged.


## Ends `run`'s run as lost (`how` names the way in the log) and starts the
## next with a new seed; one path for a destroyed ship and an abandoned run.
## Earlier escapes stay banked (RUN-7).
static func lose(run: RunWiring, how: String) -> void:
	run.state.lose()
	run.stats.run_lost(run.profile, run.store)
	print("%s %d %s on level %d; banked %s" % [RunWiring.LOG_PREFIX, run.state.plan.run_seed, how,
		run.state.current_depth(), run.state.banked])
	run.ended = run.state
	run.start(new_seed(run))


## Ends `run`'s run as won after its last level and starts the next with a new seed.
static func win(run: RunWiring) -> void:
	print("%s %d won after %d levels; banked %s" % [RunWiring.LOG_PREFIX, run.state.plan.run_seed,
		run.state.plan.level_count(), run.state.banked])
	run.ended = run.state
	run.stats.run_won(run.profile, run.store)
	run.start(new_seed(run))


## A level is never flown while a choice is due: with none made, the first
## offered shaft is taken.
static func settle_choice(run: RunWiring) -> void:
	if run.state.needs_choice():
		var offered: Array[String] = run.state.offer()
		print("%s %d: no shaft chosen, taking %s" % [RunWiring.LOG_PREFIX, run.state.plan.run_seed, offered[0]])
		run.choose(offered[0])


## Advances `run` past the escaped level and banks its `collected` components
## and `rescued` miners through `RunEscapeBank` (#1136).
static func bank(run: RunWiring, collected: Dictionary, rescued: int) -> void:
	var escaped_index: int = run.state.level_index
	var banked: RunEscapeBank = RunEscapeBank.bank(run.state, run.state.advance(collected), escaped_index,
		rescued, run.profile, run.store, run.roles, run.stats)
	if banked.error != "":
		run.error = banked.error
	if not banked.refused:
		run.crew_error = banked.crew_error


## The seed of `run`'s next run: its injected `pick_seed`, or `LevelSwitch.random_seed`.
static func new_seed(run: RunWiring) -> int:
	var picked: int = int(run.pick_seed.call()) if run.pick_seed.is_valid() else LevelSwitch.random_seed()
	print("%s: new run with seed %d" % [RunWiring.LOG_PREFIX, picked])
	return picked
