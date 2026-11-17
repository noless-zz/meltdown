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
## Failure messages kept in a result, so 10,000 bad seeds do not flood a log.
const KEPT_FAILURES: int = 10


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
## "debris_held" (entries `DebrisRouteGuard` held back), "ms", "by_check"
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
			"debris": 0, "debris_held": 0, "by_check": by_check, "failures": [] as Array[String]}
	# A broken data file must not pass every seed on the defaults.
	if inputs.error != "":
		result["failed"] = count
		result["failures"].append(inputs.error)
		result["ms"] = Time.get_ticks_msec() - started
		return result
	for level_seed: int in range(first_seed, first_seed + count):
		var generator: MineGenerator = inputs.generate(level_seed, module_count)
		if generator.note != "":
			result["short"] += 1
		if generator.loops > 0:
			result["looped"] += 1
		var level: LevelDef = inputs.level_of(generator)
		result["robots"] += level.robots.spawns.size()
		var found: Array[String] = []
		if level.error != "":
			found.append("level: %s" % level.error)
		else:
			found = inputs.validate(level, generator)
			if level.debris != null:
				result["debris"] += level.debris.size()
				var held: Array[int] = []
				var closed: String = debris_route(level, radius, held)
				result["debris_held"] += held[0]
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
	return result


## RUN-4's promise on one level (#440): the meltdown with a ship of `radius`
## at the reactor and every box explored, each tick an entry falls due on run
## through `DebrisRouteGuard` in fall order, jumping the clock between them, as
## `test_generated_debris.gd` does. After every such tick the start must still
## be reachable from the reactor; the first time it is not, the message, under
## `DEBRIS_ROUTE`, is returned. `held` gets the number of entries the guard
## held back. With `guarded` false the entries fall without the guard, so a
## test can show the check catches debris that closes the way out.
static func debris_route(level: LevelDef, radius: float, held: Array[int],
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
			closed = "%s: debris falling %d ticks into the meltdown closed every route from the reactor to the start" \
					% [DEBRIS_ROUTE, ticks]
			break
	var count: int = 0
	for index: int in sim.debris.size():
		if sim.debris.is_skipped(index):
			count += 1
	held.append(count)
	return closed


## One line for a log: "level validator: 1000 seeds, 1000 passed, 0 failed,
## 0 stopped short, 812 ms, debris 3500, debris_held 1200; failing seeds by
## check: level 0, piece 0, ...". The debris counts are left out when the
## result has none, and so is the by-check part.
static func summary(result: Dictionary) -> String:
	var line: String = "level validator: %d seeds, %d passed, %d failed, %d stopped short, %d ms" % [
			result["seeds"], result["passed"], result["failed"], result["short"], result["ms"]]
	if result.has("debris"):
		line += ", debris %d, debris_held %d" % [result["debris"], result["debris_held"]]
	if not result.has("by_check"):
		return line
	var counts: Array[String] = []
	for check: String in result["by_check"]:
		counts.append("%s %d" % [check, result["by_check"][check]])
	return line + "; failing seeds by check: " + ", ".join(counts)
