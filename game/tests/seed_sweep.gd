extends RefCounted

## Generates and validates a run of seeds and sums up the result (#317, GEN-3):
## shared by `test_level_validator.gd` (1,000 seeds per pull request) and
## `validate_seeds.gd`, which a nightly job can call with 10,000. The data
## files are read, and each level built and validated, by `SeedLevel`, the
## loader `--seed` flies with (#441), not in `gen/`, which never opens files.

## Modules per level, as in the generator's own 1,000-seed test and `--seed`.
const MODULE_COUNT: int = SeedLevel.MODULE_COUNT
const MODULES_DIR: String = SeedLevel.MODULES_DIR
const GENERATOR_FILE: String = SeedLevel.GENERATOR_FILE
## The `by_check` key for levels whose debris closed the way out (#440, RUN-4).
const DEBRIS_ROUTE: String = "debris_route"
const DebrisKinds := preload("res://tests/sweep_debris_kinds.gd")
## Failure messages kept in a result, so 10,000 bad seeds do not flood a log.
const KEPT_FAILURES: int = 10
## Where a sweep's time goes, as `run` keys "stage_ms" (#513): building the
## generator, turning it into a level (reactor, robots, debris and its trimming),
## each group `LevelValidator.validate` reports to its `on_check`, and the
## `debris_route` check.
const STAGES: Array[String] = ["generate", "build", "piece", "reachable", "escape",
		"debris_escape", "robots", DEBRIS_ROUTE]


# The loaders below hand on `SeedLevel`'s (#441), so the sweep and `--seed`
# read the data files one way; they stay for the tests that call them.

static func load_modules() -> Array[ModuleDef]:
	return SeedLevel.load_modules()


static func load_validator() -> LevelValidator:
	return LevelValidator.parse_json(SeedLevel.read_text(SeedLevel.VALIDATOR_FILE))


static func load_reactor_plan() -> ReactorPlan:
	return ReactorPlan.parse_json(SeedLevel.read_text(SeedLevel.REACTOR_FILE))


static func load_loop_bridges() -> LoopBridges:
	return LoopBridges.parse_json(SeedLevel.read_text(SeedLevel.GENERATOR_FILE))


static func robot_texts() -> Dictionary:
	return SeedLevel.robot_texts()


static func load_robot_plan() -> RobotPlan:
	return RobotPlan.parse_json(SeedLevel.read_text(SeedLevel.ROBOTS_FILE), robot_texts())


static func load_debris_plan() -> DebrisPlan:
	return DebrisPlan.parse_json(SeedLevel.read_text(SeedLevel.DEBRIS_FILE))


static func start_module_boxes(generator: MineGenerator) -> Array[int]:
	return SeedLevel.start_module_boxes(generator)


static func ship_radius() -> float:
	return ShipTuning.parse_json(SeedLevel.read_text(SeedLevel.SHIP_FILE)).radius


