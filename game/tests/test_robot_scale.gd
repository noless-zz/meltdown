extends RefCounted

## A robot-count scale for the generator (#991, RUN-1, GEN-1, GEN-2, GEN-3,
## ARC-2): `RobotPlan.scaled` follows the rounding and cap rule in its class
## comment; the default scale gives every level of seeds 0..999 exactly as the
## plan without a scale; a scale of 1.3 over seeds 0..199 gives at least 20 %
## more robots with every level still passing `LevelValidator`; and the same
## seed and scale give the same level.

const SeedLevelCache := preload("res://tests/seed_level_cache.gd")
const DEFAULT_SEEDS: int = 1000
const BUSY_SEEDS: int = 200
const BUSY_SCALE: float = 1.3
const VALID: Dictionary = {"types": ["drone", "glider"], "min_per_level": 4, "max_per_level": 8,
		"max_per_module": 2, "min_start_distance": 20, "min_reactor_distance": 8,
		"near_start_distance": 40, "max_near_start": 2}


func _plan(changes: Dictionary = {}) -> RobotPlan:
	var data: Dictionary = VALID.duplicate(true)
	data.merge(changes, true)
	return RobotPlan.parse_json(JSON.stringify(data), SeedLevel.robot_texts())


static func _robots(level: LevelDef) -> String:
	var parts: Array[String] = []
	for spawn: RobotSpawn in level.robots.spawns:
		parts.append("%s %s %s" % [spawn.id, spawn.position_mm, spawn.facing_mm])
	return "|".join(parts)


func test_scaled_range_rounds_both_ends() -> String:
	var plan: RobotPlan = _plan()
	if plan.error != "":
		return plan.error
	# 4 * 1.3 = 5.2 -> 5, 8 * 1.3 = 10.4 -> 10; 4 * 0.5 = 2, 8 * 0.5 = 4;
	# 4 * 1.25 = 5, 8 * 1.25 = 10; 4 * 0.6 = 2.4 -> 2, 8 * 0.6 = 4.8 -> 5.
	var cases: Array = [[1.0, Vector2i(4, 8)], [1.3, Vector2i(5, 10)], [0.5, Vector2i(2, 4)],
			[1.25, Vector2i(5, 10)], [0.6, Vector2i(2, 5)], [0.0, Vector2i(0, 0)]]
	for case: Array in cases:
		var scaled: RobotPlan = plan.scaled(case[0])
		var got: Vector2i = Vector2i(scaled.min_per_level, scaled.max_per_level)
		if scaled.error != "" or got != case[1]:
			return "scale %s gave %s (error \"%s\"), expected %s" % [case[0], got, scaled.error, case[1]]
		if scaled.types != plan.types or scaled.radii_mm != plan.radii_mm \
				or scaled.max_per_module != plan.max_per_module \
				or scaled.max_near_start != plan.max_near_start \
				or scaled.min_start_distance_mm != plan.min_start_distance_mm:
			return "scale %s changed a key other than the count range" % case[0]
	if plan.min_per_level != 4 or plan.max_per_level != 8:
		return "scaling changed the plan itself"
	return ""


func test_cap_follows_modules_but_never_below_the_file_range() -> String:
	var plan: RobotPlan = _plan()
	# 4 modules: 3 outside the start's, 2 each, room for 6; the file's 8 stands.
	var small: RobotPlan = plan.scaled(2.0, 4)
	if small.min_per_level != 8 or small.max_per_level != 8:
		return "scale 2 in 4 modules gave %d..%d, expected 8..8" % [small.min_per_level, small.max_per_level]
	# 6 modules: room for 10; 16 is cut to 10 and the low end follows it down.
	var cut: RobotPlan = plan.scaled(3.0, 6)
	if cut.min_per_level != 10 or cut.max_per_level != 10:
		return "scale 3 in 6 modules gave %d..%d, expected 10..10" % [cut.min_per_level, cut.max_per_level]
	# 10 modules: room for 18, so 1.3 is not cut.
	var roomy: RobotPlan = plan.scaled(BUSY_SCALE, 10)
	if roomy.min_per_level != 5 or roomy.max_per_level != 10:
		return "scale 1.3 in 10 modules gave %d..%d" % [roomy.min_per_level, roomy.max_per_level]
	for modules: int in [0, 1, 2, 4, 10]:
		for scale: float in [1.0, 1.01, 1.3, 2.0, 10.0]:
			var scaled: RobotPlan = plan.scaled(scale, modules)
			if scaled.min_per_level < plan.min_per_level or scaled.max_per_level < plan.max_per_level:
				return "scale %s in %d modules went below the file's range: %d..%d" \
						% [scale, modules, scaled.min_per_level, scaled.max_per_level]
		var same: RobotPlan = plan.scaled(1.0, modules)
		if same.min_per_level != 4 or same.max_per_level != 8:
			return "scale 1 in %d modules gave %d..%d" % [modules, same.min_per_level, same.max_per_level]
	return ""


