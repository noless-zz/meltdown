extends SceneTree

## Flies the bot pilot through whole runs and sums up how many it finishes
## (#1009, RUN-1, RUN-3, RUN-7, GEN-2, DEV-6): gate G4 asks that bots complete
## full runs, and `bot_escape_sweep.gd` flies single levels only. Each run seed
## builds a `RunPlan` from `data/run/run.json` and a `RunState` with the shipped
## `ShaftOffer`, then flies its 3 to 5 levels one after another, every level
## built and flown exactly as `bot_escape_sweep.gd --robots --debris` builds
## and flies it (`bot_sweep_levels.gd`, `BotEscapeSweep.fly`):
##
##     godot --headless --path game -s res://tests/bot_run_sweep.gd -- --runs=100 --first=1
##
## Options: `--runs=N` (default 100), `--first=S` (first run seed, default 1).
## Where the run waits for a shaft choice the sweep takes the first shaft
## offered, so a run seed always flies the same levels. An escape calls
## `advance`; anything else (ship destroyed, countdown run out, still flying at
## the tick limit, or a level that could not be flown) calls `lose` and ends
## the run. A run is complete once `is_over` after its last escape.
##
## Prints one `MELTDOWN_BOT_RUN` line per run, then
## `MELTDOWN_BOT_RUNS {"runs":N,"completed":C,"rate":r,"levels_flown":L,"levels_escaped":E}`.
## The gate has no bar for this rate yet, so it is reported, not judged: the
## exit code is 0 unless a run seed fails to build (a broken data file) or the
## summary cannot be printed. A shaft's robot-count risk is not applied yet;
## every level is built at the shipped robot counts.

const EscapeSweep := preload("res://tests/bot_escape_sweep.gd")
const Levels := preload("res://tests/bot_sweep_levels.gd")
const RUN_FILE: String = "res://data/run/run.json"
const SHAFTS_FILE: String = "res://data/run/shafts.json"
const RUN_TAG: String = "MELTDOWN_BOT_RUN"
const SUMMARY_TAG: String = "MELTDOWN_BOT_RUNS"


## How one run went.
class RunResult extends RefCounted:
	var run_seed: int = 0
	var planned: int = 0
	var flown: int = 0
	var escaped: int = 0
	## "completed", or how the last level flown ended: an `ExitRule.Outcome`
	## name or "NO_LEVEL" / "NO_REACTOR", then " ship destroyed" when it was.
	var ended: String = ""
	## The shaft taken into each level after the first, in order.
	var shafts: Array[String] = []
	## Why the run seed could not be built; empty when it was.
	var error: String = ""

	func completed() -> bool:
		return ended == "completed"

	func line() -> String:
		return '%s {"seed":%d,"planned":%d,"flown":%d,"escaped":%d,"ended":"%s"}' % [
				RUN_TAG, run_seed, planned, flown, escaped, ended]


## Flies one run. `fly_level` takes (run seed, level index, level seed) and
## returns an `EscapeSweep.SeedResult`; the sweep passes the bot, a test a stub.
static func fly_run(run_seed: int, run_text: String, shafts: ShaftOffer,
		fly_level: Callable) -> RunResult:
	var result: RunResult = RunResult.new()
	result.run_seed = run_seed
	var plan: RunPlan = RunPlan.build(run_seed, run_text)
	if plan.error != "":
		result.error = "run.json: %s" % plan.error
		return result
	result.planned = plan.level_count()
	var state: RunState = RunState.new(plan, shafts)
	while not state.is_over():
		if state.needs_choice():
			var kind: String = state.offer()[0]
			state.choose(kind)
			result.shafts.append(kind)
		var flown: EscapeSweep.SeedResult = fly_level.call(run_seed, state.level_index,
				state.current_level_seed())
		result.flown += 1
		if flown.escaped:
			result.escaped += 1
			state.advance()
		else:
			state.lose()
			result.ended = flown.outcome + (" ship destroyed" if flown.destroyed else "")
	if state.won:
		result.ended = "completed"
	return result


## Run seeds `first_seed` to `first_seed + count - 1`. With no `fly_level` the
## bot flies each level with robots and debris on. The result holds "runs",
## "completed", "rate", "levels_flown", "levels_escaped", "lines" (one
## `MELTDOWN_BOT_RUN` line per run) and "errors" (why a run seed or a data file
## could not be built).
static func run(first_seed: int, count: int, fly_level: Callable = Callable()) -> Dictionary:
	var result: Dictionary = {"runs": count, "completed": 0, "rate": 0.0, "levels_flown": 0,
			"levels_escaped": 0, "lines": [] as Array[String], "errors": [] as Array[String]}
	var run_text: String = FileAccess.get_file_as_string(RUN_FILE)
	var shafts: ShaftOffer = ShaftOffer.build(FileAccess.get_file_as_string(SHAFTS_FILE))
	if shafts.error != "":
		result["errors"].append("shafts.json: %s" % shafts.error)
		return result
	if not fly_level.is_valid():
		var levels: Levels = Levels.new(true, true)
		var broken: String = levels.broken()
		if broken != "":
			result["errors"].append(broken)
			return result
		fly_level = func(_run_seed: int, _index: int, level_seed: int) -> EscapeSweep.SeedResult:
			return EscapeSweep.fly(level_seed, levels.level_of(levels.generate(level_seed)),
					levels.tuning)
	for run_seed: int in range(first_seed, first_seed + count):
		var flown: RunResult = fly_run(run_seed, run_text, shafts, fly_level)
		if flown.error != "":
			result["errors"].append("run seed %d: %s" % [run_seed, flown.error])
			continue
		result["lines"].append(flown.line())
		result["levels_flown"] += flown.flown
		result["levels_escaped"] += flown.escaped
		if flown.completed():
			result["completed"] += 1
	result["rate"] = float(result["completed"]) / float(count)
	return result


## `MELTDOWN_BOT_RUNS {...}`, the rate to four places so the line is the same on
## every machine.
static func summary(result: Dictionary) -> String:
	return '%s {"runs":%d,"completed":%d,"rate":%.4f,"levels_flown":%d,"levels_escaped":%d}' % [
			SUMMARY_TAG, result["runs"], result["completed"], result["rate"],
			result["levels_flown"], result["levels_escaped"]]


func _init() -> void:
	var options: Dictionary[String, int] = {"runs": 100, "first": 1}
	for argument: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = argument.trim_prefix("--").split("=")
		if parts.size() != 2 or not options.has(parts[0]) or not parts[1].is_valid_int():
			printerr("unknown option ", argument, "; expected --runs=N or --first=S")
			quit(2)
			return
		options[parts[0]] = parts[1].to_int()
	if options["runs"] < 1:
		printerr("--runs must be at least 1")
		quit(2)
		return
	var result: Dictionary = run(options["first"], options["runs"])
	for line: String in result["lines"]:
		print(line)
	for problem: String in result["errors"]:
		printerr(problem)
	var line: String = summary(result)
	if not line.begins_with(SUMMARY_TAG):
		quit(1)
		return
	print(line)
	quit(1 if not result["errors"].is_empty() else 0)
