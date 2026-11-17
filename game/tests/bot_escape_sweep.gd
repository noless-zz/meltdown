extends SceneTree

## Flies the bot pilot over a run of generated levels and sums up how often it
## escapes (#377): gate G3's automated half wants bots to escape 95% of cleared
## levels (DEV-6, GEN-3, RUN-3, RUN-5), and G2 alone says nothing about the
## generator's levels. Each level is built as `seed_sweep.gd` builds it, with
## the reactor plan and the shipped loop bridges (#420), so both sweeps fly the
## levels the player will fly, and flown through `LocalSession.for_level` as
## the main scene would fly it:
##
##     godot --headless --path game -s res://tests/bot_escape_sweep.gd -- --seeds=1000 --first=1
##
## Options: `--seeds=N` (default 1000), `--first=S` (first seed, default 1),
## `--robots` (place robots from `robots.json` too; the bot must fight through
## them to the reactor), `--debris` (meltdown debris from `debris.json` too,
## #443; the bot must route round it on the way out). Prints one line per
## failing seed, then the summary line
## `MELTDOWN_BOT_ESCAPE {"seeds":N,"cleared":C,"escaped":E,"looped":L,"rate":r}`,
## with `,"robots_destroyed":D,"robots":true` before the closing brace when
## robots were placed and `,"debris":true` after that when debris was. A level is cleared once the bot destroyed its reactor,
## the rate is escaped over cleared and `looped` counts seeds with at least one
## loop. Without `--robots` the rate is G3's number. Seeds with no reactor are counted apart, so a generator that
## drops reactors cannot raise the rate. Exit code 0 only when the rate is at
## least `REQUIRED_RATE`. The functions are static so the unit test can call
## them without starting a second SceneTree.

const SeedSweep := preload("res://tests/seed_sweep.gd")
const SHIP_TUNING_PATH: String = "res://data/ships/default_ship.json"
## Read here as `seed_sweep.gd` reads its data files; `gen/` never opens files.
const DEBRIS_FILE: String = "res://data/gen/debris.json"
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
	## Robots the level spawned that were no longer alive where the flight stopped.
	var robots_destroyed: int = 0

	func line() -> String:
		return "seed %d: %s at tick %d: %s" % [level_seed, outcome, tick, reason]


## The generator for `level_seed`, with `bridges` closing loops as the
## validator sweep's levels do; null bridges give a tree.
static func generate(level_seed: int, modules: Array[ModuleDef],
		bridges: LoopBridges = null) -> MineGenerator:
	return MineGenerator.generate(level_seed, modules, SeedSweep.MODULE_COUNT, bridges)


## The level for `level_seed`, built as the validator sweep builds it. Robots
## only with a `robot_plan`, debris only with a `debris_plan`.
static func build_level(level_seed: int, modules: Array[ModuleDef], plan: ReactorPlan,
		radius: float, bridges: LoopBridges = null, robot_plan: RobotPlan = null,
		debris_plan: DebrisPlan = null) -> LevelDef:
	return generate(level_seed, modules, bridges).to_level_def(plan, radius, robot_plan,
			debris_plan)


static func load_debris_plan() -> DebrisPlan:
	return DebrisPlan.parse_json(FileAccess.get_file_as_string(DEBRIS_FILE))


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
	var spawned: int = sim.robots.size()
	while sim.outcome() == ExitRule.Outcome.RUNNING and sim.ships[0].hull > 0.0 \
			and sim.tick < TICK_LIMIT:
		session.advance(ShipState.TICK_DT)
	var outcome: ExitRule.Outcome = sim.outcome()
	result.outcome = ExitRule.Outcome.keys()[outcome]
	result.tick = sim.tick
	result.state_hash = sim.state_hash()
	result.cleared = sim.reactor.destroyed
	var alive: int = 0
	for robot: RobotState in sim.robots:
		if robot.is_alive():
			alive += 1
	result.robots_destroyed = spawned - alive
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


