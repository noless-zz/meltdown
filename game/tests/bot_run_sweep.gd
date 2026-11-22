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
## Options: `--runs=N` (default 100), `--first=S` (first run seed, default 1),
## `--shaft=<index>` (#1173, default 0), and `--profile=<path>` with
## `--fitting=<path>` (#1091, CRW-3): with both,
## the same run seeds are flown twice, first by the plain ship file and then by
## the ship that profile and fitting start a run with (`bot_sweep_ship.gd`, as
## `RunShip` builds it for a run level), and one `MELTDOWN_BOT_SHIP` line each
## sets them side by side: runs finished, level-1 escapes, mean hull left on
## level 1. That comparison is reported, never judged. Without them the sweep
## flies the ship file and prints exactly what it printed before.
## Where the run waits for a shaft choice the sweep takes the shaft at
## position `--shaft` in the offer (0, the first offered, by default; the last
## offered when the offer is shorter), so a run seed always flies the same
## levels. The offer's order is drawn per level from `shafts.json`, so a
## position is not a fixed shaft. Each level after the first is built with the
## chosen shaft's `risk.robot_count`, as the game builds it
## (`RunWiring.level_robot_scale`, `RobotPlan.scaled`), and level 1 at 1.0. An escape calls
## `advance`; anything else (ship destroyed, countdown run out, still flying at
## the tick limit, or a level that could not be flown) calls `lose` and ends
## the run. A run is complete once `is_over` after its last escape.
##
## Prints one `MELTDOWN_BOT_RUN` line per run, its `robot_scales` the scale
## each flown level was built with, then
## `MELTDOWN_BOT_RUNS {"runs":N,"completed":C,"rate":r,"levels_flown":L,"levels_escaped":E}`.
## The fitted ship's lines carry `FITTED_SUFFIX` on both tags.
## The gate has no bar for this rate yet, so it is reported, not judged: the
## exit code is 0 unless a run seed fails to build (a broken data file) or the
## summary cannot be printed.

const EscapeSweep := preload("res://tests/bot_escape_sweep.gd")
const Levels := preload("res://tests/bot_sweep_levels.gd")
const RUN_FILE: String = "res://data/run/run.json"
const SHAFTS_FILE: String = "res://data/run/shafts.json"
const RUN_TAG: String = "MELTDOWN_BOT_RUN"
const SUMMARY_TAG: String = "MELTDOWN_BOT_RUNS"
const SHIP_TAG: String = "MELTDOWN_BOT_SHIP"
const FITTED_SUFFIX: String = "_FITTED"
const Ship := preload("res://tests/bot_sweep_ship.gd")


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
	## The robot count scale each flown level was built with, in order.
	var scales: Array[float] = []
	## Why the run seed could not be built; empty when it was.
	var error: String = ""
	## Whether level 1 was escaped, and the hull left where it stopped.
	var first_escaped: bool = false
	var first_hull: float = 0.0

	func completed() -> bool:
		return ended == "completed"

	func line(tag: String = RUN_TAG) -> String:
		var written: PackedStringArray = []
		for scale: float in scales:
			written.append("%.2f" % scale)
		return '%s {"seed":%d,"planned":%d,"flown":%d,"escaped":%d,"ended":"%s","robot_scales":[%s]}' % [
				tag, run_seed, planned, flown, escaped, ended, ",".join(written)]


## Flies one run, taking the shaft at `shaft_index` in each offer. `fly_level`
## takes (run seed, level index, level seed, robot scale) and returns an
## `EscapeSweep.SeedResult`; the sweep passes the bot, a test a stub.
static func fly_run(run_seed: int, run_text: String, shafts: ShaftOffer,
		fly_level: Callable, shaft_index: int = 0) -> RunResult:
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
			var offered: Array[String] = state.offer()
			var kind: String = offered[mini(shaft_index, offered.size() - 1)]
			state.choose(kind)
			result.shafts.append(kind)
		var scale: float = float(state.current_risk()["robot_count"])
		result.scales.append(scale)
		var flown: EscapeSweep.SeedResult = fly_level.call(run_seed, state.level_index,
				state.current_level_seed(), scale)
		result.flown += 1
		if result.flown == 1:
			result.first_escaped = flown.escaped
			result.first_hull = flown.hull
		if flown.escaped:
			result.escaped += 1
			state.advance()
		else:
			state.lose()
			result.ended = flown.outcome + (" ship destroyed" if flown.destroyed else "")
	if state.won:
		result.ended = "completed"
	return result


## The sweep's `fly_level`: the bot flies each level of `levels` (built with
## robots, scaled by the shaft's robot scale, and debris) in `tuning`, or the
## ship file's when null. Shared with
## the pinned full run (#1118) so it flies exactly as the sweep does.
static func bot_flies(levels: Levels, tuning: ShipTuning = null) -> Callable:
	var flown_tuning: ShipTuning = tuning if tuning != null else levels.tuning
	return func(_run_seed: int, _index: int, level_seed: int,
			robot_scale: float) -> EscapeSweep.SeedResult:
		return EscapeSweep.fly(level_seed, levels.level_of(levels.generate(level_seed), robot_scale),
				flown_tuning)


