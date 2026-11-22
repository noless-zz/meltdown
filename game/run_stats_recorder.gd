class_name RunStatsRecorder
extends RefCounted

## Records a run's events in the profile's lifetime statistics (#1092, CRW-2,
## RUN-7): a run start, each escape with the miners that joined and the
## components banked on it, a lost ship and a won run. `RunWiring` holds one;
## single levels (`--level`, `--seed`, the dev menu) have no `RunWiring` and so
## record nothing.
##
## The statistics are a side record: a call that is refused or a save that
## fails is logged once per launch and never stops the run, so a broken or
## locked profile can not keep the pilot from flying (CRW-2).
##
## It sits beside `main.gd`, as `RunWiring` does, because it writes the `meta/`
## profile through the store the run already saves banks with.

const LOG_PREFIX: String = "[meltdown run]"

## The last recording failure; empty while every event was recorded and saved.
var error: String = ""
## Whether a failure was logged yet; later failures only set `error`.
var logged: bool = false


## A run started: records it in `profile` and saves through `store` (none
## keeps it in memory). False when it was not recorded or not saved.
func run_started(profile: Profile, store: ProfileStore) -> bool:
	return _saved(profile.stats.record_run_start(), "the run start", profile, store)


## The ship was lost: records the loss and saves it.
func run_lost(profile: Profile, store: ProfileStore) -> bool:
	return _saved(profile.stats.record_loss(), "the loss", profile, store)


## The last level was escaped: records the win and saves it.
func run_won(profile: Profile, store: ProfileStore) -> bool:
	return _saved(profile.stats.record_win(), "the win", profile, store)


## A level was escaped: records it in `profile` without saving, because the
## caller saves once for the escape together with its bank and crew.
## `level_index` is the run's 0-based index of the escaped level.
func escaped(profile: Profile, level_index: int, miners: int, banked: Dictionary) -> bool:
	if profile.stats.record_escape(level_index, miners, banked):
		return true
	fail("the escape of level %d was refused (miners %d, banked %s)" % [level_index + 1, miners, banked])
	return false


## Notes a failure: logs the first one, keeps the last in `error`.
func fail(problem: String) -> void:
	error = problem
	if logged:
		return
	logged = true
	print("%s: statistics not recorded: %s" % [LOG_PREFIX, problem])


func _saved(recorded: bool, what: String, profile: Profile, store: ProfileStore) -> bool:
	if not recorded:
		fail("%s was refused" % what)
		return false
	if store != null and not store.save(profile):
		fail("%s was not saved: %s" % [what, store.message])
		return false
	return true