## Seeds `first_seed` up to `first_seed + count - 1`, each level with the
## generator's reactor (#356, #357), loops (#396), robots (#378, #399) and
## meltdown debris (#398, #440). The result holds "seeds",
## "passed", "failed", "short" (levels the generator stopped short, which are
## still validated), "looped" (levels with at least one loop), "robots" (robots
## placed over all levels), "debris" (debris entries placed over all levels),
## "debris_held" (entries `DebrisRouteGuard` held back), "debris_by_kind"
## (those two split by `DebrisKinds.KINDS`, each kind's "placed" and "held"), "ms", "stage_ms"
## (milliseconds spent in each of `STAGES`), "by_check"
## (seeds failing each of `LevelValidator.CHECKS`, plus "level" for levels that
## did not build and `DEBRIS_ROUTE` for levels whose debris closed the way
## out, see `debris_route`), and "failures": the first
## `kept_failures` messages, each prefixed with its seed. A `kept_failures` of 0
## keeps every message, so the nightly job can list every failing seed (#358).
## `overrides` maps a data file's `res://` path to text used in its place, as
## `SeedLevel.load_inputs` takes it, so a test can break one file.
static func run(first_seed: int, count: int, module_count: int = MODULE_COUNT,
		kept_failures: int = KEPT_FAILURES, overrides: Dictionary = {}) -> Dictionary:
	var started: int = Time.get_ticks_msec()
	# The same inputs, generator, level and checks `--seed` flies (#441).
	var inputs: SeedLevel = SeedLevel.load_inputs("", overrides)
	var radius: float = inputs.tuning.radius
	var by_check: Dictionary[String, int] = {"level": 0}
	for check: String in LevelValidator.CHECKS:
		by_check[check] = 0
	by_check[DEBRIS_ROUTE] = 0
	var result: Dictionary = {"seeds": count, "passed": 0, "failed": 0, "short": 0, "looped": 0, "robots": 0,
			"debris": 0, "debris_held": 0, "debris_by_kind": DebrisKinds.empty(), "by_check": by_check, "failures": [] as Array[String]}
	# A broken data file must not pass every seed on the defaults.
	if inputs.error != "":
		result["failed"] = count
		result["failures"].append(inputs.error)
		result["ms"] = Time.get_ticks_msec() - started
		return result
	var stage_us: Dictionary[String, int] = {}
	for stage: String in STAGES:
		stage_us[stage] = 0
	# The clock read when the last stage ended; each stage adds what has passed.
	var last: Array[int] = [Time.get_ticks_usec()]
	var mark: Callable = func(stage: String) -> void:
		var now: int = Time.get_ticks_usec()
		stage_us[stage] += now - last[0]
		last[0] = now
	for level_seed: int in range(first_seed, first_seed + count):
		last[0] = Time.get_ticks_usec()
		var generator: MineGenerator = inputs.generate(level_seed, module_count)
		mark.call("generate")
		if generator.note != "":
			result["short"] += 1
		if generator.loops > 0:
			result["looped"] += 1
		var level: LevelDef = inputs.level_of(generator)
		mark.call("build")
		result["robots"] += level.robots.spawns.size()
		var found: Array[String] = []
		if level.error != "":
			found.append("level: %s" % level.error)
		else:
			# `inputs.validate`'s call, with the checks timed.
			found = inputs.validator.validate(level, radius, true, inputs.robot_radii,
					start_module_boxes(generator), mark)
			if level.debris != null:
				result["debris"] += level.debris.size()
				var held: Array[int] = []
				var held_flags: Array[bool] = []
				last[0] = Time.get_ticks_usec()
				var closed: String = debris_route(level, radius, held, true, held_flags)
				mark.call(DEBRIS_ROUTE)
				result["debris_held"] += held[0]
				DebrisKinds.add(result["debris_by_kind"], level.debris, held_flags)
				if closed != "":
					found.append(closed)
		if found.is_empty():
			result["passed"] += 1
			continue
		result["failed"] += 1
		var counted: Array[String] = []
		for message: String in found:
			var check: String = message.get_slice(":", 0)
			if by_check.has(check) and not counted.has(check):
				counted.append(check)
				by_check[check] += 1
			if kept_failures == 0 or result["failures"].size() < kept_failures:
				result["failures"].append("seed %d: %s" % [level_seed, message])
	result["ms"] = Time.get_ticks_msec() - started
	var stage_ms: Dictionary[String, int] = {}
	for stage: String in STAGES:
		stage_ms[stage] = stage_us[stage] / 1000
	result["stage_ms"] = stage_ms
	return result


## RUN-4's promise on one level (#440): the meltdown with a ship of `radius`
## at the reactor and every box explored, each tick an entry falls due run
## through `DebrisRouteGuard` in fall order. After every such tick the start
## must still be reachable from the reactor; the first time it is not, the
## message, under `DEBRIS_ROUTE`, is returned. `held` gets the number of
## entries the guard held back. With `guarded` false the entries fall without
## the guard, so a test can show the check catches debris that closes the way out.
##
## With the guard this gives what `debris_route_flown` gives, without flying
## the meltdown (#513): it was half of the 1,000-seed sweep's time. The guard
## keeps the one ship's route whenever it has one, so the way out only closes
## when the start was never reachable from the reactor, on the first tick an
## entry falls, with nothing held; otherwise the guard holds what
## `DebrisEscape.held_by_guard` holds. `test_seed_sweep_debris.gd` compares the
## two over seeds 0..199. With the guard, `held_flags` gets whether each entry
## was held, for the counts by kind (#887); it stays empty when nothing was.
static func debris_route(level: LevelDef, radius: float, held: Array[int],
		guarded: bool = true, held_flags: Array[bool] = []) -> String:
	if not guarded:
		return debris_route_flown(level, radius, held, false)
	var debris: MeltdownDebris = level.debris
	var graph: OpeningGraph = OpeningGraph.new(level, radius)
	var open: Array[bool] = []
	open.resize(graph.opening_count())
	open.fill(false)
	if debris.size() > 0 and not graph.connected(open):
		held.append(0)
		var first: int = debris.after_ticks[0]
		for ticks: int in debris.after_ticks:
			first = mini(first, ticks)
		return _closed(first)
	var count: int = 0
	var flags: Array[bool] = DebrisEscape.held_by_guard(level, debris, radius)
	for flag: bool in flags:
		if flag:
			count += 1
	held.append(count)
	held_flags.append_array(flags)
	return ""