## Seeds `first_seed` up to `first_seed + count - 1`, on looped levels, with
## robots when `with_robots` and meltdown debris when `with_debris`. The result
## holds "seeds", "cleared", "escaped", "looped", "no_reactor", "robots" and
## "debris" (whether robots and debris were placed),
## "robots_destroyed", "rate", "ms" and "failures": a `SeedResult` line for
## every seed that did not escape, in seed order.
static func run(first_seed: int, count: int, with_robots: bool = false,
		with_debris: bool = false) -> Dictionary:
	var started: int = Time.get_ticks_msec()
	var modules: Array[ModuleDef] = SeedSweep.load_modules()
	var plan: ReactorPlan = SeedSweep.load_reactor_plan()
	var bridges: LoopBridges = SeedSweep.load_loop_bridges()
	var robot_plan: RobotPlan = SeedSweep.load_robot_plan() if with_robots else null
	var debris_plan: DebrisPlan = load_debris_plan() if with_debris else null
	var radius: float = SeedSweep.ship_radius()
	var tuning: ShipTuning = LocalSession.load_tuning(SHIP_TUNING_PATH)
	var result: Dictionary = {"seeds": count, "cleared": 0, "escaped": 0, "looped": 0,
			"no_reactor": 0, "robots": with_robots, "debris": with_debris, "robots_destroyed": 0,
			"rate": 0.0,
			"failures": [] as Array[String]}
	# A broken file would give levels with no reactor, no loops or no robots,
	# and a rate that measures something other than the levels the player flies.
	var broken: String = ""
	if plan.error != "":
		broken = "reactor.json: %s" % plan.error
	elif bridges.error != "":
		broken = "generator.json: %s" % bridges.error
	elif robot_plan != null and robot_plan.error != "":
		broken = "robots.json: %s" % robot_plan.error
	elif debris_plan != null and debris_plan.error != "":
		broken = "debris.json: %s" % debris_plan.error
	if broken != "":
		result["failures"].append(broken)
		result["ms"] = Time.get_ticks_msec() - started
		return result
	for level_seed: int in range(first_seed, first_seed + count):
		var generator: MineGenerator = generate(level_seed, modules, bridges)
		if generator.loops > 0:
			result["looped"] += 1
		var level: LevelDef = generator.to_level_def(plan, radius, robot_plan, debris_plan)
		var flown: SeedResult = fly(level_seed, level, tuning)
		result["robots_destroyed"] += flown.robots_destroyed
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


## `MELTDOWN_BOT_ESCAPE {"seeds":N,"cleared":C,"escaped":E,"looped":L,"rate":r}`,
## the rate to four places so the line is the same on every machine. With
## robots, `,"robots_destroyed":D,"robots":true` follows the rate, so a robot
## run's line can never be read as the G3 number; `,"debris":true` follows
## when debris was placed.
static func summary(result: Dictionary) -> String:
	var line: String = '%s {"seeds":%d,"cleared":%d,"escaped":%d,"looped":%d,"rate":%.4f' % [
			SUMMARY_TAG, result["seeds"], result["cleared"], result["escaped"],
			result.get("looped", 0), result["rate"]]
	if result.get("robots", false):
		line += ',"robots_destroyed":%d,"robots":true' % result.get("robots_destroyed", 0)
	if result.get("debris", false):
		line += ',"debris":true'
	return line + "}"


## The run's extras, which do not belong in the machine-read summary line.
static func details(result: Dictionary) -> String:
	return "bot escape sweep: %d without a reactor, %d not escaped, %d ms" % [
			result["no_reactor"], result["failures"].size(), result["ms"]]


func _init() -> void:
	var options: Dictionary[String, int] = {"seeds": 1000, "first": 1}
	var with_robots: bool = false
	var with_debris: bool = false
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--robots":
			with_robots = true
			continue
		if argument == "--debris":
			with_debris = true
			continue
		var parts: PackedStringArray = argument.trim_prefix("--").split("=")
		if parts.size() != 2 or not options.has(parts[0]) or not parts[1].is_valid_int():
			printerr("unknown option ", argument, "; expected --seeds=N, --first=S, --robots or --debris")
			quit(2)
			return
		options[parts[0]] = parts[1].to_int()
	if options["seeds"] < 1:
		printerr("--seeds must be at least 1")
		quit(2)
		return
	var result: Dictionary = run(options["first"], options["seeds"], with_robots,
			with_debris)
	for line: String in result["failures"]:
		print(line)
	print(details(result))
	print(summary(result))
	quit(0 if result["cleared"] > 0 and result["rate"] >= REQUIRED_RATE else 1)