func test_bad_scale_is_an_error_naming_it() -> String:
	var plan: RobotPlan = _plan()
	for scale: float in [-0.1, RobotPlan.MAX_ROBOT_SCALE + 0.5, INF, NAN]:
		var scaled: RobotPlan = plan.scaled(scale)
		if not scaled.error.contains("robot_scale"):
			return "scale %s gave error \"%s\"" % [scale, scaled.error]
		if not scaled.types.is_empty():
			return "scale %s kept its types" % scale
	var inputs: SeedLevel = SeedLevelCache.inputs()
	var level: LevelDef = inputs.level_of(SeedLevelCache.generator(0), -1.0)
	if not level.error.contains("robot_scale"):
		return "level_of with scale -1 gave error \"%s\"" % level.error
	return ""


func test_default_scale_leaves_every_level_unchanged() -> String:
	var inputs: SeedLevel = SeedLevelCache.inputs()
	for level_seed: int in DEFAULT_SEEDS:
		var generator: MineGenerator = SeedLevelCache.generator(level_seed)
		var shipped: LevelDef = SeedLevelCache.level(level_seed)
		var scaled: LevelDef = generator.to_level_def(inputs.reactor_plan, inputs.tuning.radius,
				inputs.robot_plan.scaled(1.0, generator.placements.size()), inputs.debris_plan,
				inputs.miner_plan)
		if generator.output_hash() != SeedLevelCache.generated_hash(level_seed):
			return "seed %d: output_hash moved" % level_seed
		if _robots(scaled) != _robots(shipped):
			return "seed %d: robots differ at scale 1.0" % level_seed
		if SeedLevelCache.fingerprint(scaled) != SeedLevelCache.fingerprint(shipped):
			return "seed %d: level differs at scale 1.0" % level_seed
	return ""


func test_busier_scale_gives_more_robots_and_valid_levels() -> String:
	var inputs: SeedLevel = SeedLevelCache.inputs()
	var plain_total: int = 0
	var busy_total: int = 0
	for level_seed: int in BUSY_SEEDS:
		var generator: MineGenerator = SeedLevelCache.generator(level_seed)
		var plain: LevelDef = SeedLevelCache.level(level_seed)
		var busy: LevelDef = inputs.level_of(generator, BUSY_SCALE)
		if busy.error != "":
			return "seed %d at %s: %s" % [level_seed, BUSY_SCALE, busy.error]
		var failures: Array[String] = inputs.validate(busy, generator)
		if not failures.is_empty():
			return "seed %d at %s fails the validator: %s" % [level_seed, BUSY_SCALE, failures]
		plain_total += plain.robots.spawns.size()
		busy_total += busy.robots.spawns.size()
	var plain_mean: float = float(plain_total) / BUSY_SEEDS
	var busy_mean: float = float(busy_total) / BUSY_SEEDS
	print("  robot scale: mean robots over seeds 0..%d: %.2f at 1.0, %.2f at %s" \
			% [BUSY_SEEDS - 1, plain_mean, busy_mean, BUSY_SCALE])
	if busy_mean < plain_mean * 1.2:
		return "mean %.2f at %s is not 20 %% above %.2f at 1.0" % [busy_mean, BUSY_SCALE, plain_mean]
	return ""


func test_same_seed_and_scale_give_the_same_level() -> String:
	var inputs: SeedLevel = SeedLevelCache.inputs()
	for level_seed: int in [3, 41, 177]:
		var first: LevelDef = inputs.level_of(inputs.generate(level_seed), BUSY_SCALE)
		var second: LevelDef = inputs.level_of(inputs.generate(level_seed), BUSY_SCALE)
		if SeedLevelCache.fingerprint(first) != SeedLevelCache.fingerprint(second):
			return "seed %d at %s built two different levels" % [level_seed, BUSY_SCALE]
	return ""


func test_load_level_passes_the_scale_through() -> String:
	var level_seed: int = 7
	var plain: LevelDef = SeedLevel.load_level(level_seed)
	var busy: LevelDef = SeedLevel.load_level(level_seed, LevelSwitch.DEFAULTS_FILE, "", {}, BUSY_SCALE)
	if plain == null or busy == null:
		return "seed %d was rejected" % level_seed
	var inputs: SeedLevel = SeedLevelCache.inputs()
	var expected: LevelDef = inputs.level_of(inputs.generate(level_seed), BUSY_SCALE)
	if _robots(busy) != _robots(expected):
		return "load_level at %s placed other robots than level_of" % BUSY_SCALE
	if _robots(plain) != _robots(SeedLevelCache.level(level_seed)):
		return "load_level without a scale placed other robots than the shipped level"
	return ""