## `debris_route` by flying the meltdown: each tick an entry falls due on is
## run through `DebrisRouteGuard` (or, with `guarded` false, only
## `MeltdownDebris.advance`), jumping the clock between them, as
## `test_generated_debris.gd` does, and the route is looked for after each.
static func debris_route_flown(level: LevelDef, radius: float, held: Array[int],
		guarded: bool = true) -> String:
	var sim: Sim = Sim.new(0, 1)
	sim.set_walls(level.union)
	sim.set_start_pose(0, level.start_position(), Basis())
	sim.ships[0].radius = radius
	sim.ships[0].position = level.reactor.position()
	var reactor: ReactorState = level.reactor.fresh_copy()
	reactor.destroyed = true
	sim.set_reactor(reactor)
	sim.set_debris(level.debris.fresh_copy())
	var due: Array[int] = []
	for ticks: int in sim.debris.after_ticks:
		if not due.has(ticks):
			due.append(ticks)
	due.sort()
	var all: Array[int] = []
	for box: int in level.union.boxes.size():
		all.append(box)
	var events: Array[SimEvent] = []
	var closed: String = ""
	for ticks: int in due:
		sim.debris.elapsed_ticks = ticks - 1
		if guarded:
			DebrisRouteGuard.advance(sim, events)
		else:
			sim.debris.advance(sim.reactor)
		var route: KnownRoute = KnownRoute.find(level.union, all, level.reactor.position(),
				level.start_position(), sim.debris, radius)
		if route.length_mm == EscapePath.UNREACHABLE:
			closed = _closed(ticks)
			break
	var count: int = 0
	for index: int in sim.debris.size():
		if sim.debris.is_skipped(index):
			count += 1
	held.append(count)
	return closed


static func _closed(ticks: int) -> String:
	return "%s: debris falling %d ticks into the meltdown closed every route from the reactor to the start" \
			% [DEBRIS_ROUTE, ticks]


## One line for a log, with each of `STAGES` and its milliseconds, as the
## 1,000-seed test prints it: "sweep time: generate 4300 ms, build 2100 ms, ...".
static func timing(result: Dictionary) -> String:
	var parts: Array[String] = []
	var stage_ms: Dictionary = result.get("stage_ms", {})
	for stage: String in stage_ms:
		parts.append("%s %d ms" % [stage, stage_ms[stage]])
	return "sweep time: " + ", ".join(parts)


## One line for a log: "level validator: 1000 seeds, 1000 passed, 0 failed,
## 0 stopped short, 812 ms, debris 3500, debris_held 1200, rocks 2900,
## rocks_held 1100, doors 400, doors_held 100, fires 200, fires_held 0; failing
## seeds by check: level 0, piece 0, ...". The debris counts, those by kind
## (#887) and the by-check part are each left out when the result has none.
static func summary(result: Dictionary) -> String:
	var line: String = "level validator: %d seeds, %d passed, %d failed, %d stopped short, %d ms" % [
			result["seeds"], result["passed"], result["failed"], result["short"], result["ms"]]
	if result.has("debris"):
		line += ", debris %d, debris_held %d" % [result["debris"], result["debris_held"]]
	if result.has("debris_by_kind"):
		line += DebrisKinds.summary_part(result["debris_by_kind"])
	if not result.has("by_check"):
		return line
	var counts: Array[String] = []
	for check: String in result["by_check"]:
		counts.append("%s %d" % [check, result["by_check"][check]])
	return line + "; failing seeds by check: " + ", ".join(counts)
