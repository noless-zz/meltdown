extends SceneTree

## Flies the bot pilot over a run of generated levels and sums up how often it
## escapes (#377): gate G3's automated half wants bots to escape 95% of cleared
## levels (DEV-6, GEN-3, RUN-3, RUN-5), and G2 alone says nothing about the
## generator's levels. Each level is built as `seed_sweep.gd` builds it, with
## the reactor plan, and flown through `LocalSession.for_level` as the main
## scene would fly it:
##
##     godot --headless --path game -s res://tests/bot_escape_sweep.gd -- --seeds=1000 --first=1
##
## Options: `--seeds=N` (default 1000), `--first=S` (first seed, default 1).
## Prints one line per failing seed, then the summary line
## `MELTDOWN_BOT_ESCAPE {"seeds":N,"cleared":C,"escaped":E,"rate":r}`, where a
## level is cleared once the bot destroyed its reactor and the rate is escaped
## over cleared. Seeds with no reactor are counted apart, so a generator that
## drops reactors cannot raise the rate. Exit code 0 only when the rate is at
## least `REQUIRED_RATE`. The functions are static so the unit test can call
## them without starting a second SceneTree.

const SeedSweep := preload("res://tests/seed_sweep.gd")
const SHIP_TUNING_PATH: String = "res://data/ships/default_ship.json"
const SUMMARY_TAG: String = "MELTDOWN_BOT_ESCAPE"
## G3's bar (DEV-6).
const REQUIRED_RATE: float = 0.95
## Ten minutes of flight: the countdown is at most a few minutes even scaled
## with the path, so a bot still flying here is stuck, not slow.
const TICK_LIMIT: int = 36000


## Feeds the session the bot's input; the bot needs the session's own `Sim`.
class BotSource extends ShipInputSource:
	var bot: BotPilot = null

	func next_input(tick: int) -> ShipInput:
		return bot.next_input(tick) if bot != null else ShipInput.new()


## How one seed went. `outcome` is an `ExitRule.Outcome` name, or "NO_LEVEL"
## and "NO_REACTOR" for seeds that were never flown.
class SeedResult extends RefCounted:
	var level_seed: int = 0
	var outcome: String = ""
	var tick: int = 0
	var cleared: bool = false
	var escaped: bool = false
	var reason: String = ""
	## `Sim.state_hash` where the flight stopped; 0 for a seed never flown.
	var state_hash: int = 0

	func line() -> String:
		return "seed %d: %s at tick %d: %s" % [level_seed, outcome, tick, reason]


## The level for `level_seed`, built as the validator sweep builds it.
static func build_level(level_seed: int, modules: Array[ModuleDef], plan: ReactorPlan,
		radius: float) -> LevelDef:
	var generator: MineGenerator = MineGenerator.generate(level_seed, modules, SeedSweep.MODULE_COUNT)
	return generator.to_level_def(plan, radius)


## The bot flies `level` until the run ends, its ship is destroyed, or
## TICK_LIMIT.
static func fly(level_seed: int, level: LevelDef, tuning: ShipTuning) -> SeedResult:
	var result: SeedResult = SeedResult.new()
	result.level_seed = level_seed
	if level.error != "":
		result.outcome = "NO_LEVEL"
		result.reason = level.error
		return result
	if level.reactor == null:
		result.outcome = "NO_REACTOR"
		result.reason = "the generator placed no reactor"
		return result
	var source: BotSource = BotSource.new()
	var session: LocalSession = LocalSession.for_level(level, 0, source, tuning)
	source.bot = BotPilot.new(session.sim, 0, level)
	var sim: Sim = session.sim
	while sim.outcome() == ExitRule.Outcome.RUNNING and sim.ships[0].hull > 0.0 \
			and sim.tick < TICK_LIMIT:
		session.advance(ShipState.TICK_DT)
	var outcome: ExitRule.Outcome = sim.outcome()
	result.outcome = ExitRule.Outcome.keys()[outcome]
	result.tick = sim.tick
	result.state_hash = sim.state_hash()
	result.cleared = sim.reactor.destroyed
	result.escaped = outcome == ExitRule.Outcome.ESCAPED
	if result.escaped:
		return result
	if sim.ships[0].hull <= 0.0:
		result.reason = "ship destroyed%s" % (" after the reactor" if result.cleared else "")
	elif outcome == ExitRule.Outcome.LOST:
		result.reason = "the countdown ran out"
	elif result.cleared:
		result.reason = "tick limit with the countdown running"
	else:
		result.reason = "tick limit with the reactor intact"
	return result


## Seeds `first_seed` up to `first_seed + count - 1`. The result holds
## "seeds", "cleared", "escaped", "no_reactor", "rate", "ms" and "failures":
## a `SeedResult` line for every seed that did not escape, in seed order.
static func run(first_seed: int, count: int) -> Dictionary:
	var started: int = Time.get_ticks_msec()
	var modules: Array[ModuleDef] = SeedSweep.load_modules()
	var plan: ReactorPlan = SeedSweep.load_reactor_plan()
	var radius: float = SeedSweep.ship_radius()
	var tuning: ShipTuning = LocalSession.load_tuning(SHIP_TUNING_PATH)
	var result: Dictionary = {"seeds": count, "cleared": 0, "escaped": 0, "no_reactor": 0,
			"rate": 0.0, "failures": [] as Array[String]}
	# A broken plan would give levels with no reactor and an empty, meaningless rate.
	if plan.error != "":
		result["failures"].append("reactor.json: %s" % plan.error)
		result["ms"] = Time.get_ticks_msec() - started
		return result
	for level_seed: int in range(first_seed, first_seed + count):
		var flown: SeedResult = fly(level_seed, build_level(level_seed, modules, plan, radius), tuning)
		if flown.outcome == "NO_REACTOR":
			result["no_reactor"] += 1
		if flown.cleared:
			result["cleared"] += 1
		if flown.escaped:
			result["escaped"] += 1
		else:
			result["failures"].append(flown.line())
	if result["cleared"] > 0:
		result["rate"] = float(result["escaped"]) / float(result["cleared"])
	result["ms"] = Time.get_ticks_msec() - started
	return result


## `MELTDOWN_BOT_ESCAPE {"seeds":N,"cleared":C,"escaped":E,"rate":r}`, the rate
## to four places so the line is the same on every machine.
static func summary(result: Dictionary) -> String:
	return '%s {"seeds":%d,"cleared":%d,"escaped":%d,"rate":%.4f}' % [SUMMARY_TAG,
			result["seeds"], result["cleared"], result["escaped"], result["rate"]]


## The run's extras, which do not belong in the machine-read summary line.
static func details(result: Dictionary) -> String:
	return "bot escape sweep: %d without a reactor, %d not escaped, %d ms" % [
			result["no_reactor"], result["failures"].size(), result["ms"]]


func _init() -> void:
	var options: Dictionary[String, int] = {"seeds": 1000, "first": 1}
	for argument: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = argument.trim_prefix("--").split("=")
		if parts.size() != 2 or not options.has(parts[0]) or not parts[1].is_valid_int():
			printerr("unknown option ", argument, "; expected --seeds=N or --first=S")
			quit(2)
			return
		options[parts[0]] = parts[1].to_int()
	if options["seeds"] < 1:
		printerr("--seeds must be at least 1")
		quit(2)
		return
	var result: Dictionary = run(options["first"], options["seeds"])
	for line: String in result["failures"]:
		print(line)
	print(details(result))
	print(summary(result))
	quit(0 if result["cleared"] > 0 and result["rate"] >= REQUIRED_RATE else 1)