## Run seeds `first_seed` to `first_seed + count - 1`. With no `fly_level` the
## bot flies each level with robots and debris on, in `tuning`, or the ship
## file's when null. The result holds "runs", "completed", "rate",
## "levels_flown", "levels_escaped", "level1_escapes", "level1_hull" (summed
## over the runs), "lines" (one `MELTDOWN_BOT_RUN` line per run, or `tag`'s)
## and "errors" (why a run seed or a data file could not be built).
static func run(first_seed: int, count: int, fly_level: Callable = Callable(),
		tuning: ShipTuning = null, tag: String = RUN_TAG, shaft_index: int = 0) -> Dictionary:
	var result: Dictionary = {"runs": count, "completed": 0, "rate": 0.0, "levels_flown": 0,
			"levels_escaped": 0, "level1_escapes": 0, "level1_hull": 0.0,
			"lines": [] as Array[String], "errors": [] as Array[String]}
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
		fly_level = bot_flies(levels, tuning)
	for run_seed: int in range(first_seed, first_seed + count):
		var flown: RunResult = fly_run(run_seed, run_text, shafts, fly_level, shaft_index)
		if flown.error != "":
			result["errors"].append("run seed %d: %s" % [run_seed, flown.error])
			continue
		result["lines"].append(flown.line(tag))
		result["levels_flown"] += flown.flown
		result["levels_escaped"] += flown.escaped
		result["level1_escapes"] += 1 if flown.first_escaped else 0
		result["level1_hull"] += flown.first_hull
		if flown.completed():
			result["completed"] += 1
	result["rate"] = float(result["completed"]) / float(count)
	return result


## `MELTDOWN_BOT_RUNS {...}`, the rate to four places so the line is the same on
## every machine.
static func summary(result: Dictionary, tag: String = SUMMARY_TAG) -> String:
	return '%s {"runs":%d,"completed":%d,"rate":%.4f,"levels_flown":%d,"levels_escaped":%d}' % [
			tag, result["runs"], result["completed"], result["rate"],
			result["levels_flown"], result["levels_escaped"]]


## `MELTDOWN_BOT_SHIP {"ship":<ship>,"runs":N,"finished":C,"level1_escapes":E,"level1_mean_hull":h}`,
## the hull to two places; a run whose ship was destroyed on level 1 counts 0.
static func ship_line(ship: String, result: Dictionary) -> String:
	var runs: int = maxi(int(result["runs"]), 1)
	return '%s {"ship":"%s","runs":%d,"finished":%d,"level1_escapes":%d,"level1_mean_hull":%.2f}' % [
			SHIP_TAG, ship, result["runs"], result["completed"], result["level1_escapes"],
			float(result["level1_hull"]) / float(runs)]


## The options in `arguments`: "runs", "first", "shaft", "profile" and "fitting", or
## "error" naming what is wrong. Profile and fitting come together or not at all.
static func parse_options(arguments: PackedStringArray) -> Dictionary:
	var options: Dictionary = {"runs": 100, "first": 1, "shaft": 0, "profile": "", "fitting": "",
			"error": ""}
	for argument: String in arguments:
		var parts: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
		var known: bool = parts.size() == 2 and options.has(parts[0]) and parts[0] != "error"
		if known and (parts[0] == "profile" or parts[0] == "fitting") and parts[1] != "":
			options[parts[0]] = parts[1]
		elif known and (parts[0] in ["runs", "first", "shaft"]) and parts[1].is_valid_int():
			options[parts[0]] = parts[1].to_int()
		else:
			options["error"] = "unknown option %s; expected --runs=N, --first=S, --shaft=<index>, --profile=<path> or --fitting=<path>" % argument
			return options
	if options["runs"] < 1:
		options["error"] = "--runs must be at least 1"
	elif options["shaft"] < 0:
		options["error"] = "--shaft must be 0 or more"
	elif (options["profile"] == "") != (options["fitting"] == ""):
		options["error"] = "--profile and --fitting go together"
	return options


## Prints one sweep's lines and summary under `tag`s; false when the summary
## could not be built or a run seed failed.
static func _print(result: Dictionary, run_tag: String, summary_tag: String) -> bool:
	for line: String in result["lines"]:
		print(line)
	for problem: String in result["errors"]:
		printerr(problem)
	var line: String = summary(result, summary_tag)
	if not line.begins_with(summary_tag):
		return false
	print(line)
	return result["errors"].is_empty()


func _init() -> void:
	var options: Dictionary = parse_options(OS.get_cmdline_user_args())
	if options["error"] != "":
		printerr(options["error"])
		quit(2)
		return
	var fitted: ShipTuning = null
	if options["profile"] != "":
		var built: Dictionary = Ship.fitted(options["profile"], options["fitting"])
		if built["error"] != "":
			printerr(built["error"])
			quit(2)
			return
		fitted = built["tuning"]
	var plain: Dictionary = run(options["first"], options["runs"], Callable(), null, RUN_TAG,
			options["shaft"])
	var ok: bool = _print(plain, RUN_TAG, SUMMARY_TAG)
	if fitted == null:
		quit(0 if ok else 1)
		return
	var with_fitting: Dictionary = run(options["first"], options["runs"], Callable(), fitted,
			RUN_TAG + FITTED_SUFFIX, options["shaft"])
	ok = _print(with_fitting, RUN_TAG + FITTED_SUFFIX, SUMMARY_TAG + FITTED_SUFFIX) and ok
	print(ship_line("plain", plain))
	print(ship_line("fitted", with_fitting))
	quit(0 if ok else 1)
