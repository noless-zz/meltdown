extends RefCounted

## Gate G4's automated half, "bots complete full runs" (#1118, RUN-1, RUN-3,
## RUN-7, GEN-2, DEV-6): the bot pilot flies one pinned run seed through every
## level exactly as the run sweep does (`bot_run_sweep.gd`, robots and debris
## on, the ship file's tuning, the first offered shaft) and must complete it.
## The seed is the lowest in 1 to 50 the sweep completed when this was written,
## pinned in `fixtures/bot_full_run.json` (data, ARC-4). If a change stops the
## bot finishing it, this goes red; re-pin only with a reason in the devlog.
##
## The whole run takes about 18 s, so it is flown once. The second flight for
## ARC-2 repeats only the first two levels, with the same level seeds, and
## compares them with the first flight's (the CI unit test job is near its
## time limit, so the whole run is not flown twice).

const RunSweep := preload("res://tests/bot_run_sweep.gd")
const EscapeSweep := preload("res://tests/bot_escape_sweep.gd")
const Levels := preload("res://tests/bot_sweep_levels.gd")
const PINNED_FILE: String = "res://tests/fixtures/bot_full_run.json"
## RUN-1: a run is 3 to 5 levels.
const MIN_LEVELS: int = 3
const MAX_LEVELS: int = 5
## Levels flown a second time for the determinism check.
const REPEATED_LEVELS: int = 2

## Filled by the first test that needs it, so the run is flown once per file.
var _flown: RunSweep.RunResult = null
var _fly_level: Callable = Callable()
## [level index, level seed, result] for each level the first flight flew.
var _levels: Array = []
var _error: String = ""


func _pinned() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PINNED_FILE))
	if not (parsed is Dictionary) or not parsed.has("run_seed") or not parsed.has("planned_levels"):
		return {}
	return parsed


func _fly() -> String:
	if _flown != null or _error != "":
		return _error
	var pinned: Dictionary = _pinned()
	if pinned.is_empty():
		_error = "%s is missing or lacks run_seed and planned_levels" % PINNED_FILE
		return _error
	var levels: Levels = Levels.new(true, true)
	var broken: String = levels.broken()
	if broken != "":
		_error = broken
		return _error
	var shafts: ShaftOffer = ShaftOffer.build(FileAccess.get_file_as_string(RunSweep.SHAFTS_FILE))
	if shafts.error != "":
		_error = "shafts.json: %s" % shafts.error
		return _error
	_fly_level = RunSweep.bot_flies(levels)
	var recording: Callable = func(run_seed: int, index: int, level_seed: int) -> EscapeSweep.SeedResult:
		var result: EscapeSweep.SeedResult = _fly_level.call(run_seed, index, level_seed)
		_levels.append([index, level_seed, result])
		return result
	_flown = RunSweep.fly_run(int(pinned["run_seed"]), FileAccess.get_file_as_string(RunSweep.RUN_FILE),
			shafts, recording)
	if _flown.error != "":
		_error = _flown.error
	return _error


static func _describe(result: EscapeSweep.SeedResult) -> String:
	return "%s tick %d hash %d hull %.3f robots destroyed %d" % [result.outcome, result.tick,
			result.state_hash, result.hull, result.robots_destroyed]


func test_the_bot_completes_the_pinned_run() -> String:
	var problem: String = _fly()
	if problem != "":
		return problem
	var pinned: Dictionary = _pinned()
	if _flown.planned != int(pinned["planned_levels"]):
		return "run seed %d plans %d levels, pinned %d" % [_flown.run_seed, _flown.planned,
				int(pinned["planned_levels"])]
	if not _flown.completed():
		return "run seed %d not completed: %s" % [_flown.run_seed, _flown.line()]
	if _flown.flown != _flown.planned or _flown.escaped != _flown.planned:
		return "run seed %d flew %d and escaped %d of %d planned levels" % [_flown.run_seed,
				_flown.flown, _flown.escaped, _flown.planned]
	if _flown.escaped < MIN_LEVELS or _flown.escaped > MAX_LEVELS:
		return "escaped %d levels, RUN-1 wants %d to %d" % [_flown.escaped, MIN_LEVELS, MAX_LEVELS]
	return ""


func test_flying_the_first_levels_again_gives_the_same_results() -> String:
	var problem: String = _fly()
	if problem != "":
		return problem
	if _levels.size() < REPEATED_LEVELS:
		return "the first flight flew only %d levels" % _levels.size()
	for flown: Array in _levels.slice(0, REPEATED_LEVELS):
		var again: EscapeSweep.SeedResult = _fly_level.call(_flown.run_seed, flown[0], flown[1])
		var first: String = _describe(flown[2])
		if _describe(again) != first:
			return "level %d (seed %d): %s, then %s" % [flown[0], flown[1], first, _describe(again)]
	return ""
