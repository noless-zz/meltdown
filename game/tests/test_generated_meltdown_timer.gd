extends RefCounted

## Generated levels scale the meltdown countdown with the escape path (#417,
## RUN-5, RUN-2, GEN-3, ARC-4): `reactor.json` turns scaling on with values
## inside 45..180 s; over seeds 0..999 every countdown is in that range and at
## least 1.5 times the time to fly the level's escape path at the validator's
## escape speed; and of three seeds with different escape paths the longer path
## gets the longer countdown, by the formula. The values themselves are tuning
## knobs for the G3 headset session (#292), so the tests pin the rules, not the
## numbers.

const SeedSweep := preload("res://tests/seed_sweep.gd")
const SeedLevelCache := preload("res://tests/seed_level_cache.gd")
const MIN_SECONDS: float = 45.0
const MAX_SECONDS: float = 180.0
## Countdown over the flying time at the validator's escape speed (#417).
const MIN_RATIO: float = 1.5
const SEEDS: int = 1000
## Seeds 3, 1 and 0 have escape paths of about 87, 136 and 225 m, all on the
## sloped part of the formula with the values in #417's pull request.
const ORDERED_SEEDS: Array[int] = [3, 1, 0]


static func _level(level_seed: int, modules: Array[ModuleDef], plan: ReactorPlan) -> LevelDef:
	var generator: MineGenerator = MineGenerator.generate(level_seed, modules, SeedSweep.MODULE_COUNT,
			SeedSweep.load_loop_bridges())
	return generator.to_level_def(plan, SeedSweep.ship_radius(), SeedSweep.load_robot_plan())


static func _path_mm(level: LevelDef) -> int:
	return EscapePath.length_mm(level.union, level.reactor.position(), level.start_position())


static func _formula_ticks(reactor: ReactorState, path_mm: int) -> int:
	var seconds: float = reactor.meltdown_base_seconds + reactor.meltdown_seconds_per_metre * path_mm / float(RobotSpawn.SCALE)
	return roundi(clampf(seconds, reactor.meltdown_min_seconds, reactor.meltdown_max_seconds)
			* ReactorState.TICKS_PER_SECOND)


func test_the_data_file_scales_within_the_agreed_range() -> String:
	var plan: ReactorPlan = SeedSweep.load_reactor_plan()
	if plan.error != "":
		return "reactor.json: %s" % plan.error
	var reactor: ReactorState = plan.reactor
	if not reactor.scales_with_path:
		return "reactor.json does not scale the countdown with the escape path"
	if reactor.meltdown_min_seconds < MIN_SECONDS or reactor.meltdown_max_seconds > MAX_SECONDS:
		return "clamp %s..%s s, outside %s..%s" % [reactor.meltdown_min_seconds,
				reactor.meltdown_max_seconds, MIN_SECONDS, MAX_SECONDS]
	if reactor.meltdown_seconds_per_metre <= 0.0:
		return "meltdown_seconds_per_metre %s does not grow with the path" % reactor.meltdown_seconds_per_metre
	return ""


func test_every_seed_gets_a_fair_countdown_in_range() -> String:
	var plan: ReactorPlan = SeedSweep.load_reactor_plan()
	var validator: LevelValidator = SeedSweep.load_validator()
	if plan.error != "" or validator.error != "":
		return "data: %s %s" % [plan.error, validator.error]
	var radius: float = SeedSweep.ship_radius()
	var robot_plan: RobotPlan = SeedSweep.load_robot_plan()
	var countdowns: Array[float] = []
	for level_seed: int in SEEDS:
		# The shipped generator, shared with the seed sweeps
		# (`seed_level_cache.gd`, #1139); the level built as `_level` builds it.
		var level: LevelDef = SeedLevelCache.generator(level_seed).to_level_def(plan, radius, robot_plan)
		if level.error != "" or level.reactor == null:
			return "seed %d: no level with a reactor (%s)" % [level_seed, level.error]
		var path_mm: int = _path_mm(level)
		if path_mm == EscapePath.UNREACHABLE:
			return "seed %d: no escape path" % level_seed
		var seconds: float = level.reactor.meltdown_ticks_for_path(path_mm) / float(ReactorState.TICKS_PER_SECOND)
		if seconds < MIN_SECONDS or seconds > MAX_SECONDS:
			return "seed %d: countdown %.2f s outside %s..%s" % [level_seed, seconds, MIN_SECONDS, MAX_SECONDS]
		var flying: float = path_mm / float(RobotSpawn.SCALE) / validator.escape_speed_mps
		if seconds < MIN_RATIO * flying:
			return "seed %d: countdown %.2f s under %.1f times the %.2f s escape" % [level_seed, seconds,
					MIN_RATIO, flying]
		countdowns.append(seconds)
	countdowns.sort()
	print("  meltdown countdown over seeds 0..%d: min %.2f s, median %.2f s, max %.2f s" % [SEEDS - 1,
			countdowns[0], countdowns[SEEDS / 2], countdowns[SEEDS - 1]])
	return ""


func test_a_longer_escape_path_gets_a_longer_countdown() -> String:
	var plan: ReactorPlan = SeedSweep.load_reactor_plan()
	var modules: Array[ModuleDef] = SeedSweep.load_modules()
	var last_path: int = -1
	var last_ticks: int = -1
	for level_seed: int in ORDERED_SEEDS:
		var level: LevelDef = _level(level_seed, modules, plan)
		var path_mm: int = _path_mm(level)
		var ticks: int = level.reactor.meltdown_ticks_for_path(path_mm)
		if ticks != _formula_ticks(level.reactor, path_mm):
			return "seed %d: %d ticks, the formula gives %d" % [level_seed, ticks,
					_formula_ticks(level.reactor, path_mm)]
		if path_mm <= last_path:
			return "seed %d: path %d mm not longer than %d mm; pick other seeds" % [level_seed, path_mm, last_path]
		if ticks <= last_ticks:
			return "seed %d: %d ticks for %d mm, not more than %d ticks for %d mm" % [level_seed, ticks,
					path_mm, last_ticks, last_path]
		last_path = path_mm
		last_ticks = ticks
	return ""


func test_the_same_seed_gets_the_same_countdown() -> String:
	var plan: ReactorPlan = SeedSweep.load_reactor_plan()
	var modules: Array[ModuleDef] = SeedSweep.load_modules()
	var first: LevelDef = _level(ORDERED_SEEDS[0], modules, plan)
	var second: LevelDef = _level(ORDERED_SEEDS[0], modules, plan)
	var a: int = first.reactor.meltdown_ticks_for_path(_path_mm(first))
	var b: int = second.reactor.meltdown_ticks_for_path(_path_mm(second))
	return "" if a == b else "%d ticks then %d ticks for the same seed" % [a, b]
